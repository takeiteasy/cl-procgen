;;;; walk.lisp
;;;; Drunkard's-walk (random-walk) cave generation

(in-package #:cl-procgen)

(defparameter %walk-directions #((0 . -1) (0 . 1) (-1 . 0) (1 . 0))
  "Cardinal step vectors as (DX . DY) pairs: west, east, north, south.")

(defun drunkards-walk (rng width height
                        &key (steps (floor (* width height) 2))
                             (walkers 1) fill-target (start :center))
  "Carve a cave-like pattern into a WIDTH x HEIGHT grid by running one or more
   random walkers ('drunkards') that dig out the cell they stand on and then
   take a random cardinal step, clamped to stay in bounds.

   WALKERS is the number of independent walkers to run in sequence (each
   starts fresh). STEPS is the number of steps each walker takes. START is
   either :CENTER (all walkers start at the grid center) or :RANDOM (each
   walker starts at a random cell). If FILL-TARGET is given, it is a fraction
   in (0, 1] of the grid's cells; carving stops early, across all walkers,
   once that fraction of cells has been carved.

   Returns a (HEIGHT WIDTH) bit array indexed as (AREF grid y x), where 1
   means solid/wall and 0 means carved/open. The grid starts entirely solid."
  (let* ((grid (make-array (list height width) :element-type 'bit :initial-element 1))
         (target-count (and fill-target (round (* fill-target width height))))
         (carved 0))
    (flet ((carve (x y)
             (when (= 1 (aref grid y x))
               (setf (aref grid y x) 0)
               (incf carved))))
      (dotimes (w walkers)
        (unless (and target-count (>= carved target-count))
          (multiple-value-bind (x y)
              (ecase start
                (:center (values (floor width 2) (floor height 2)))
                (:random (values (rng-int rng 0 (1- width)) (rng-int rng 0 (1- height)))))
            (carve x y)
            (dotimes (s steps)
              (when (and target-count (>= carved target-count))
                (return))
              (let* ((dir (aref %walk-directions (rng-int rng 0 3)))
                     (nx (clamp (+ x (car dir)) 0 (1- width)))
                     (ny (clamp (+ y (cdr dir)) 0 (1- height))))
                (setf x nx y ny)
                (carve x y)))))))
    grid))
