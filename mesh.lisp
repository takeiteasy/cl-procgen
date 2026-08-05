;;;; mesh.lisp
;;;; Convert cl-procgen grid data into common-shapes meshes

(defpackage #:cl-procgen/mesh
  (:nicknames #:cgen-mesh)
  (:use #:cl)
  (:export
   #:heightfield->mesh
   #:cave-grid->walls
   #:marching-squares->mesh))
(in-package #:cl-procgen/mesh)

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
           (hw (/ (cl-procgen:sf width) 2.0))
           (hd (/ (cl-procgen:sf depth) 2.0))
           (height-scale (cl-procgen:sf height-scale))
           (base-height (cl-procgen:sf base-height)))
      ;; Generate vertices
      (dotimes (row rows)
        (dotimes (col cols)
          (let* ((idx (+ col (* row cols)))
                 (u (/ (cl-procgen:sf col) (cl-procgen:sf slices)))
                 (v (/ (cl-procgen:sf row) (cl-procgen:sf stacks)))
                 (x (- (* u (cl-procgen:sf width)) hw))
                 (y (- (* v (cl-procgen:sf depth)) hd))
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

(defun %write-quad (vertices indices uvs quad-idx v0 v1 v2 v3)
  "Write one quad (as two CCW triangles) into VERTICES/INDICES (and UVS, if
   non-NIL) at QUAD-IDX. V0..V3 are (x y z) lists, given in CCW order as
   viewed from the face's outward normal, matching COMMON-SHAPES:MAKE-BOX's
   per-face vertex convention."
  (let ((vbase (* quad-idx 4 3))
        (ibase (* quad-idx 2 3))
        (vidx (* quad-idx 4)))
    (loop for corner in (list v0 v1 v2 v3)
          for i from 0
          do (destructuring-bind (x y z) corner
               (setf (aref vertices (+ vbase (* i 3))) x
                     (aref vertices (+ vbase (* i 3) 1)) y
                     (aref vertices (+ vbase (* i 3) 2)) z)))
    (setf (aref indices ibase) vidx
          (aref indices (+ ibase 1)) (+ vidx 1)
          (aref indices (+ ibase 2)) (+ vidx 2)
          (aref indices (+ ibase 3)) vidx
          (aref indices (+ ibase 4)) (+ vidx 2)
          (aref indices (+ ibase 5)) (+ vidx 3))
    (when uvs
      (let ((ubase (* quad-idx 4 2)))
        (setf (aref uvs ubase) 0.0 (aref uvs (+ ubase 1)) 0.0
              (aref uvs (+ ubase 2)) 1.0 (aref uvs (+ ubase 3)) 0.0
              (aref uvs (+ ubase 4)) 1.0 (aref uvs (+ ubase 5)) 1.0
              (aref uvs (+ ubase 6)) 0.0 (aref uvs (+ ubase 7)) 1.0)))))

(defparameter %wall-directions
  '((-1 0 :north) (1 0 :south) (0 -1 :west) (0 1 :east))
  "Grid offsets (DROW DCOL DIRECTION-KEY) checked around each solid cell in
   CAVE-GRID->WALLS to decide which side faces are exposed.")

(defun %grid-solid-p (grid row col)
  "T if (ROW, COL) is in bounds and non-zero (solid) in GRID."
  (destructuring-bind (rows cols) (array-dimensions grid)
    (and (>= row 0) (< row rows) (>= col 0) (< col cols)
         (not (zerop (aref grid row col))))))

(defun cave-grid->walls (grid &key (cell-size 1.0) (height 1.0)
                                    (floor t) (ceiling nil)
                                    normals tex-coords)
  "Convert a (HEIGHT WIDTH) bit (or integer) GRID -- as returned by
   COMMON-GENERATION:CELLULAR-AUTOMATA, COMMON-GENERATION:DRUNKARDS-WALK,
   COMMON-GENERATION:BSP-DUNGEON, or the wall-grid form of
   COMMON-GENERATION:MAZE, where a non-zero cell means solid/wall and a zero
   cell means open/floor -- into a COMMON-SHAPES:MESH of vertical wall quads.

   Cells are laid out on the XY plane centered at the origin (matching
   HEIGHTFIELD->MESH), each CELL-SIZE units square. A wall quad is emitted
   for each side of a solid cell that borders an open cell or the grid edge
   (face-culling -- fully enclosed solid cells contribute no geometry),
   spanning Z from 0 to HEIGHT. FLOOR and CEILING, if true, additionally cap
   every open cell with a floor quad at Z=0 (facing +Z) and/or a ceiling
   quad at Z=HEIGHT (facing -Z).

   Faces do not share vertices (one quad's worth of vertices per face, as in
   COMMON-SHAPES:MAKE-BOX), so NORMALS (if true, via
   COMMON-SHAPES:COMPUTE-NORMALS) and TEX-COORDS (a 0..1 UV square per face)
   produce hard-edged per-face results. A GRID with no exposed faces (e.g.
   all-open with FLOOR and CEILING both NIL) produces a valid empty mesh."
  (destructuring-bind (rows cols) (array-dimensions grid)
    (let ((cs (cl-procgen:sf cell-size))
          (h (cl-procgen:sf height))
          (side-faces 0)
          (open-cells 0))
      (dotimes (row rows)
        (dotimes (col cols)
          (if (%grid-solid-p grid row col)
              (dolist (d %wall-directions)
                (unless (%grid-solid-p grid (+ row (first d)) (+ col (second d)))
                  (incf side-faces)))
              (incf open-cells))))
      (let* ((quad-count (+ side-faces (if floor open-cells 0) (if ceiling open-cells 0)))
             (vertices (make-array (* quad-count 4 3) :element-type 'single-float
                                    :initial-element 0.0))
             (indices (make-array (* quad-count 2 3) :element-type '(unsigned-byte 32)
                                   :initial-element 0))
             (uvs (when tex-coords
                    (make-array (* quad-count 4 2) :element-type 'single-float
                                :initial-element 0.0)))
             (hw (/ (* cols cs) 2.0))
             (hd (/ (* rows cs) 2.0))
             (quad-idx 0))
        (flet ((cell-bounds (row col)
                 (values (- (* col cs) hw) (- (* (1+ col) cs) hw)
                         (- (* row cs) hd) (- (* (1+ row) cs) hd))))
          (dotimes (row rows)
            (dotimes (col cols)
              (multiple-value-bind (x0 x1 y0 y1) (cell-bounds row col)
                (if (%grid-solid-p grid row col)
                    (dolist (d %wall-directions)
                      (unless (%grid-solid-p grid (+ row (first d)) (+ col (second d)))
                        (ecase (third d)
                          (:north (%write-quad vertices indices uvs quad-idx
                                                (list x0 y0 0.0) (list x1 y0 0.0)
                                                (list x1 y0 h) (list x0 y0 h)))
                          (:south (%write-quad vertices indices uvs quad-idx
                                                (list x1 y1 0.0) (list x0 y1 0.0)
                                                (list x0 y1 h) (list x1 y1 h)))
                          (:west (%write-quad vertices indices uvs quad-idx
                                               (list x0 y1 0.0) (list x0 y0 0.0)
                                               (list x0 y0 h) (list x0 y1 h)))
                          (:east (%write-quad vertices indices uvs quad-idx
                                               (list x1 y0 0.0) (list x1 y1 0.0)
                                               (list x1 y1 h) (list x1 y0 h))))
                        (incf quad-idx)))
                    (progn
                      (when floor
                        (%write-quad vertices indices uvs quad-idx
                                      (list x0 y0 0.0) (list x1 y0 0.0)
                                      (list x1 y1 0.0) (list x0 y1 0.0))
                        (incf quad-idx))
                      (when ceiling
                        (%write-quad vertices indices uvs quad-idx
                                      (list x0 y0 h) (list x0 y1 h)
                                      (list x1 y1 h) (list x1 y0 h))
                        (incf quad-idx)))))))
          (let ((mesh (common-shapes:make-mesh :vertices vertices
                                                :indices indices
                                                :normals nil
                                                :tex-coords uvs
                                                :dimensions 3)))
            (if normals
                (common-shapes:compute-normals mesh)
                mesh)))))))

(defparameter %ms-case-edges
  #(() ((:l . :t)) ((:t . :r)) ((:l . :r))
    ((:r . :b)) ((:l . :t) (:r . :b)) ((:t . :b)) ((:l . :b))
    ((:b . :l)) ((:t . :b)) ((:t . :r) (:b . :l)) ((:r . :b))
    ((:l . :r)) ((:t . :r)) ((:l . :t)) ())
  "16-case marching squares lookup: for CASE = TL*1+TR*2+BR*4+BL*8 (bit set
   when a corner's value is >= the iso level), the list of segments to emit,
   each segment a (FROM-EDGE . TO-EDGE) pair over {:T :R :B :L} (top, right,
   bottom, left edges of the cell). Cases 5 and 10 are the ambiguous saddle
   cases, resolved here with a fixed (non-averaged) pairing.")

(defun %ms-lerp-point (iso v0 v1 p0 p1)
  "Interpolate the point along the edge P0->P1 (each a (X Y) list) where the
   scalar field crosses ISO, given the field values V0/V1 at the endpoints."
  (let ((tt (if (= v0 v1) 0.5 (/ (- iso v0) (- v1 v0)))))
    (list (cl-procgen:lerp (first p0) (first p1) tt)
          (cl-procgen:lerp (second p0) (second p1) tt))))

(defun marching-squares->mesh (field &key (iso 0.5) (cell-size 1.0)
                                          (height 1.0) normals)
  "Extract iso-contours from a 2D single-float FIELD (as returned by
   COMMON-GENERATION:NOISE-FIELD-2D or COMMON-GENERATION:DIAMOND-SQUARE) via
   marching squares, at threshold ISO.

   Returns two values:
   1. A COMMON-SHAPES:MESH extruding every contour segment into a vertical
      wall quad spanning Z from 0 to HEIGHT (pass :HEIGHT 0.0 for a
      degenerate, zero-area mesh if only the outline in the second value is
      wanted).
   2. The raw contour as a list of segments, each a 2-element vector #(V0 V1)
      of 2-element single-float points #(X Y) in world space (grid points on
      the XY plane centered at the origin, CELL-SIZE apart, matching
      HEIGHTFIELD->MESH's centering convention) -- a zero-dependency polyline
      output usable without COMMON-SHAPES.

   Edge crossings are linearly interpolated between corner values. NORMALS,
   if true, computes per-vertex normals via COMMON-SHAPES:COMPUTE-NORMALS."
  (destructuring-bind (rows cols) (array-dimensions field)
    (let* ((cs (cl-procgen:sf cell-size))
           (h (cl-procgen:sf height))
           (iso (cl-procgen:sf iso))
           (hw (/ (* (1- cols) cs) 2.0))
           (hd (/ (* (1- rows) cs) 2.0))
           (segments '()))
      (flet ((world (row col) (list (- (* col cs) hw) (- (* row cs) hd))))
        (dotimes (row (1- rows))
          (dotimes (col (1- cols))
            (let* ((c00 (aref field row col)) (c01 (aref field row (1+ col)))
                   (c11 (aref field (1+ row) (1+ col))) (c10 (aref field (1+ row) col))
                   (p00 (world row col)) (p01 (world row (1+ col)))
                   (p11 (world (1+ row) (1+ col))) (p10 (world (1+ row) col))
                   (case-idx (+ (if (>= c00 iso) 1 0) (if (>= c01 iso) 2 0)
                                (if (>= c11 iso) 4 0) (if (>= c10 iso) 8 0))))
              (flet ((edge-point (key)
                       (ecase key
                         (:t (%ms-lerp-point iso c00 c01 p00 p01))
                         (:r (%ms-lerp-point iso c01 c11 p01 p11))
                         (:b (%ms-lerp-point iso c10 c11 p10 p11))
                         (:l (%ms-lerp-point iso c00 c10 p00 p10)))))
                (dolist (seg (aref %ms-case-edges case-idx))
                  (push (list (edge-point (car seg)) (edge-point (cdr seg))) segments)))))))
      (setf segments (nreverse segments))
      (let* ((seg-count (length segments))
             (vertices (make-array (* seg-count 4 3) :element-type 'single-float
                                    :initial-element 0.0))
             (indices (make-array (* seg-count 2 3) :element-type '(unsigned-byte 32)
                                   :initial-element 0)))
        (loop for seg in segments
              for quad-idx from 0
              do (destructuring-bind ((x0 y0) (x1 y1)) seg
                   (%write-quad vertices indices nil quad-idx
                                (list x0 y0 0.0) (list x1 y1 0.0)
                                (list x1 y1 h) (list x0 y0 h))))
        (let ((mesh (common-shapes:make-mesh :vertices vertices
                                              :indices indices
                                              :normals nil
                                              :tex-coords nil
                                              :dimensions 3))
              (out-segments (mapcar (lambda (seg)
                                       (destructuring-bind ((x0 y0) (x1 y1)) seg
                                         (vector (vector (cl-procgen:sf x0)
                                                          (cl-procgen:sf y0))
                                                 (vector (cl-procgen:sf x1)
                                                          (cl-procgen:sf y1)))))
                                     segments)))
          (values (if normals (common-shapes:compute-normals mesh) mesh)
                  out-segments))))))
