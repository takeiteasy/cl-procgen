;;;; mesh-tests.lisp
;;;; Test suite for cl-procgen/mesh

(defpackage #:cl-procgen/mesh/test
  (:use #:cl #:fiveam #:cl-procgen/mesh))
(in-package #:cl-procgen/mesh/test)

(def-suite cl-procgen-mesh-suite :description "cl-procgen/mesh test suite")
(in-suite cl-procgen-mesh-suite)

(defun run-mesh-tests ()
  (run! 'cl-procgen-mesh-suite))

(defun %zero-field (rows cols)
  (make-array (list rows cols) :element-type 'single-float :initial-element 0.0))

;;; heightfield->mesh

(test heightfield->mesh-matches-make-plane-on-zero-field
  ;; An all-zero field must produce the exact same vertices/indices as
  ;; MAKE-PLANE with matching slices/stacks/width/depth -- this pins the
  ;; up-axis and winding conventions to MAKE-PLANE.
  (let* ((rows 5) (cols 7)
         (field (%zero-field rows cols))
         (mesh (heightfield->mesh field :width 3.0 :depth 2.0))
         (plane (common-shapes:make-plane 3.0 2.0 (1- cols) (1- rows))))
    (is (equalp (common-shapes:mesh-vertices mesh) (common-shapes:mesh-vertices plane)))
    (is (equalp (common-shapes:mesh-indices mesh) (common-shapes:mesh-indices plane)))
    (is (= 3 (common-shapes:mesh-dimensions mesh)))))

(test heightfield->mesh-counts
  (let* ((rows 4) (cols 6)
         (field (%zero-field rows cols))
         (mesh (heightfield->mesh field)))
    (is (= (* rows cols) (common-shapes:vertex-count mesh)))
    (is (= (* 2 (1- rows) (1- cols)) (common-shapes:triangle-count mesh)))))

(test heightfield->mesh-height-mapping
  (let* ((field (%zero-field 3 3)))
    (setf (aref field 1 1) 2.0)
    (let* ((mesh (heightfield->mesh field :height-scale 5.0 :base-height 1.0))
           (verts (common-shapes:mesh-vertices mesh))
           ;; vertex (row=1, col=1) is index 4 (0-based, cols=3 -> 1+1*3)
           (base (* 4 3)))
      (is (= 11.0 (aref verts (+ base 2)))))))

(test heightfield->mesh-normals-and-texcoords
  (let* ((field (%zero-field 4 4))
         (mesh (heightfield->mesh field :normals t :tex-coords t)))
    (is (not (null (common-shapes:mesh-normals mesh))))
    (is (= (* 3 (common-shapes:vertex-count mesh)) (length (common-shapes:mesh-normals mesh))))
    (is (not (null (common-shapes:mesh-tex-coords mesh))))
    (is (= (* 2 (common-shapes:vertex-count mesh)) (length (common-shapes:mesh-tex-coords mesh))))))

(test heightfield->mesh-rejects-degenerate-field
  (signals error (heightfield->mesh (%zero-field 1 5)))
  (signals error (heightfield->mesh (%zero-field 5 1))))

(test heightfield->mesh-from-diamond-square
  (let* ((rng (cl-procgen:make-rng :seed 42))
         (field (cl-procgen:diamond-square rng 4))
         (mesh (heightfield->mesh field :normals t)))
    (is (> (common-shapes:vertex-count mesh) 0))
    (is (> (common-shapes:triangle-count mesh) 0))
    (is (= 3 (common-shapes:mesh-dimensions mesh)))
    (is (every (lambda (v) (and (typep v 'single-float) (not (float-nan-p v))))
               (common-shapes:mesh-vertices mesh)))))

(defun float-nan-p (x)
  (/= x x))

;;; cave-grid->walls

(defun %bit-grid (rows cols &optional (initial 0))
  (make-array (list rows cols) :element-type 'bit :initial-element initial))

(test cave-grid->walls-single-solid-cell
  ;; A lone solid cell in a sea of open cells: all 4 sides are exposed
  ;; (4 wall quads), plus the default FLOOR caps every one of the 8 open
  ;; cells (8 floor quads). No CEILING by default.
  (let* ((grid (%bit-grid 3 3 0)))
    (setf (aref grid 1 1) 1)
    (let ((mesh (cave-grid->walls grid)))
      (is (= (* 12 4) (common-shapes:vertex-count mesh)))
      (is (= (* 12 2) (common-shapes:triangle-count mesh))))))

(test cave-grid->walls-fully-enclosed-cell-culled
  ;; An all-solid grid produces no interior faces -- only the border cells'
  ;; edges facing out of the grid are exposed, since face-culling checks
  ;; solid/solid neighbours as unexposed.
  (let* ((grid (%bit-grid 3 3 1))
         (mesh (cave-grid->walls grid :floor nil :ceiling nil)))
    ;; 4 corner cells x 2 exposed sides + 4 edge-middle cells x 1 exposed
    ;; side + 1 fully-interior cell x 0 = 12 exposed sides.
    (is (= (* 12 4) (common-shapes:vertex-count mesh)))))

(test cave-grid->walls-all-open-no-caps-is-empty
  (let* ((grid (%bit-grid 3 3 0))
         (mesh (cave-grid->walls grid :floor nil :ceiling nil)))
    (is (= 0 (common-shapes:vertex-count mesh)))
    (is (= 0 (common-shapes:triangle-count mesh)))))

(test cave-grid->walls-ceiling-adds-caps
  (let* ((grid (%bit-grid 2 2 0))
         (walls-only (cave-grid->walls grid :floor nil :ceiling nil))
         (with-ceiling (cave-grid->walls grid :floor nil :ceiling t)))
    (is (= 0 (common-shapes:vertex-count walls-only)))
    ;; 4 open cells x 1 ceiling quad each
    (is (= (* 4 4) (common-shapes:vertex-count with-ceiling)))))

(test cave-grid->walls-normals-and-texcoords
  (let* ((grid (%bit-grid 3 3 0)))
    (setf (aref grid 1 1) 1)
    (let ((mesh (cave-grid->walls grid :normals t :tex-coords t)))
      (is (not (null (common-shapes:mesh-normals mesh))))
      (is (= (* 3 (common-shapes:vertex-count mesh)) (length (common-shapes:mesh-normals mesh))))
      (is (not (null (common-shapes:mesh-tex-coords mesh))))
      (is (= (* 2 (common-shapes:vertex-count mesh)) (length (common-shapes:mesh-tex-coords mesh)))))))

(test cave-grid->walls-from-cellular-automata
  (let* ((rng (cl-procgen:make-rng :seed 9))
         (grid (cl-procgen:cellular-automata rng 40 40))
         (mesh (cave-grid->walls grid :ceiling t :normals t)))
    (is (> (common-shapes:vertex-count mesh) 0))
    (is (> (common-shapes:triangle-count mesh) 0))
    (is (every (lambda (v) (and (typep v 'single-float) (not (float-nan-p v))))
               (common-shapes:mesh-vertices mesh)))))

;;; marching-squares->mesh

(defun %ramp-field (rows cols)
  "A field that rises linearly from 0.0 (row 0) to 1.0 (last row), constant
   across columns."
  (let ((field (make-array (list rows cols) :element-type 'single-float)))
    (dotimes (row rows)
      (dotimes (col cols)
        (setf (aref field row col) (/ (cl-procgen:sf row) (cl-procgen:sf (1- rows))))))
    field))

(test marching-squares->mesh-all-below-iso-is-empty
  (let ((field (%zero-field 5 5)))
    (multiple-value-bind (mesh segments) (marching-squares->mesh field :iso 0.5)
      (is (= 0 (common-shapes:vertex-count mesh)))
      (is (null segments)))))

(test marching-squares->mesh-ramp-produces-boundary-segments
  (let ((field (%ramp-field 5 5)))
    (multiple-value-bind (mesh segments) (marching-squares->mesh field :iso 0.5)
      (is (> (length segments) 0))
      (is (> (common-shapes:vertex-count mesh) 0))
      (is (= (* 4 (length segments)) (common-shapes:vertex-count mesh))))))

(test marching-squares->mesh-interpolates-crossing-midpoint
  ;; On the linear ramp (row/4, rows 0-4), field values are 0, 0.25, 0.5,
  ;; 0.75, 1.0. An ISO of 0.6 crosses only between rows 2 (0.5) and 3
  ;; (0.75), at tt=0.4, i.e. world Y = lerp(y(row=2), y(row=3), 0.4). Since
  ;; the field is constant across columns, every emitted segment endpoint
  ;; must land on that same Y.
  (let* ((field (%ramp-field 5 5))
         (hd (/ (* 4.0 1.0) 2.0))
         (y2 (- (* 2.0 1.0) hd))
         (y3 (- (* 3.0 1.0) hd))
         (expected-y (cl-procgen:lerp y2 y3 0.4)))
    (multiple-value-bind (mesh segments) (marching-squares->mesh field :iso 0.6 :cell-size 1.0)
      (declare (ignore mesh))
      (is (> (length segments) 0))
      (dolist (seg segments)
        (dotimes (i 2)
          (is (< (abs (- (aref (aref seg i) 1) expected-y)) 1e-4)))))))

(test marching-squares->mesh-zero-height-still-returns-segments
  ;; HEIGHT 0.0 still walks the same contour topology (segments, and one
  ;; degenerate zero-area quad per segment) -- only the outline's callers
  ;; (via the second value) care that HEIGHT collapsed to zero.
  (let ((field (%ramp-field 5 5)))
    (multiple-value-bind (mesh segments) (marching-squares->mesh field :iso 0.5 :height 0.0)
      (is (> (length segments) 0))
      (is (= (* 2 (length segments)) (common-shapes:triangle-count mesh)))
      (is (every (lambda (v) (and (typep v 'single-float) (not (float-nan-p v))))
                 (common-shapes:mesh-vertices mesh))))))

(test marching-squares->mesh-from-diamond-square
  (let* ((rng (cl-procgen:make-rng :seed 5))
         (field (cl-procgen:diamond-square rng 6))
         (mesh (marching-squares->mesh field :iso 0.5 :normals t)))
    (is (every (lambda (v) (and (typep v 'single-float) (not (float-nan-p v))))
               (common-shapes:mesh-vertices mesh)))))
