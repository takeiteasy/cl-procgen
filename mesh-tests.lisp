;;;; mesh-tests.lisp
;;;; Test suite for common-generation/mesh

(defpackage #:common-generation/mesh/test
  (:use #:cl #:fiveam #:common-generation/mesh))
(in-package #:common-generation/mesh/test)

(def-suite common-generation-mesh-suite :description "common-generation/mesh test suite")
(in-suite common-generation-mesh-suite)

(defun run-mesh-tests ()
  (run! 'common-generation-mesh-suite))

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
  (let* ((rng (common-generation:make-rng :seed 42))
         (field (common-generation:diamond-square rng 4))
         (mesh (heightfield->mesh field :normals t)))
    (is (> (common-shapes:vertex-count mesh) 0))
    (is (> (common-shapes:triangle-count mesh) 0))
    (is (= 3 (common-shapes:mesh-dimensions mesh)))
    (is (every (lambda (v) (and (typep v 'single-float) (not (float-nan-p v))))
               (common-shapes:mesh-vertices mesh)))))

(defun float-nan-p (x)
  (/= x x))
