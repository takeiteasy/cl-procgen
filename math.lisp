;;;; math.lisp
;;;; Shared numeric utilities for cl-procgen

(in-package #:cl-procgen)

;;; Constants

(defconstant +pi+ (coerce pi 'single-float)
  "PI as single-float.")

(defconstant +tau+ (* 2.0 +pi+)
  "2*PI, a full rotation in radians.")

;;; Coercion and interpolation

(declaim (inline sf))
(defun sf (x)
  "Coerce X to single-float."
  (coerce x 'single-float))

(declaim (inline clamp))
(defun clamp (x lo hi)
  "Clamp X to the inclusive range [LO, HI]."
  (cond ((< x lo) lo)
        ((> x hi) hi)
        (t x)))

(declaim (inline lerp))
(defun lerp (a b tt)
  "Linearly interpolate between A and B by TT (typically in [0,1])."
  (+ (* (- 1.0 tt) a) (* tt b)))

(declaim (inline remap))
(defun remap (x in-min in-max out-min out-max)
  "Remap X from range [IN-MIN, IN-MAX] to [OUT-MIN, OUT-MAX]."
  (+ out-min (/ (* (- x in-min) (- out-max out-min)) (- in-max in-min))))

(declaim (inline fast-floor))
(defun fast-floor (x)
  "Fast floor to an integer, matching paul's FASTFLOOR (truncate-toward-negative-infinity)."
  (if (>= x 0.0)
      (truncate x)
      (1- (truncate x))))

;;; Interpolation curves

(declaim (inline fade))
(defun fade (tt)
  "Perlin's quintic fade curve: 6t^5 - 15t^4 + 10t^3."
  (* tt tt tt (+ (* tt (- (* tt 6.0) 15.0)) 10.0)))

(defun smoothstep (edge0 edge1 tt)
  "Smooth Hermite interpolation between 0 and 1 as TT moves from EDGE0 to EDGE1."
  (if (= edge0 edge1)
      0.0
      (let ((x (clamp (/ (- tt edge0) (- edge1 edge0)) 0.0 1.0)))
        (* x x (- 3.0 (* 2.0 x))))))

(defun smootherstep (edge0 edge1 tt)
  "Higher-order smooth interpolation (zero first and second derivatives at the edges)."
  (if (= edge0 edge1)
      0.0
      (let ((x (clamp (/ (- tt edge0) (- edge1 edge0)) 0.0 1.0)))
        (fade x))))

;;; Integer hashing (used by value/white/Worley noise)

(declaim (inline hash-u32))
(defun hash-u32 (x)
  "Integer hash of a 32-bit unsigned value (murmur-style avalanche)."
  (let ((x (logand x #xFFFFFFFF)))
    (setf x (logand (* (logxor x (ash x -16)) #x45d9f3b) #xFFFFFFFF))
    (setf x (logand (* (logxor x (ash x -16)) #x45d9f3b) #xFFFFFFFF))
    (logxor x (ash x -16))))

(declaim (inline hash-3d))
(defun hash-3d (x y z)
  "Combine three integer coordinates into a single hash value."
  (hash-u32 (+ x (hash-u32 (+ y (hash-u32 z))))))

(declaim (inline hash->float))
(defun hash->float (h)
  "Map a hash value to a float in [0, 1)."
  (/ (float (logand h #xFFFFFF) 1.0) 16777216.0))

;;; Array normalization

(defun normalize-array (array)
  "Destructively normalize ARRAY (any rank) in place to the range [0, 1].
   If all elements are equal, the array is filled with 0.0."
  (let ((flat (make-array (array-total-size array)
                           :element-type (array-element-type array)
                           :displaced-to array)))
    (let ((minv most-positive-single-float)
          (maxv most-negative-single-float))
      (loop for v across flat
            when (< v minv) do (setf minv v)
            when (> v maxv) do (setf maxv v))
      (if (= minv maxv)
          (loop for i below (length flat) do (setf (aref flat i) 0.0))
          (let ((range (- maxv minv)))
            (loop for i below (length flat)
                  do (setf (aref flat i) (/ (- (aref flat i) minv) range)))))))
  array)
