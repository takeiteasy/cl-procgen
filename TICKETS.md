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

- **#3 — Voxel ray traversal.** Fast grid/voxel ray marching (Amanatides-Woo
  3D DDA) for line-of-sight, block-picking, and lighting queries against
  generated grids — useful against `cellular-automata`/`bsp-dungeon`/`maze`
  bit-grids once 2D, and against the eventual 3D cellular automata grids.
  Open question: implement a 2D version now against the existing bit-grid
  generators, or hold until the 3D cellular automata TODO item lands and do
  both at once? Leaning toward 2D first since it's directly testable against
  what already exists, with a 3D generalization once 3D grids exist.

- **#4 — WFC tiled/authored-rules front-end.** `wfc.lisp`'s solver core
  (wave/entropy/observe/propagate/contradiction-restart) is model-agnostic —
  it only needs `patterns + weights + adjacency[4]`. The overlapping model
  (`wave-function-collapse`, closed #2) derives those from a sample grid via
  NxN pattern extraction. A tiled model would derive the same three from a
  fixed, hand- or data-authored tile set with explicit adjacency rules
  instead, feeding the same core. Needs a design conversation on the
  authoring format (data file vs. Lisp plist/struct API) before starting.

- **#5 — WFC symmetry transforms.** `wave-function-collapse`'s `symmetry`
  key currently only accepts `:none` and signals an error otherwise
  (`wfc.lisp`). Add `:reflect`/`:rotate`/`:all`, which should extend
  `%wfc-extract-patterns` to also insert the horizontally/vertically
  reflected and 90-degree-rotated variants of each pattern before
  deduplication (matching the reference implementation's flip/rotation
  flags).

- **#6 — WFC propagation is O(P^2) per cell, not O(P).** `%wfc-propagate` in
  `wfc.lisp` rechecks pattern support with a full linear scan
  (`%wfc-pattern-supported-p`) on every candidate removal. The reference WFC
  implementations maintain a per-cell-per-direction support-count matrix so
  each removal is amortized O(1). Left as-is for now since pattern counts
  (`P`) stay small for typical sample sizes; revisit if larger samples or
  bigger `n` make generation noticeably slow.

## Closed

- **#2 — Wave-function-collapse 2D generator.** Resolved: implemented the
  overlapping model as `wave-function-collapse` in `wfc.lisp` (learns
  adjacency from a sample grid's NxN patterns; no new authoring format
  needed, so existing bit-grid generators can be used as samples directly).
  The tiled/authored-rules variant is deferred as a fast-follow on the same
  solver core — see #4.
