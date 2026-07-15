;;;; heightmap.lisp
;;;; Diamond-square heightmap generation

(in-package #:common-generation)

(defun %ds-average (field size &rest coords)
  "Average the values of FIELD at the given (Y X) COORD pairs that fall
   within [0, SIZE), ignoring out-of-bounds ones."
  (let ((total 0.0) (count 0))
    (loop for (y x) on coords by #'cddr
          when (and (>= y 0) (< y size) (>= x 0) (< x size))
          do (incf total (aref field y x)) (incf count))
    (if (plusp count) (/ total count) 0.0)))

(defun diamond-square (rng n &key (roughness 0.5) (normalize t))
  "Generate a heightmap via the diamond-square algorithm. N is an exponent:
   the returned field is exactly (2^N + 1) x (2^N + 1), the only grid size
   the algorithm can fill without truncation. ROUGHNESS controls how quickly
   displacement shrinks each pass (lower is smoother; each pass's random
   jitter is scaled by ROUGHNESS raised to the pass index).

   Seeds the four corners with random values in [-1, 1), then alternates
   diamond steps (center of each square = average of its 4 corners + jitter)
   and square steps (center of each diamond = average of its up-to-4
   neighbors + jitter), halving the step size each pass until adjacent cells
   are filled.

   If NORMALIZE is true (the default), the result is rescaled in place to
   [0, 1] via NORMALIZE-ARRAY; otherwise raw values are returned, roughly in
   [-1, 1] but not clamped. Returns a (2^N+1 2^N+1) single-float array
   indexed (AREF field y x)."
  (let* ((size (1+ (expt 2 n)))
         (max-index (1- size))
         (field (make-array (list size size) :element-type 'single-float
                             :initial-element 0.0)))
    (setf (aref field 0 0) (rng-float-signed rng))
    (setf (aref field 0 max-index) (rng-float-signed rng))
    (setf (aref field max-index 0) (rng-float-signed rng))
    (setf (aref field max-index max-index) (rng-float-signed rng))
    (let ((step max-index) (scale 1.0))
      (loop while (> step 1)
            do (let ((half (floor step 2)))
                 ;; Diamond step: center of each STEP x STEP square.
                 (loop for y from half below size by step
                       do (loop for x from half below size by step
                                do (setf (aref field y x)
                                         (+ (%ds-average field size
                                                          (- y half) (- x half)
                                                          (- y half) (+ x half)
                                                          (+ y half) (- x half)
                                                          (+ y half) (+ x half))
                                            (* scale (rng-float-signed rng))))))
                 ;; Square step: midpoints of each diamond edge.
                 (loop for y from 0 below size by half
                       do (loop for x from (if (evenp (floor y half)) half 0) below size by step
                                do (when (or (/= 0 y) (/= 0 x))
                                     (setf (aref field y x)
                                           (+ (%ds-average field size
                                                            (- y half) x (+ y half) x
                                                            y (- x half) y (+ x half))
                                              (* scale (rng-float-signed rng)))))))
                 (setf step half)
                 (setf scale (* scale (sf roughness))))))
    (when normalize (normalize-array field))
    field))
