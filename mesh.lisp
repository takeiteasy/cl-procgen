;;;; mesh.lisp
;;;; Convert common-generation grid data into common-shapes meshes

(defpackage #:common-generation/mesh
  (:nicknames #:cgen-mesh)
  (:use #:cl)
  (:export
   #:heightfield->mesh))
(in-package #:common-generation/mesh)

(defun heightfield->mesh (field &key (width 1.0) (depth 1.0) (height-scale 1.0)
                                     (base-height 0.0) normals tex-coords)
  "Convert a 2D single-float FIELD (indexed (AREF field row col), as returned
   by COMMON-GENERATION:NOISE-FIELD-2D or COMMON-GENERATION:DIAMOND-SQUARE)
   into a COMMON-SHAPES:MESH.

   The vertex grid lies on the XY plane centered at the origin, matching
   COMMON-SHAPES:MAKE-PLANE: WIDTH/DEPTH set the XY extent, and each sample
   FIELD(row, col) becomes that vertex's Z coordinate, scaled by
   HEIGHT-SCALE and offset by BASE-HEIGHT. Triangle winding is
   counter-clockwise, matching MAKE-PLANE, so the surface faces +Z when
   FIELD is all zero (in which case the output is identical to MAKE-PLANE).

   FIELD must be at least 2x2 (one grid cell); a smaller field signals an
   ERROR. NORMALS and TEX-COORDS, if true, request per-vertex normals
   (computed via COMMON-SHAPES:COMPUTE-NORMALS) and a UV grid (u, v in
   [0, 1], matching MAKE-PLANE)."
  (destructuring-bind (rows cols) (array-dimensions field)
    (when (or (< rows 2) (< cols 2))
      (error "heightfield->mesh: FIELD must be at least 2x2, got ~Dx~D" rows cols))
    (let* ((slices (1- cols))
           (stacks (1- rows))
           (vertex-count (* cols rows))
           (tri-count (* 2 slices stacks))
           (vertices (make-array (* vertex-count 3) :element-type 'single-float
                                  :initial-element 0.0))
           (indices (make-array (* tri-count 3) :element-type '(unsigned-byte 32)
                                 :initial-element 0))
           (uvs (when tex-coords
                  (make-array (* vertex-count 2) :element-type 'single-float
                              :initial-element 0.0)))
           (hw (/ (common-generation:sf width) 2.0))
           (hd (/ (common-generation:sf depth) 2.0))
           (height-scale (common-generation:sf height-scale))
           (base-height (common-generation:sf base-height)))
      ;; Generate vertices
      (dotimes (row rows)
        (dotimes (col cols)
          (let* ((idx (+ col (* row cols)))
                 (u (/ (common-generation:sf col) (common-generation:sf slices)))
                 (v (/ (common-generation:sf row) (common-generation:sf stacks)))
                 (x (- (* u (common-generation:sf width)) hw))
                 (y (- (* v (common-generation:sf depth)) hd))
                 (z (+ base-height (* height-scale (aref field row col))))
                 (base (* idx 3)))
            (setf (aref vertices base) x
                  (aref vertices (+ base 1)) y
                  (aref vertices (+ base 2)) z)
            (when tex-coords
              (let ((ubase (* idx 2)))
                (setf (aref uvs ubase) u
                      (aref uvs (+ ubase 1)) v))))))
      ;; Generate triangles (same diagonal + winding as MAKE-PLANE)
      (let ((tri-idx 0))
        (dotimes (j stacks)
          (dotimes (i slices)
            (let ((bl (+ i (* j cols)))
                  (br (+ i 1 (* j cols)))
                  (tl (+ i (* (1+ j) cols)))
                  (tr (+ i 1 (* (1+ j) cols))))
              (flet ((set-tri (a b c)
                       (let ((base (* tri-idx 3)))
                         (setf (aref indices base) a
                               (aref indices (+ base 1)) b
                               (aref indices (+ base 2)) c)
                         (incf tri-idx))))
                (set-tri bl br tr)
                (set-tri bl tr tl))))))
      (let ((mesh (common-shapes:make-mesh :vertices vertices
                                            :indices indices
                                            :normals nil
                                            :tex-coords uvs
                                            :dimensions 3)))
        (if normals
            (common-shapes:compute-normals mesh)
            mesh)))))
