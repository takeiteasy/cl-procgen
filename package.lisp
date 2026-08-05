;;;; package.lisp
;;;; Package definition for cl-procgen

(defpackage #:cl-procgen
  (:nicknames #:cgen)
  (:use #:cl)
  (:export
   ;; Math utilities
   #:+pi+
   #:+tau+
   #:sf
   #:clamp
   #:lerp
   #:remap
   #:fast-floor
   #:fade
   #:smoothstep
   #:smootherstep
   #:hash-u32
   #:hash-3d
   #:hash->float
   #:normalize-array

   ;; RNG
   #:rng
   #:rng-p
   #:make-rng
   #:rng-u64
   #:rng-float
   #:rng-float-signed
   #:rng-int
   #:rng-float-range
   #:rng-normal
   #:rng-exponential
   #:rng-weighted-choice
   #:rng-shuffle
   #:rng-permutation

   ;; Noise constructors
   #:make-perlin-noise
   #:make-simplex-noise
   #:make-value-noise
   #:make-white-noise
   #:make-worley-noise

   ;; Fractal combinators
   #:fbm
   #:turbulence
   #:ridged-multifractal
   #:tileable-noise
   #:curl-noise

   ;; Sampled fields
   #:noise-field-2d
   #:noise-field-3d
   #:quantize-field

   ;; Cellular automata
   #:cellular-automata

   ;; Poisson disc sampling
   #:poisson-disc-sample
   #:map-poisson-disc

   ;; Drunkard's-walk caves
   #:drunkards-walk

   ;; Maze generation
   #:maze
   #:maze-flags->grid

   ;; BSP room-and-corridor dungeons
   #:bsp-dungeon
   #:dungeon-room
   #:dungeon-room-p
   #:dungeon-room-x
   #:dungeon-room-y
   #:dungeon-room-w
   #:dungeon-room-h

   ;; Diamond-square heightmaps
   #:diamond-square

   ;; Wave function collapse (overlapping model)
   #:wave-function-collapse))
