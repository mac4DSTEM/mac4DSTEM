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

## Outcome, same day

All four predictions held. Every log ends with exit 0 on its own line.

| | Before | After |
|---|---|---|
| P1 agreement (`DiffractionEmbeddingProjectionTests`: d 256 / k 8 / n 300, d 1024 / k 8 / n 200, d 49 / k 1 / n 150) | — | within 1e-5 of max \|coord\|; error vs the exact double projection ≤ 2× the old one's; at least one coordinate bit-different, in every fixture. 19/19 across the four embedding test classes (`green.log`) |
| P2 downstream, `-O` (`labels-before.log` / `labels-after.log`) | 4 hashes | **identical**: label hash, group sizes and all 8 explained variances, on all four configurations |
| P3 `-Onone`, 1 000 × 32² (`profile-Onone-project.log`) | project 0.69 s, total 1.76 s | project **0.001 s**, total **1.02 s** |
| P4 gated parity (`parity-project.log`) | 8 checks, 0 failed; D 1.405e-6 | 8 checks, 0 failed; D **1.056e-6** (closer to py4DSTEM) |

Mutations:
- **the subtraction reversed, the dot product one element short, no centring:** all red on the new tests;
- **always component 0:** red on the two tests with k = 8. It stays green at k = 1, as it must;
- **the cached-path output offset wrong:** red on 3 existing end-to-end `DiffractionEmbeddingTests`. The helper tests cannot see a call site.

The two-pass path (cube cache over 512 MB) is not reached by any test. It calls the same helper.

After all three Gate Ds, diffraction groups in a Debug build take about 1.0 s per 1 000 patterns at
32 × 32. That is about 20 s for the owner's 29 241-position cube ((1.02 − 0.33) s × 29.2 + 0.33 s) (synthetic data, file I/O excluded),
against about 44 min before. The largest remaining step is the eigen decomposition (0.33 s, fixed).

## Independent refuter (Sonnet), same day

**NOT REFUTED.** I checked the handback: both files `cmp`-identical, and its scratch stress test was
removed.
- **The helper call is correct.** Per the SDK's `vDSP.h` ("A and B are swapped"),
  `vDSP_vsub(mean, 1, vector, 1, …)` gives vector − mean.
- **The two-pass path, exercised directly.** With a one-line scratch edit forcing
  `cacheEverything = false`, all 10 `DiffractionEmbeddingTests` passed through it
  (`refuter-twopass-forced.log`). On that path, a wrong output offset turned 3 of them red
  (`refuter-twopass-offset-mutation.log`). This is the only evidence for that path; the shipped
  tests still do not reach it.
- **Accuracy under stress** (a 1e6 mean offset, cancelling basis rows, d 1024 with values to 64).
  Every case passed both bars. **The new code was 6–10× closer to the double-precision truth than
  the old loop** (error ratio 0.10–0.16), and the old loop's error was never near zero, so the 2×
  check cannot pass vacuously.
- **Mutations.** Its own two (components short by one; the mean subtracted twice) were red on all 3
  tests.
- **P2 scope.** The four synthetic configurations have well-separated clusters (top two components
  78–83 % of the variance). So "labels identical" is weak evidence for data near a k-means
  boundary, which this record already says.
