# TICKETS

This repo has no sr.ht tracker yet (no `.hut.scfg`), so issues are tracked
here until one exists.

## Open

- **#1 — `curl-noise` is not a true curl.** `fractal.lisp`'s `curl-noise`
  treats a single noise function's gradient as a stand-in vector potential
  and combines finite differences of it; the curl of a true gradient field
  is identically zero, so this only produces a plausible-looking swirl, not
  a guaranteed divergence-free flow field. A correct implementation needs
  three independently-seeded noise functions as the x/y/z components of a
  genuine vector potential, then takes the curl of *that*. Low priority —
  revisit when a feature actually needs divergence-free flow (e.g. particle
  advection through fluid-like noise).

- **#2 — Wave-function-collapse 2D generator.** Listed in the README TODO
  alongside the algorithms implemented in `walk.lisp`, `maze.lisp`,
  `dungeon.lisp`, and `heightmap.lisp`, but deferred: WFC is substantially
  larger than those four and has its own unresolved design fork that needs
  deciding before implementation starts —
  - **Tiled model**: a fixed tile set with hand- or data-authored adjacency
    rules; simpler, predictable output, but requires an input format for
    tiles/rules.
  - **Overlapping model**: adjacency rules learned automatically from a
    sample bitmap/grid via NxN pattern extraction; more general and less
    authoring effort, but higher implementation complexity (pattern
    frequency tables, backtracking on contradiction) and slower.
  Needs a design conversation (and likely its own plan) before starting.

- **#3 — Voxel ray traversal.** Fast grid/voxel ray marching (Amanatides-Woo
  3D DDA) for line-of-sight, block-picking, and lighting queries against
  generated grids — useful against `cellular-automata`/`bsp-dungeon`/`maze`
  bit-grids once 2D, and against the eventual 3D cellular automata grids.
  Open question: implement a 2D version now against the existing bit-grid
  generators, or hold until the 3D cellular automata TODO item lands and do
  both at once? Leaning toward 2D first since it's directly testable against
  what already exists, with a 3D generalization once 3D grids exist.
