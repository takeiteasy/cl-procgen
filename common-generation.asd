;;;; common-generation.asd
;;;; System definition for common-generation

(asdf:defsystem #:common-generation
  :description "A Common Lisp library of procedural generation algorithms (noise, fBm, cellular automata, Poisson disc sampling)"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :components ((:file "package")
               (:file "math")
               (:file "rng")
               (:file "noise")
               (:file "fractal")
               (:file "field")
               (:file "cellular")
               (:file "sampling")
               (:file "walk")
               (:file "maze")
               (:file "dungeon")
               (:file "heightmap")
               (:file "wfc")))

(asdf:defsystem #:common-generation/test
  :description "Tests for common-generation"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :depends-on (#:common-generation #:fiveam)
  :serial t
  :components ((:file "tests")))

(asdf:defsystem #:common-generation/mesh
  :description "Converts common-generation grid data into common-shapes meshes"
  :author "George Watson <gigolo@hotmail.co.uk>"
  ;; MIT for now: the MVP (heightfield->mesh) needs no triangulation library.
  ;; If this system later grows arbitrary-polygon triangulation via the GPLv3
  ;; cl-earcut / cl-constrained-delaunay libraries, it will relicense to
  ;; GPLv3 at that point. common-generation itself stays MIT regardless.
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:common-generation #:common-shapes)
  :serial t
  :components ((:file "mesh")))

(asdf:defsystem #:common-generation/mesh/test
  :description "Tests for common-generation/mesh"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :depends-on (#:common-generation/mesh #:fiveam)
  :serial t
  :components ((:file "mesh-tests")))
