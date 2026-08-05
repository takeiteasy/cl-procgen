;;;; noise.lisp
;;;; Noise constructors: each MAKE-*-NOISE function returns a closure of (x y z)

(in-package #:cl-procgen)

;;; Gradient table shared by Perlin and Simplex noise

(defparameter *grad3*
  (make-array 12 :initial-contents
              (list #(1.0 1.0 0.0) #(-1.0 1.0 0.0) #(1.0 -1.0 0.0) #(-1.0 -1.0 0.0)
                    #(1.0 0.0 1.0) #(-1.0 0.0 1.0) #(1.0 0.0 -1.0) #(-1.0 0.0 -1.0)
                    #(0.0 1.0 1.0) #(0.0 -1.0 1.0) #(0.0 1.0 -1.0) #(0.0 -1.0 -1.0)))
  "The 12 edge-midpoint gradients used by Perlin/Simplex noise.")

(declaim (inline %dot3))
(defun %dot3 (g x y z)
  "Dot product of gradient vector G with (X Y Z)."
  (+ (* (aref g 0) x) (* (aref g 1) y) (* (aref g 2) z)))

;;; Default permutation table (a fixed pseudo-random shuffle of 0-255)

(defparameter +default-perm+
  (make-array 256 :element-type '(unsigned-byte 16)
              :initial-contents
              '(182 232 51 15 55 119 7 107 230 227 6 34 216 61 183 36
                40 134 74 45 157 78 81 114 145 9 209 189 147 58 126 0
                240 169 228 235 67 198 72 64 88 98 129 194 99 71 30 127
                18 150 155 179 132 62 116 200 251 178 32 140 130 139 250 26
                151 203 106 123 53 255 75 254 86 234 223 19 199 244 241 1
                172 70 24 97 196 10 90 246 252 68 84 161 236 205 80 91
                233 225 164 217 239 220 20 46 204 35 31 175 154 17 133 117
                73 224 125 65 77 173 3 2 242 221 120 218 56 190 166 11
                138 208 231 50 135 109 213 187 152 201 47 168 185 186 167 165
                102 153 156 49 202 69 195 92 21 229 63 104 197 136 148 94
                171 93 59 149 23 144 160 57 76 141 96 158 163 219 237 113
                206 181 112 111 191 137 207 215 13 83 238 249 100 131 118 243
                162 248 43 66 226 27 211 95 214 105 108 101 170 128 210 87
                38 44 174 188 176 39 14 143 159 16 124 222 33 247 37 245
                8 4 22 82 110 180 184 12 25 5 193 41 85 177 192 253
                79 29 115 103 142 146 52 48 89 54 121 212 122 60 28 42))
  "The default fixed permutation table used when a noise function is unseeded.")

(defun %make-perm-table (seed)
  "Build a doubled 512-entry permutation table (each value in [0,256) appears
   at index i and i+256, enabling wraparound-free indexing). If SEED is given,
   a fresh table is shuffled via an internal RNG; otherwise +DEFAULT-PERM+ is used."
  (let ((base (if seed
                  (rng-permutation (make-rng :seed seed) 256)
                  +default-perm+))
        (table (make-array 512 :element-type '(unsigned-byte 16))))
    (dotimes (i 512)
      (setf (aref table i) (aref base (mod i 256))))
    table))

(declaim (inline %seed-offset))
(defun %seed-offset (seed)
  "Turn an arbitrary SEED into an integer offset folded into hash-based noise."
  (if seed (hash-u32 seed) 0))

;;; Perlin noise

(defun %perlin-sample (perm x y z)
  (let* ((fx (fast-floor x)) (fy (fast-floor y)) (fz (fast-floor z))
         (rx (- x fx)) (ry (- y fy)) (rz (- z fz))
         (gx (logand fx 255)) (gy (logand fy 255)) (gz (logand fz 255)))
    (flet ((p (idx) (aref perm (logand idx 511))))
      (let ((gi (make-array 8 :element-type 'fixnum))
            (n (make-array 8 :element-type 'single-float)))
        (dotimes (i 8)
          (let* ((inner (p (+ gz (logand i 1))))
                 (mid (p (+ gy (logand (ash i -1) 1) inner)))
                 (outer (p (+ gx (logand (ash i -2) 1) mid))))
            (setf (aref gi i) (mod outer 12))))
        (dotimes (i 8)
          (setf (aref n i)
                (%dot3 (aref *grad3* (aref gi i))
                       (- rx (logand (ash i -2) 1))
                       (- ry (logand (ash i -1) 1))
                       (- rz (logand i 1)))))
        (let ((u (fade rx)) (v (fade ry)) (w (fade rz))
              (nx (make-array 4 :element-type 'single-float)))
          (dotimes (i 4) (setf (aref nx i) (lerp (aref n i) (aref n (+ 4 i)) u)))
          (let ((nxy (make-array 2 :element-type 'single-float)))
            (dotimes (i 2) (setf (aref nxy i) (lerp (aref nx i) (aref nx (+ 2 i)) v)))
            (lerp (aref nxy 0) (aref nxy 1) w)))))))

(defun make-perlin-noise (&key seed)
  "Return a Perlin noise function of (x y z) -> single-float in [-1, 1].
   If SEED is given, a freshly shuffled permutation table is used."
  (let ((perm (%make-perm-table seed)))
    (lambda (x y z) (%perlin-sample perm x y z))))

;;; Simplex noise

(defun %simplex-sample (perm x y z)
  (let* ((f3 (/ 1.0 3.0)) (g3 (/ 1.0 6.0))
         (s (* (+ x y z) f3))
         (i (fast-floor (+ x s))) (j (fast-floor (+ y s))) (k (fast-floor (+ z s)))
         (tt (* (+ i j k) g3))
         (x0- (- i tt)) (y0- (- j tt)) (z0- (- k tt))
         (x0 (- x x0-)) (y0 (- y y0-)) (z0 (- z z0-)))
    (multiple-value-bind (i1 j1 k1 i2 j2 k2)
        (cond ((>= x0 y0)
               (cond ((>= y0 z0) (values 1 0 0 1 1 0))
                     ((>= x0 z0) (values 1 0 0 1 0 1))
                     (t (values 0 0 1 1 0 1))))
              (t (cond ((< y0 z0) (values 0 0 1 0 1 1))
                       ((< x0 z0) (values 0 1 0 0 1 1))
                       (t (values 0 1 0 1 1 0)))))
      (let* ((x1 (+ (- x0 i1) g3)) (y1 (+ (- y0 j1) g3)) (z1 (+ (- z0 k1) g3))
             (x2 (+ (- x0 i2) (* 2.0 g3))) (y2 (+ (- y0 j2) (* 2.0 g3))) (z2 (+ (- z0 k2) (* 2.0 g3)))
             (x3 (+ (- x0 1.0) (* 3.0 g3))) (y3 (+ (- y0 1.0) (* 3.0 g3))) (z3 (+ (- z0 1.0) (* 3.0 g3))))
        (flet ((p (idx) (aref perm (logand idx 255))))
          (flet ((contribution (x* y* z* i* j* k*)
                   (let ((tv (- 0.6 (+ (* x* x*) (* y* y*) (* z* z*)))))
                     (if (< tv 0.0)
                         0.0
                         (let* ((gi (mod (p (+ i* (p (+ j* (p (logand k* 255)))))) 12))
                                (tv2 (* tv tv)))
                           (* tv2 tv2 (%dot3 (aref *grad3* gi) x* y* z*)))))))
            (let ((n0 (contribution x0 y0 z0 i j k))
                  (n1 (contribution x1 y1 z1 (+ i i1) (+ j j1) (+ k k1)))
                  (n2 (contribution x2 y2 z2 (+ i i2) (+ j j2) (+ k k2)))
                  (n3 (contribution x3 y3 z3 (1+ i) (1+ j) (1+ k))))
              (* 32.0 (+ n0 n1 n2 n3)))))))))

(defun make-simplex-noise (&key seed)
  "Return a Simplex noise function of (x y z) -> single-float, roughly in [-1, 1]."
  (let ((perm (%make-perm-table seed)))
    (lambda (x y z) (%simplex-sample perm x y z))))

;;; White noise (uncorrelated per unit cell)

(defun make-white-noise (&key seed)
  "Return a white noise function of (x y z) -> single-float in [-1, 1]."
  (let ((so (%seed-offset seed)))
    (lambda (x y z)
      (let ((h (hash-3d (+ (fast-floor x) so) (fast-floor y) (fast-floor z))))
        (- (* 2.0 (hash->float h)) 1.0)))))

;;; Value noise (interpolated white noise)

(defun %value-corner (so x y z)
  (- (* 2.0 (hash->float (hash-3d (+ x so) y z))) 1.0))

(defun %value-sample (so x y z)
  (let* ((x0 (fast-floor x)) (x1 (1+ x0))
         (y0 (fast-floor y)) (y1 (1+ y0))
         (z0 (fast-floor z)) (z1 (1+ z0))
         (fx (- x x0)) (fy (- y y0)) (fz (- z z0))
         (u (fade fx)) (v (fade fy)) (w (fade fz))
         (n000 (%value-corner so x0 y0 z0)) (n001 (%value-corner so x0 y0 z1))
         (n010 (%value-corner so x0 y1 z0)) (n011 (%value-corner so x0 y1 z1))
         (n100 (%value-corner so x1 y0 z0)) (n101 (%value-corner so x1 y0 z1))
         (n110 (%value-corner so x1 y1 z0)) (n111 (%value-corner so x1 y1 z1))
         (nx00 (lerp n000 n100 u)) (nx01 (lerp n001 n101 u))
         (nx10 (lerp n010 n110 u)) (nx11 (lerp n011 n111 u))
         (nxy0 (lerp nx00 nx10 v)) (nxy1 (lerp nx01 nx11 v)))
    (lerp nxy0 nxy1 w)))

(defun make-value-noise (&key seed)
  "Return a value noise function of (x y z) -> single-float in [-1, 1]."
  (let ((so (%seed-offset seed)))
    (lambda (x y z) (%value-sample so x y z))))

;;; Worley (cellular) noise

(defun %worley-sample (so x y z)
  (let ((xi (fast-floor x)) (yi (fast-floor y)) (zi (fast-floor z))
        (min-dist most-positive-single-float))
    (loop for oz from -1 to 1 do
      (loop for oy from -1 to 1 do
        (loop for ox from -1 to 1 do
          (let* ((cx (+ xi ox)) (cy (+ yi oy)) (cz (+ zi oz))
                 (h (hash-3d (+ cx so) cy cz))
                 (px (+ cx (hash->float h)))
                 (py (+ cy (hash->float (hash-u32 h))))
                 (pz (+ cz (hash->float (hash-u32 (hash-u32 h)))))
                 (dx (- x px)) (dy (- y py)) (dz (- z pz))
                 (dist (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
            (when (< dist min-dist) (setf min-dist dist))))))
    (- 1.0 min-dist)))

(defun make-worley-noise (&key seed)
  "Return a Worley/cellular noise function of (x y z) -> single-float.
   Values increase toward the center of each cell (1.0 - nearest-feature-distance)."
  (let ((so (%seed-offset seed)))
    (lambda (x y z) (%worley-sample so x y z))))
