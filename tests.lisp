;;;; tests.lisp
;;;; Test suite for common-generation

(defpackage #:common-generation/test
  (:use #:cl #:fiveam #:common-generation))
(in-package #:common-generation/test)

(def-suite common-generation-suite :description "common-generation test suite")
(in-suite common-generation-suite)

(defun run-generation-tests ()
  (run! 'common-generation-suite))

;;; math

(test math-basics
  (is (= 0.5 (clamp 1.5 0.0 0.5)))
  (is (= 0.0 (clamp -1.0 0.0 0.5)))
  (is (= 0.5 (clamp 1.0 0.0 0.5)))
  (is (= 5.0 (lerp 0.0 10.0 0.5)))
  (is (= 50.0 (remap 5.0 0.0 10.0 0.0 100.0)))
  (is (= 3 (fast-floor 3.7)))
  (is (= -4 (fast-floor -3.2))))

(test hash-basics
  (is (typep (hash-u32 12345) '(unsigned-byte 32)))
  (is (<= 0.0 (hash->float (hash-3d 1 2 3)) 1.0))
  (is (/= (hash-3d 1 2 3) (hash-3d 3 2 1))))

(test normalize-array-basics
  (let ((arr (make-array 4 :element-type 'single-float
                          :initial-contents '(2.0 4.0 6.0 8.0))))
    (normalize-array arr)
    (is (= 0.0 (aref arr 0)))
    (is (= 1.0 (aref arr 3))))
  (let ((flat (make-array '(2 2) :element-type 'single-float :initial-element 5.0)))
    (normalize-array flat)
    (is (every (lambda (v) (= v 0.0))
               (make-array 4 :element-type 'single-float :displaced-to flat)))))

;;; rng

(test rng-determinism
  (let ((r1 (make-rng :seed 42))
        (r2 (make-rng :seed 42)))
    (is (equal (loop repeat 20 collect (rng-u64 r1))
               (loop repeat 20 collect (rng-u64 r2))))))

(test rng-float-range-bounds
  (let ((rng (make-rng :seed 1)))
    (is (every (lambda (v) (<= 0.0 v)) (loop repeat 200 collect (rng-float rng))))
    (is (every (lambda (v) (< v 1.0)) (loop repeat 200 collect (rng-float rng))))))

(test rng-int-bounds
  (let ((rng (make-rng :seed 2)))
    (is (every (lambda (v) (<= 3 v 9)) (loop repeat 500 collect (rng-int rng 3 9))))
    (is (= 5 (rng-int rng 5 5)))))

(test rng-permutation-is-valid
  (let* ((rng (make-rng :seed 3))
         (perm (rng-permutation rng 100))
         (sorted (sort (copy-seq perm) #'<)))
    (is (equal (coerce sorted 'list) (loop for i below 100 collect i)))))

(test rng-shuffle-preserves-elements
  (let ((rng (make-rng :seed 4))
        (v (make-array 10 :initial-contents '(0 1 2 3 4 5 6 7 8 9))))
    (rng-shuffle rng v)
    (is (equal (sort (coerce v 'list) #'<) '(0 1 2 3 4 5 6 7 8 9)))))

(test rng-weighted-choice-basics
  (let ((rng (make-rng :seed 5)))
    (is (null (rng-weighted-choice rng #())))
    (is (null (rng-weighted-choice rng #(0.0 0.0))))
    (is (= 2 (rng-weighted-choice rng #(0.0 0.0 1.0))))))

;;; noise

(test noise-functions-finite
  (dolist (ctor (list #'make-perlin-noise #'make-simplex-noise #'make-value-noise
                       #'make-white-noise #'make-worley-noise))
    (let ((fn (funcall ctor :seed 1)))
      (dotimes (i 20)
        (let ((v (funcall fn (* i 0.37) (* i 0.11) (* i 0.05))))
          (is (typep v 'single-float))
          (is (not (or (sb-ext:float-nan-p v) (sb-ext:float-infinity-p v)))
              "~A produced a non-finite value" ctor))))))

(test noise-seed-determinism
  (let ((a (make-perlin-noise :seed 7))
        (b (make-perlin-noise :seed 7)))
    (is (= (funcall a 1.23 4.56 0.0) (funcall b 1.23 4.56 0.0)))))

(test noise-seed-changes-output
  (let ((a (make-perlin-noise :seed 7))
        (b (make-perlin-noise :seed 8)))
    (is (/= (funcall a 1.23 4.56 0.0) (funcall b 1.23 4.56 0.0)))))

;;; fractal

(test fbm-basics
  (let ((fn (make-perlin-noise :seed 1)))
    (is (typep (fbm fn 1.0 2.0 3.0) 'single-float))
    (is (typep (turbulence fn 1.0 2.0 3.0) 'single-float))
    (is (typep (ridged-multifractal fn 1.0 2.0 3.0) 'single-float))))

;;; field

(test noise-field-2d-shape
  (let* ((fn (make-perlin-noise :seed 2))
         (field (noise-field-2d fn 10 6)))
    (is (equal '(6 10) (array-dimensions field)))
    (is (every (lambda (v) (<= 0.0 v 1.0))
               (make-array 60 :displaced-to field :element-type 'single-float)))))

(test noise-field-3d-shape
  (let* ((fn (make-perlin-noise :seed 2))
         (field (noise-field-3d fn 4 3 2)))
    (is (equal '(2 3 4) (array-dimensions field)))))

(test quantize-field-basics
  (let* ((field (make-array '(2 2) :element-type 'single-float
                             :initial-contents '((0.0 0.5) (1.0 0.25))))
         (q (quantize-field field)))
    (is (equal '(2 2) (array-dimensions q)))
    (is (= 0 (aref q 0 0)))
    (is (= 255 (aref q 1 0)))))

;;; cellular

(test cellular-automata-shape
  (let* ((rng (make-rng :seed 6))
         (grid (cellular-automata rng 30 20)))
    (is (equal '(20 30) (array-dimensions grid)))
    (is (every (lambda (b) (or (= b 0) (= b 1)))
               (make-array 600 :displaced-to grid :element-type 'bit)))))

;;; sampling

(test poisson-disc-min-distance
  (let* ((rng (make-rng :seed 8))
         (pts (poisson-disc-sample 40.0 40.0 4.0 :rng rng)))
    (is (> (length pts) 0))
    (is (every (lambda (p) (and (<= 0.0 (aref p 0) 40.0) (<= 0.0 (aref p 1) 40.0))) pts))
    (dotimes (i (length pts))
      (dotimes (j (length pts))
        (unless (= i j)
          (let* ((a (aref pts i)) (b (aref pts j))
                 (dx (- (aref a 0) (aref b 0))) (dy (- (aref a 1) (aref b 1))))
            (is (>= (sqrt (+ (* dx dx) (* dy dy))) (* 4.0 0.99)))))))))

(test poisson-disc-predicate
  (let* ((rng (make-rng :seed 9))
         (pts (poisson-disc-sample 40.0 40.0 4.0 :rng rng
                                    :predicate (lambda (x y) (declare (ignore y)) (< x 20.0)))))
    (is (every (lambda (p) (< (aref p 0) 20.0)) pts))))
