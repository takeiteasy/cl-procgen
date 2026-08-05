;;;; rng.lisp
;;;; Seeded pseudo-random number generator (port of paul's lagged-Fibonacci generator)

(in-package #:cl-procgen)

(defconstant +rng-ssize+ 64
  "Size of the generator's state array (must be a power of two).")
(defconstant +rng-lag1+ 24)
(defconstant +rng-lag2+ 55)
(defconstant +rng-smask+ (1- +rng-ssize+))
(defconstant +rng-exhaust-limit+ +rng-lag2+)
(defconstant +rng-refill-count+ (- (* +rng-lag2+ 10) +rng-exhaust-limit+))
(defconstant +u64-mask+ #xFFFFFFFFFFFFFFFF)

(declaim (inline u64+))
(defun u64+ (a b)
  "Add A and B, wrapping to 64 bits."
  (logand (+ a b) +u64-mask+))

(defstruct (rng (:constructor %make-rng))
  "Lagged-Fibonacci PRNG state. Create with MAKE-RNG rather than the raw constructor."
  (state (make-array +rng-ssize+ :element-type '(unsigned-byte 64) :initial-element 0)
   :type (simple-array (unsigned-byte 64) (64)))
  (i 0 :type (unsigned-byte 32))
  (c 0 :type (unsigned-byte 32)))

(defun %rng-step (rng)
  "Advance the generator by one raw 64-bit output."
  (let ((state (rng-state rng))
        (i 0))
    (let ((new-rands (if (zerop (rng-c rng))
                          (progn (setf (rng-c rng) (1- +rng-exhaust-limit+))
                                 (1+ +rng-refill-count+))
                          (progn (decf (rng-c rng))
                                 1))))
      (dotimes (r new-rands)
        (setf i (rng-i rng))
        (setf (aref state (logand i +rng-smask+))
              (u64+ (aref state (logand (- i +rng-lag1+) +rng-smask+))
                    (aref state (logand (- i +rng-lag2+) +rng-smask+))))
        (incf (rng-i rng))))
    (aref state (logand i +rng-smask+))))

(defun make-rng (&key (seed 0))
  "Create and seed a new RNG. If SEED is 0 or NIL, seed from the current time.
   The generator is run forward 10,000 steps after seeding to decorrelate
   the effect of low-value seeds."
  (let* ((seed (logand (or (and seed (not (zerop seed)) seed) (get-universal-time))
                        +u64-mask+))
         (state (make-array +rng-ssize+ :element-type '(unsigned-byte 64) :initial-element 0)))
    (setf (aref state 0) seed)
    (loop for i from 1 below +rng-ssize+
          do (setf (aref state i) (u64+ (* i 2147483647) seed)))
    (let ((rng (%make-rng :state state :i 0 :c +rng-exhaust-limit+)))
      (dotimes (i 10000) (%rng-step rng))
      rng)))

(defun rng-u64 (rng)
  "Return a random (unsigned-byte 64)."
  (%rng-step rng))

(defun rng-float (rng)
  "Return a random single-float in [0, 1)."
  (/ (coerce (rng-u64 rng) 'single-float) (coerce +u64-mask+ 'single-float)))

(defun rng-float-signed (rng)
  "Return a random single-float in [-1, 1)."
  (- (* 2.0 (rng-float rng)) 1.0))

(defun rng-int (rng min max)
  "Return a random integer in the inclusive range [MIN, MAX]."
  (if (>= min max)
      min
      (let* ((span (1+ (- max min)))
             (wide (* (rng-u64 rng) span)))
        (+ min (floor wide (1+ +u64-mask+))))))

(defun rng-float-range (rng min max)
  "Return a random single-float in [MIN, MAX)."
  (lerp min max (rng-float rng)))

(defun rng-normal (rng &optional (mean 0.0) (stddev 1.0))
  "Return a normally-distributed random value ~ N(MEAN, STDDEV^2) via Box-Muller."
  (let (u v)
    (loop do (setf u (rng-float rng))
             (setf v (rng-float rng))
          while (<= u 1e-7))
    (let* ((mag (sqrt (* -2.0 (log u))))
           (z0 (* mag (cos (* +tau+ v)))))
      (+ mean (* z0 stddev)))))

(defun rng-exponential (rng lambda)
  "Sample the exponential distribution with rate parameter LAMBDA (> 0)."
  (if (<= lambda 0.0)
      0.0
      (let (u)
        (loop do (setf u (rng-float rng)) while (<= u 1e-7))
        (/ (- (log u)) lambda))))

(defun rng-weighted-choice (rng weights &key (key #'identity))
  "Choose an index into the sequence WEIGHTS proportional to each element's
   weight (as returned by KEY, default IDENTITY). Negative weights are treated
   as zero. Returns NIL if WEIGHTS is empty or all weights are non-positive."
  (let* ((v (coerce weights 'vector))
         (n (length v)))
    (when (zerop n)
      (return-from rng-weighted-choice nil))
    (let ((total 0.0d0))
      (loop for w across v
            do (incf total (max 0.0d0 (coerce (funcall key w) 'double-float))))
      (when (<= total 0.0d0)
        (return-from rng-weighted-choice nil))
      (let ((r (* (coerce (rng-float rng) 'double-float) total))
            (acc 0.0d0))
        (dotimes (i n)
          (incf acc (max 0.0d0 (coerce (funcall key (aref v i)) 'double-float)))
          (when (< r acc)
            (return-from rng-weighted-choice i)))
        (1- n)))))

(defun rng-shuffle (rng sequence)
  "Destructively shuffle the vector SEQUENCE in place using Fisher-Yates. Returns SEQUENCE."
  (loop for i from (1- (length sequence)) downto 1
        do (let ((j (rng-int rng 0 i)))
             (unless (= i j)
               (rotatef (aref sequence i) (aref sequence j)))))
  sequence)

(defun rng-permutation (rng n)
  "Return a fresh random permutation of the integers [0, N) as a
   (simple-array (unsigned-byte 32) (n))."
  (let ((perm (make-array n :element-type '(unsigned-byte 32))))
    (dotimes (i n) (setf (aref perm i) i))
    (rng-shuffle rng perm)
    perm))
