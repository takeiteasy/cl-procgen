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
               (:file "heightmap")))

(asdf:defsystem #:common-generation/test
  :description "Tests for common-generation"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license "MIT"
  :depends-on (#:common-generation #:fiveam)
  :serial t
  :components ((:file "tests")))
