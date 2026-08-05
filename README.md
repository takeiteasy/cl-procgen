# cl-procgen

A Common Lisp library of procedural generation algorithms: seeded noise
(Perlin, Simplex, Worley, value, white), fractal combinators (fBm,
turbulence, ridged multifractal), cellular automata, and Poisson disc
sampling. Starts 2D, extends to 3D, and feeds
[`common-shapes`](../common-shapes) to turn generated caves and heightfields
into meshes.

## Features

- **RNG** (`rng.lisp`) — a seeded, deterministic lagged-Fibonacci generator:
  `make-rng`, uniform floats/ints/ranges, normal and exponential
  distributions, weighted choice, Fisher-Yates shuffle, and permutations.
- **Noise** (`noise.lisp`) — closure constructors returning `(lambda (x y z))`:
  `make-perlin-noise`, `make-simplex-noise`, `make-value-noise`,
  `make-white-noise`, `make-worley-noise`. Each accepts an optional `:seed`.
- **Fractal combinators** (`fractal.lisp`) — higher-order functions that take
  any noise function: `fbm`, `turbulence`, `ridged-multifractal`,
  `tileable-noise`, `curl-noise`.
- **Sampled fields** (`field.lisp`) — `noise-field-2d`/`noise-field-3d` bake
  fBm into native N-dimensional `single-float` arrays; `quantize-field`
  exports a normalized field as 8-bit values.
- **Cellular automata** (`cellular.lisp`) — `cellular-automata` generates
  cave-like bit grids via randomized fill + smoothing iterations.
- **Poisson disc sampling** (`sampling.lisp`) — `poisson-disc-sample` and
  `map-poisson-disc` (Bridson's algorithm) for evenly-spaced random points.
- **Drunkard's-walk caves** (`walk.lisp`) — `drunkards-walk` carves open space
  into a solid grid via one or more random walkers.
- **Maze generation** (`maze.lisp`) — `maze` builds a perfect maze via a
  randomized recursive backtracker, returned as either a wall bit-grid or raw
  per-cell wall flags.
- **BSP dungeons** (`dungeon.lisp`) — `bsp-dungeon` splits an area with binary
  space partitioning, carves a room per leaf, and joins them with corridors.
- **Diamond-square heightmaps** (`heightmap.lisp`) — `diamond-square` bakes a
  fractal heightfield into a `(2^n+1)` square single-float array.
- **Wave function collapse** (`wfc.lisp`) — `wave-function-collapse` generates
  a grid locally similar to a sample grid using the overlapping model:
  adjacency rules are learned automatically from N x N patterns cut from the
  sample (including bit grids from `cellular-automata`, `drunkards-walk`, etc.).
- **Mesh generation** (`mesh.lisp`, system `cl-procgen/mesh`) — a
  separate system, since it is the only part of this library that depends on
  `common-shapes`:
  - `heightfield->mesh` converts a 2D single-float field (from
    `noise-field-2d` or `diamond-square`) into a
    [`common-shapes`](../common-shapes) `mesh`, matching
    `common-shapes:make-plane`'s XY-plane/CCW-winding conventions with
    height written into Z.
  - `cave-grid->walls` extrudes the solid cells of a bit grid
    (`cellular-automata`, `drunkards-walk`, `bsp-dungeon`, `maze`) into a
    face-culled wall mesh, with optional floor/ceiling caps.
  - `marching-squares->mesh` extracts iso-contours from a 2D scalar field,
    returning both an extruded wall mesh and the raw 2D contour segments.

No runtime dependencies for the core `cl-procgen` system (only
[`fiveam`](https://github.com/lispci/fiveam) for tests). The optional
`cl-procgen/mesh` system depends on `common-shapes`.

## Dependencies

None at runtime. `fiveam` is required to run the test suite.

## Examples

```lisp
(ql:quickload :cl-procgen)
(use-package :cl-procgen)

;; Deterministic RNG
(let ((rng (make-rng :seed 42)))
  (rng-float rng)                ; => single-float in [0, 1)
  (rng-int rng 1 6))             ; => integer in [1, 6]

;; Seeded Perlin noise sampled directly
(let ((perlin (make-perlin-noise :seed 1)))
  (funcall perlin 1.5 2.5 0.0))

;; fBm built from any noise function
(let ((simplex (make-simplex-noise :seed 7)))
  (fbm simplex 1.0 2.0 0.0 :octaves 5 :lacunarity 2.0 :gain 0.5))

;; A baked 2D fBm heightfield, ready to feed into a heightmap mesh
(let* ((noise (make-perlin-noise :seed 3))
       (field (noise-field-2d noise 128 128 :scale 32.0 :octaves 5)))
  (aref field 64 64))             ; => single-float in [0, 1]

;; A cellular-automata cave grid
(let* ((rng (make-rng :seed 9))
       (grid (cellular-automata rng 80 40 :fill-chance 45 :iterations 5)))
  (aref grid 20 40))              ; => 0 (open) or 1 (wall)

;; Evenly-spaced random points
(poisson-disc-sample 100.0 100.0 5.0 :rng (make-rng :seed 11))

;; A drunkard's-walk cave
(let ((rng (make-rng :seed 12)))
  (drunkards-walk rng 80 40 :walkers 4 :fill-target 0.4))

;; A perfect maze, as a wall bit-grid ready to mesh
(let ((rng (make-rng :seed 13)))
  (maze rng 20 10))

;; A BSP room-and-corridor dungeon, with room metadata for entity placement
(multiple-value-bind (grid rooms) (bsp-dungeon (make-rng :seed 14) 80 50)
  (values (array-dimensions grid) (length rooms)))

;; A diamond-square heightmap, 2^7+1 = 129 square
(diamond-square (make-rng :seed 15) 7)

;; Wave function collapse: grow a cellular-automata cave sample into a
;; larger, locally-similar grid
(let* ((sample (cellular-automata (make-rng :seed 9) 20 20))
       (rng (make-rng :seed 16)))
  (wave-function-collapse rng sample 60 40))
```

Mesh generation is a separate system (it is the only part of this library
that depends on `common-shapes`):

```lisp
(ql:quickload :cl-procgen/mesh)

;; A noise-driven terrain mesh, ready for common-shapes
(let* ((noise (make-perlin-noise :seed 3))
       (field (noise-field-2d noise 65 65 :scale 32.0 :octaves 5))
       (mesh (cl-procgen/mesh:heightfield->mesh
              field :width 10.0 :depth 10.0 :height-scale 2.0
                    :normals t :tex-coords t)))
  (common-shapes:vertex-count mesh))

;; A cellular-automata cave, extruded into walls with a floor and ceiling
(let* ((rng (make-rng :seed 9))
       (grid (cellular-automata rng 40 40))
       (mesh (cl-procgen/mesh:cave-grid->walls
              grid :height 2.0 :ceiling t :normals t)))
  (common-shapes:triangle-count mesh))

;; Iso-contours from a heightfield via marching squares -- both the
;; extruded wall mesh and the raw 2D outline segments
(let* ((field (diamond-square (make-rng :seed 5) 6)))
  (multiple-value-bind (mesh segments)
      (cl-procgen/mesh:marching-squares->mesh field :iso 0.5)
    (values (common-shapes:triangle-count mesh) (length segments))))
```

## Future Work

Open work items — remaining `common-shapes` integration (marching cubes,
Poisson scatter, greedy meshing, arbitrary-polygon triangulation), 3D
algorithms, L-systems, voxel ray traversal, additional noise, and an
optimisation pass — are tracked in [`TICKETS.md`](TICKETS.md).

## License

```
The MIT License (MIT)

Copyright (c) 2026 George Watson

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
