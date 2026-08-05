;;;; field.lisp
;;;; Sampled 2D/3D noise fields (idiomatic replacements for paul's fbm2D/fbm3D)

(in-package #:cl-procgen)

(defun noise-field-2d (noise-fn width height
                        &key (z 0.0) (offset-x 0.0) (offset-y 0.0) (scale 1.0)
                          (octaves 4) (lacunarity 2.0) (gain 0.5) (normalize t))
  "Sample fBm of NOISE-FN over a WIDTH x HEIGHT grid, returning a
   (HEIGHT WIDTH) array of single-floats indexed as (AREF field y x).
   OFFSET-X/OFFSET-Y translate the sampled region; SCALE controls zoom
   (larger SCALE = lower frequency detail). When NORMALIZE is true (the
   default) the result is rescaled in place to [0, 1]."
  (let ((field (make-array (list height width) :element-type 'single-float)))
    (dotimes (y height)
      (dotimes (x width)
        (let ((nx (/ (+ offset-x x) scale))
              (ny (/ (+ offset-y y) scale)))
          (setf (aref field y x)
                (fbm noise-fn nx ny z :octaves octaves :lacunarity lacunarity :gain gain)))))
    (when normalize (normalize-array field))
    field))

(defun noise-field-3d (noise-fn width height depth
                        &key (offset-x 0.0) (offset-y 0.0) (offset-z 0.0) (scale 1.0)
                          (octaves 4) (lacunarity 2.0) (gain 0.5) (normalize t))
  "Sample fBm of NOISE-FN over a WIDTH x HEIGHT x DEPTH volume, returning a
   (DEPTH HEIGHT WIDTH) array of single-floats indexed as (AREF field z y x).
   See NOISE-FIELD-2D for the meaning of the offset/scale/normalize keywords."
  (let ((field (make-array (list depth height width) :element-type 'single-float)))
    (dotimes (z depth)
      (dotimes (y height)
        (dotimes (x width)
          (let ((nx (/ (+ offset-x x) scale))
                (ny (/ (+ offset-y y) scale))
                (nz (/ (+ offset-z z) scale)))
            (setf (aref field z y x)
                  (fbm noise-fn nx ny nz :octaves octaves :lacunarity lacunarity :gain gain))))))
    (when normalize (normalize-array field))
    field))

(defun quantize-field (field &key (max 255))
  "Return a fresh array of (unsigned-byte 8) (or wider, per MAX) values by
   scaling FIELD (assumed normalized to [0, 1]) by MAX and truncating.
   Useful for exporting a field as an 8-bit image or volume texture."
  (let ((out (make-array (array-dimensions field) :element-type '(unsigned-byte 8)))
        (flat-in (make-array (array-total-size field)
                              :element-type (array-element-type field)
                              :displaced-to field))
        (flat-out nil))
    (setf flat-out (make-array (array-total-size out)
                                :element-type (array-element-type out)
                                :displaced-to out))
    (dotimes (i (length flat-in))
      (setf (aref flat-out i) (truncate (* (clamp (aref flat-in i) 0.0 1.0) max))))
    out))
