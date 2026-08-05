;;;; cellular.lisp
;;;; Cellular automata grid generation (e.g. cave-like shapes)

(in-package #:cl-procgen)

(defun cellular-automata (rng width height
                           &key (fill-chance 45) (iterations 5) (survive 4) (starve 3))
  "Generate a cave-like pattern by randomly filling a WIDTH x HEIGHT grid and
   then iteratively smoothing it with a Conway-style rule: a cell is filled if
   it has more than SURVIVE filled neighbors, and cleared if it has fewer than
   STARVE filled neighbors (cells in between keep their previous state).

   FILL-CHANCE is the percentage (1-99) chance a cell starts filled.
   ITERATIONS is the number of smoothing passes to run (at least 1).
   Cells outside the grid bounds count as filled neighbors, which biases the
   grid toward solid walls at the edges.

   Returns a (HEIGHT WIDTH) bit array indexed as (AREF grid y x), where 1
   means filled/solid and 0 means empty/open."
  (let ((grid (make-array (list height width) :element-type 'bit))
        (fill-chance (clamp fill-chance 1 99)))
    (dotimes (y height)
      (dotimes (x width)
        (setf (aref grid y x) (if (< (rng-int rng 1 99) fill-chance) 1 0))))
    (dotimes (iter (max iterations 1))
      (let ((next (make-array (list height width) :element-type 'bit)))
        (dotimes (y height)
          (dotimes (x width)
            (let ((neighbours 0))
              (loop for ny from (1- y) to (1+ y)
                    do (loop for nx from (1- x) to (1+ x)
                             do (cond ((and (= nx x) (= ny y)))
                                      ((and (>= nx 0) (< nx width) (>= ny 0) (< ny height))
                                       (when (= 1 (aref grid ny nx)) (incf neighbours)))
                                      (t (incf neighbours)))))
              (setf (aref next y x)
                    (cond ((> neighbours survive) 1)
                          ((< neighbours starve) 0)
                          (t (aref grid y x)))))))
        (setf grid next)))
    grid))
