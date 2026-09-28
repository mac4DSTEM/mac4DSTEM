# Diffraction-groups covariance accumulation on Accelerate — Gate D, 2026-09-28

Owner, 2026-09-28: "do the accelerate fix with the agreement fixture", after the profile in
`open-items.md` ("Diffraction groups at 32 × 32 is too slow in a Debug build").

## Diagnosis (registered before any code change)

`DiffractionEmbedding.accumulate` adds each binned vector's outer product to a d × d
double-precision sum in a scalar Swift loop, so the cost is O(positions × d²). `tools/embedding-profile`
measured this on synthetic 128² patterns. At `-Onone` (the project's Debug config, which the owner
runs), 1 000 patterns at 32 × 32 (d = 1024) take 90.7 s, 84.8 s of it in accumulate. At 16 × 16 the
same step takes 5.4 s, which is d² scaling. With `-O` the same 2 000 patterns take 1.0 s in total.
**Refuting observation:** if accumulate were not the cost, replacing it would leave the `-Onone`
time near 90 s.

**Change:** batch each tile's binned vectors and update the sum with one BLAS `cblas_dsyrk` (upper
triangle), then mirror the upper triangle into the lower once, before the covariance is formed.
`sumVec` keeps its scalar O(d) loop. `embed` and the projection are unchanged. `embed` is the next
cost in Debug (~4.9 s per 1 000 patterns): it is out of scope here, because vectorising `log1p`
would move its values.

## Predictions

- **P1 agreement** (new unit test; the old loop is copied verbatim into the test as the reference):
  on random vectors (d = 256 and 1024, positions across several batches), `sumOuter` agrees with
  the reference to max |Δ| / max |ref| ≤ 1e-12, and the new result is exactly symmetric. The
  difference comes only from summation order and fused multiply-adds.
- **P2 gated parity** (`tools/embedding-pca-parity`, against numpy/sklearn/py4DSTEM): 8 checks,
  0 failed, as before. Each gated error stays within 10 % of the baseline (A 7.157e-09, B 4.441e-16,
  C 2.541e-08, D 1.935e-06, E 4.721e-07, S2a 6.627e-16, S2b 0.000e+00; `parity-before.log`, exit 0).
- **P3 timing** (`tools/embedding-profile`, 1 000 patterns, 32 × 32): at `-Onone` the
  accumulate+tiles phase drops from 84.8 s to under 3 s, and the total to under 10 s (embed
  dominates). At `-O`, 2 000 patterns take no longer than before (1.0 s).
- Group labels and explained variance on the unit-test fixtures (`DiffractionEmbeddingTests`) are
  unchanged.
