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
