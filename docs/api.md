# API Reference

Package `#:common-generation` (nickname `#:cgen`). All values are
`single-float` unless noted.

## RNG (`rng.lisp`)

| Function | Description |
|---|---|
| `(make-rng &key seed)` | Create a seeded RNG. `seed` 0/NIL seeds from the current time. |
| `(rng-u64 rng)` | Random `(unsigned-byte 64)`. |
| `(rng-float rng)` | Random float in `[0, 1)`. |
| `(rng-float-signed rng)` | Random float in `[-1, 1)`. |
| `(rng-int rng min max)` | Random integer in the inclusive range `[min, max]`. |
| `(rng-float-range rng min max)` | Random float in `[min, max)`. |
| `(rng-normal rng &optional mean stddev)` | Box-Muller normal sample. |
| `(rng-exponential rng lambda)` | Exponential distribution sample. |
| `(rng-weighted-choice rng weights &key key)` | Weighted index choice; NIL if all weights are non-positive. |
| `(rng-shuffle rng sequence)` | In-place Fisher-Yates shuffle of a vector. |
| `(rng-permutation rng n)` | Fresh random permutation of `[0, n)`. |

## Noise (`noise.lisp`)

Each constructor returns a closure `(lambda (x y z) ...)`. Pass `z = 0.0` for
2D sampling. All accept `&key seed` — an unseeded call uses a fixed default
table (Perlin/Simplex) or a fixed hash offset (value/white/Worley).

| Function | Notes |
|---|---|
| `(make-perlin-noise &key seed)` | Classic gradient noise, `[-1, 1]`. |
| `(make-simplex-noise &key seed)` | Simplex noise, roughly `[-1, 1]`. |
| `(make-value-noise &key seed)` | Interpolated hash noise, `[-1, 1]`. |
| `(make-white-noise &key seed)` | Uncorrelated per-cell noise, `[-1, 1]`. |
| `(make-worley-noise &key seed)` | Cellular/Voronoi-style noise; `1 - nearest-feature-distance`. |

## Fractal combinators (`fractal.lisp`)

Take a noise function as the first argument and combine octaves of it.

| Function | Notes |
|---|---|
| `(fbm noise-fn x y z &key octaves lacunarity gain)` | Weighted sum, normalized by total amplitude. |
| `(turbulence noise-fn x y z &key ...)` | Sum of `abs` octaves — billowy. |
| `(ridged-multifractal noise-fn x y z &key ...)` | Inverted-and-squared octaves — ridges. |
| `(tileable-noise noise-fn x y width height)` | Maps `(x,y)` onto a torus for seamless tiling. |
| `(curl-noise noise-fn x y z &key eps)` | **Placeholder** pseudo-curl — see `TICKETS.md`. |

## Sampled fields (`field.lisp`)

| Function | Notes |
|---|---|
| `(noise-field-2d noise-fn width height &key z offset-x offset-y scale octaves lacunarity gain normalize)` | Returns a `(height width)` array via `fbm`. |
| `(noise-field-3d noise-fn width height depth &key ...)` | Returns a `(depth height width)` array. |
| `(quantize-field field &key max)` | Returns a `(unsigned-byte 8)` array scaled by `max` (default 255). |

## Cellular automata (`cellular.lisp`)

| Function | Notes |
|---|---|
| `(cellular-automata rng width height &key fill-chance iterations survive starve)` | Returns a `(height width)` bit array (1 = solid). Out-of-bounds neighbours count as solid. |

## Poisson disc sampling (`sampling.lisp`)

| Function | Notes |
|---|---|
| `(poisson-disc-sample width height min-dist &key rng max-attempts predicate)` | Returns a simple-vector of `#(x y)` points. |
| `(map-poisson-disc fn width height min-dist &key rng max-attempts predicate)` | Callback form, no result vector allocated. |

## Drunkard's-walk caves (`walk.lisp`)

| Function | Notes |
|---|---|
| `(drunkards-walk rng width height &key steps walkers fill-target start)` | Returns a `(height width)` bit array (1 = solid, 0 = carved). Grid starts solid; walkers carve as they step. `start` is `:center` or `:random`. |

## Maze generation (`maze.lisp`)

| Function | Notes |
|---|---|
| `(maze rng width height &key format)` | Recursive-backtracker perfect maze. `format` `:walls` (default) returns a `(2h+1 2w+1)` bit grid (1 = wall); `:flags` returns the raw `(h w)` per-cell N/E/S/W wall-bitflag array. |
| `(maze-flags->grid flags)` | Converts a `:flags` array into the `:walls` bit-grid representation. |

## BSP dungeons (`dungeon.lisp`)

| Function | Notes |
|---|---|
| `(bsp-dungeon rng width height &key min-leaf max-leaf min-room room-margin max-depth)` | Returns two values: a `(height width)` bit array (1 = wall, 0 = floor) and a `simple-vector` of `dungeon-room` structs. Rooms are connected by L-shaped corridors. |
| `dungeon-room`, `dungeon-room-x/y/w/h` | Room accessors (top-left corner + size, in grid cells). |

## Diamond-square heightmaps (`heightmap.lisp`)

| Function | Notes |
|---|---|
| `(diamond-square rng n &key roughness normalize)` | Returns a `(2^n+1 2^n+1)` single-float field. `roughness` scales jitter falloff per pass; `normalize` (default `t`) rescales to `[0, 1]`. |

## Wave function collapse (`wfc.lisp`)

| Function | Notes |
|---|---|
| `(wave-function-collapse rng sample out-width out-height &key n periodic-input periodic-output symmetry max-retries)` | Overlapping-model WFC: learns N x N pattern adjacency/weights from `sample` (any grid of `eql`-comparable values, e.g. a bit grid) and collapses an `(out-height out-width)` wave to match. Returns a fresh array (same element-type as `sample`), or `nil` if every retry (up to `max-retries`) hit a contradiction. `symmetry` currently only accepts `:none`. |

## Math utilities (`math.lisp`)

`+pi+`, `+tau+`, `sf`, `clamp`, `lerp`, `remap`, `fast-floor`, `fade`,
`smoothstep`, `smootherstep`, `hash-u32`, `hash-3d`, `hash->float`,
`normalize-array`.

## Mesh generation (`mesh.lisp`)

Package `#:common-generation/mesh` (nickname `#:cgen-mesh`), system
`common-generation/mesh`. Depends on `common-generation` and
[`common-shapes`](../../common-shapes) — the only part of this library with
a runtime dependency. Not part of the core `#:common-generation` system.

| Function | Notes |
|---|---|
| `(heightfield->mesh field &key width depth height-scale base-height normals tex-coords)` | Converts a `(height width)` single-float `field` (`noise-field-2d`, `diamond-square`) into a `common-shapes:mesh`. Vertex grid on the XY plane centered at the origin, height written into Z (`base-height + height-scale * field-value`); CCW winding matching `common-shapes:make-plane` (an all-zero field produces an identical mesh to `make-plane`). `field` must be at least 2x2. |
