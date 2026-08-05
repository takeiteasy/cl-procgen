;;;; cl-procgen.asd
;;;; System definition for cl-procgen

(asdf:defsystem #:cl-procgen
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

(asdf:defsystem #:cl-procgen/test
  :description "Tests for cl-procgen"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :depends-on (#:cl-procgen #:fiveam)
  :serial t
  :components ((:file "tests")))

(asdf:defsystem #:cl-procgen/mesh
  :description "Converts cl-procgen grid data into common-shapes meshes"
  :author "George Watson <gigolo@hotmail.co.uk>"
  ;; MIT for now: the MVP (heightfield->mesh) needs no triangulation library.
  ;; If this system later grows arbitrary-polygon triangulation via the GPLv3
  ;; cl-earcut / cl-constrained-delaunay libraries, it will relicense to
  ;; GPLv3 at that point. cl-procgen itself stays MIT regardless.
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:cl-procgen #:common-shapes)
  :serial t
  :components ((:file "mesh")))

(asdf:defsystem #:cl-procgen/mesh/test
  :description "Tests for cl-procgen/mesh"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :depends-on (#:cl-procgen/mesh #:fiveam)
  :serial t
  :components ((:file "mesh-tests")))
