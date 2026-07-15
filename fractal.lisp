;;;; fractal.lisp
;;;; Higher-order noise combinators (fBm and friends) built from any noise function

(in-package #:common-generation)

(defun fbm (noise-fn x y z &key (octaves 4) (lacunarity 2.0) (gain 0.5))
  "Fractal Brownian motion: a weighted sum of NOISE-FN sampled at increasing
   frequency (scaled by LACUNARITY each octave) and decreasing amplitude
   (scaled by GAIN each octave), normalized by total amplitude."
  (let ((freq 1.0) (amp 1.0) (sum 0.0) (total 0.0))
    (dotimes (i octaves)
      (incf sum (* (funcall noise-fn (* x freq) (* y freq) (* z freq)) amp))
      (incf total amp)
      (setf freq (* freq lacunarity))
      (setf amp (* amp gain)))
    (/ sum total)))

(defun turbulence (noise-fn x y z &key (octaves 4) (lacunarity 2.0) (gain 0.5))
  "Turbulence: sum of absolute-valued octaves of NOISE-FN. Produces billowy,
   cloud-like patterns rather than smooth fBm."
  (let ((freq 1.0) (amp 1.0) (sum 0.0))
    (dotimes (i octaves)
      (incf sum (* (abs (funcall noise-fn (* x freq) (* y freq) (* z freq))) amp))
      (setf freq (* freq lacunarity))
      (setf amp (* amp gain)))
    sum))

(defun ridged-multifractal (noise-fn x y z &key (octaves 4) (lacunarity 2.0) (gain 0.5))
  "Ridged multifractal noise: inverts and squares each octave of NOISE-FN so
   that values near zero become sharp ridges. Useful for mountain ranges."
  (let ((freq 1.0) (amp 1.0) (sum 0.0))
    (dotimes (i octaves)
      (let ((v (- 1.0 (abs (funcall noise-fn (* x freq) (* y freq) (* z freq))))))
        (setf v (* v v))
        (incf sum (* v amp)))
      (setf freq (* freq lacunarity))
      (setf amp (* amp gain)))
    sum))

(defun tileable-noise (noise-fn x y width height)
  "Sample NOISE-FN so the result tiles seamlessly over [0,WIDTH) x [0,HEIGHT)
   by mapping (x,y) onto a torus."
  (let* ((nx (/ (* (cos (* (/ x width) +tau+)) width) +tau+))
         (ny (/ (* (sin (* (/ x width) +tau+)) width) +tau+))
         (nz (/ (* (cos (* (/ y height) +tau+)) height) +tau+)))
    (fbm noise-fn nx ny nz :octaves 1)))

(defun curl-noise (noise-fn x y z &key (eps 1e-3))
  "Compute a pseudo-curl vector field from the scalar NOISE-FN by finite
   differencing offset samples. Returns (values cx cy cz).

   PLACEHOLDER: this treats NOISE-FN's gradient as a stand-in vector
   potential, which is not a true curl (the curl of a true gradient field is
   identically zero) -- it produces visually plausible swirl but is not
   guaranteed divergence-free. A correct implementation needs three
   independently-seeded noise fields as the vector potential's components.
   See TICKETS.md."
  (let* ((eps (sf eps))
         (dx (/ (- (funcall noise-fn (+ x eps) y z) (funcall noise-fn (- x eps) y z)) (* 2.0 eps)))
         (dy (/ (- (funcall noise-fn x (+ y eps) z) (funcall noise-fn x (- y eps) z)) (* 2.0 eps)))
         (dz (/ (- (funcall noise-fn x y (+ z eps)) (funcall noise-fn x y (- z eps))) (* 2.0 eps))))
    (values (- dz dy) (- dx dz) (- dy dx))))
