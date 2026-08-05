;;;; tests.lisp
;;;; Test suite for cl-procgen

(defpackage #:cl-procgen/test
  (:use #:cl #:fiveam #:cl-procgen))
(in-package #:cl-procgen/test)

(def-suite cl-procgen-suite :description "cl-procgen test suite")
(in-suite cl-procgen-suite)

(defun run-generation-tests ()
  (run! 'cl-procgen-suite))

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

;;; walk

(test drunkards-walk-shape
  (let* ((rng (make-rng :seed 10))
         (grid (drunkards-walk rng 30 20)))
    (is (equal '(20 30) (array-dimensions grid)))
    (is (every (lambda (b) (or (= b 0) (= b 1)))
               (make-array 600 :displaced-to grid :element-type 'bit)))
    (is (some #'zerop (make-array 600 :displaced-to grid :element-type 'bit)))))

(test drunkards-walk-determinism
  (let ((g1 (drunkards-walk (make-rng :seed 11) 20 20))
        (g2 (drunkards-walk (make-rng :seed 11) 20 20)))
    (is (equalp g1 g2))))

;;; maze

(test maze-flags-shape
  (let* ((rng (make-rng :seed 12))
         (flags (maze rng 6 6 :format :flags)))
    (is (equal '(6 6) (array-dimensions flags)))))

(test maze-walls-shape-and-connectivity
  (let* ((rng (make-rng :seed 12))
         (grid (maze rng 6 6 :format :walls)))
    (is (equal '(13 13) (array-dimensions grid)))
    (dotimes (cy 6)
      (dotimes (cx 6)
        (is (= 0 (aref grid (1+ (* 2 cy)) (1+ (* 2 cx)))))))))

(test maze-determinism
  (let ((m1 (maze (make-rng :seed 13) 8 8))
        (m2 (maze (make-rng :seed 13) 8 8)))
    (is (equalp m1 m2))))

;;; dungeon

(test bsp-dungeon-shape-and-rooms
  (let* ((rng (make-rng :seed 14)))
    (multiple-value-bind (grid rooms) (bsp-dungeon rng 50 40)
      (is (equal '(40 50) (array-dimensions grid)))
      (is (every (lambda (b) (or (= b 0) (= b 1)))
                 (make-array 2000 :displaced-to grid :element-type 'bit)))
      (is (> (length rooms) 0))
      (is (every (lambda (r)
                   (loop for y from (dungeon-room-y r) below (+ (dungeon-room-y r) (dungeon-room-h r))
                         always (loop for x from (dungeon-room-x r) below (+ (dungeon-room-x r) (dungeon-room-w r))
                                      always (= 0 (aref grid y x)))))
                 rooms)))))

(test bsp-dungeon-determinism
  (multiple-value-bind (g1 r1) (bsp-dungeon (make-rng :seed 15) 50 40)
    (multiple-value-bind (g2 r2) (bsp-dungeon (make-rng :seed 15) 50 40)
      (is (equalp g1 g2))
      (is (= (length r1) (length r2))))))

;;; heightmap

(test diamond-square-shape
  (let ((field (diamond-square (make-rng :seed 16) 5)))
    (is (equal '(33 33) (array-dimensions field)))
    (is (every (lambda (v) (<= 0.0 v 1.0))
               (make-array 1089 :displaced-to field :element-type 'single-float)))))

(test diamond-square-unnormalized-finite
  (let ((field (diamond-square (make-rng :seed 16) 5 :normalize nil)))
    (is (every (lambda (v) (not (or (sb-ext:float-nan-p v) (sb-ext:float-infinity-p v))))
               (make-array 1089 :displaced-to field :element-type 'single-float)))))

(test diamond-square-determinism
  (let ((f1 (diamond-square (make-rng :seed 17) 4))
        (f2 (diamond-square (make-rng :seed 17) 4)))
    (is (equalp f1 f2))))

;;; wfc

(defparameter *wfc-test-sample*
  (make-array '(4 4) :element-type 'bit
              :initial-contents '((0 0 1 1)
                                   (0 0 1 1)
                                   (1 1 0 0)
                                   (1 1 0 0)))
  "A small 2x2-block checker pattern used to exercise WAVE-FUNCTION-COLLAPSE.")

(defun %wfc-window (arr y x n)
  "Extract a fresh copy of the N x N block of ARR with top-left corner
   (Y, X), for use as a hash-table key."
  (let ((w (make-array (list n n) :element-type (array-element-type arr))))
    (dotimes (dy n)
      (dotimes (dx n)
        (setf (aref w dy dx) (aref arr (+ y dy) (+ x dx)))))
    w))

(defun %wfc-output-matches-patterns-p (sample output n periodic-input)
  "True if every N x N window of OUTPUT equals one of the distinct N x N
   patterns %WFC-EXTRACT-PATTERNS learns from SAMPLE — i.e. WFC introduced
   no window that couldn't have come from SAMPLE. This checks the actual
   constraint WFC enforces (N x N pattern membership), unlike a same-domain
   single-cell adjacency check, which is vacuous for small binary samples."
  (multiple-value-bind (patterns weights)
      (cl-procgen::%wfc-extract-patterns sample n periodic-input)
    (declare (ignore weights))
    (let ((pattern-set (make-hash-table :test 'equalp)))
      (loop for p across patterns do (setf (gethash p pattern-set) t))
      (destructuring-bind (oh ow) (array-dimensions output)
        (loop for y from 0 to (- oh n)
              always (loop for x from 0 to (- ow n)
                           always (gethash (%wfc-window output y x n) pattern-set)))))))

(test wfc-shape
  (let* ((rng (make-rng :seed 20))
         (out (wave-function-collapse rng *wfc-test-sample* 12 8 :n 2)))
    (is (not (null out)))
    (is (equal '(8 12) (array-dimensions out)))
    (is (every (lambda (b) (or (= b 0) (= b 1)))
               (make-array 96 :displaced-to out :element-type 'bit)))))

(test wfc-determinism
  (let ((o1 (wave-function-collapse (make-rng :seed 21) *wfc-test-sample* 10 10 :n 2))
        (o2 (wave-function-collapse (make-rng :seed 21) *wfc-test-sample* 10 10 :n 2)))
    (is (equalp o1 o2))))

(test wfc-output-respects-sample-adjacency
  (let* ((rng (make-rng :seed 22))
         (out (wave-function-collapse rng *wfc-test-sample* 14 10 :n 2)))
    (is (not (null out)))
    (is (%wfc-output-matches-patterns-p *wfc-test-sample* out 2 t))))

(test wfc-cellular-automata-sample
  (let* ((sample (cellular-automata (make-rng :seed 23) 12 12))
         (out (wave-function-collapse (make-rng :seed 24) sample 16 16 :n 3)))
    (is (not (null out)))
    (is (equal '(16 16) (array-dimensions out)))
    (is (%wfc-output-matches-patterns-p sample out 3 t))))
