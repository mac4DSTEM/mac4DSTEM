# Diffraction-groups projection on Accelerate — Gate D, 2026-09-28

Owner, 2026-09-28: "do the projection fix with an agreement fixture too". This is the third
step after `embedding-accumulate-gateD-2026-09-28.md` and `embedding-embed-gateD-2026-09-28.md`.

## Diagnosis (registered before any code change)

`DiffractionEmbedding.compute` projects every binned vector onto the principal components. That
is a scalar Float loop, O(positions × components × d), duplicated in the cached path and the
two-pass path. `profile-Onone-embed.log` measured it at 0.69 s per 1 000 patterns at 32 × 32
(8 components), now the largest step at `-Onone`. At `-O` it is 0.012 s per 2 000.

**Change:** one shared helper for both paths. `vDSP_vsub` centres the vector (the same
per-element subtraction as before, exact), then `vDSP_dotpr` takes each component's dot product
(the sum reordered, possibly fused). The coordinates are Float, as before.

**Refuting observation:** if the scalar loop were not the cost, the `-Onone` projection time would
stay near 0.7 s per 1 000.

## Predictions

- **P1 agreement** (new test; the old loop copied verbatim as the reference, plus an exact
  double-precision reference): on vectors like `embed`'s (d = 256 and 1 024, 8 components),
  max |new − old| ≤ 1e-5 × max |coordinate|. The new code's worst error against the double
  reference is no more than 2× the old code's. At least one coordinate differs in its last bits
  (anti-vacuity: the Accelerate path ran).
- **P2 downstream** (`tools/embedding-profile`, `-O`; baseline `labels-before.log`, reproducible
  in `labels-before-repeat.log`): on the four synthetic configurations, the k-means label hashes,
  group sizes and explained variances are **identical** to the baseline:
  - 1 000 × 16²: `a7c42350096315e7`;
  - 1 000 × 32²: `e9dfeb1d41935d97`;
  - 2 000 × 32²: `cf1b5624502eb81a`;
  - 2 000 × 16² with 6 groups: `436807d67e27680a`.

  A flipped label means a position sat within rounding of a k-means boundary. That would refute
  "identical", though not the science. It would be reported, not tuned.
- **P3 timing** (`-Onone`, 1 000 × 32²): the projection drops from 0.69 s to under 0.1 s.
- **P4:** the existing embedding tests stay green, and gated parity stays 8/0. Its check D
  (coordinates vs py4DSTEM scores, 1.405e-06 now) stays within its 5e-5 tolerance.
