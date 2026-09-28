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

## Outcome, same day

All three predictions held. Every log ends with exit 0 on its own line.

| | Before | After |
|---|---|---|
| P1 agreement (`DiffractionEmbeddingAccumulatorTests`, 3 tests: d 256 × 2 500, d 1024 × 1 100, d 49 × 37) | — | ≤ 1e-12 of max \|ref\|, exactly symmetric, `sumVec` bit-identical. 13/13 with the 10 existing embedding tests (`green2.log`) |
| P2 gated parity (`parity-before.log` / `parity-after.log`) | 8 checks, 0 failed | 8 checks, 0 failed; every printed error line identical |
| P3 `-Onone`, 1 000 × 32 × 32 (`profile-Onone.log` / `-after`) | 90.7 s, accumulate 84.8 s | **6.3 s**; accumulate + tile reads 0.02 s; embed 5.1 s |
| P3 `-Onone`, 1 000 × 16 × 16 | 10.3 s | 5.0 s (embed 4.7 s) |
| `-O`, 2 000 × 32 × 32 (`profile-O.log` / `-after`) | 1.0 s | 0.33 s |

The refuting observation did not occur: replacing accumulate removed its cost.

Mutations, each run against the new test class:
- the mirror removed,
- no final flush,
- α 0.5,
- `CblasLower`,
- `sumVec` one element short.

All five turned all 3 tests red.

A first green run executed **zero tests and exited 0**: two `-only-testing` flags had been passed as one
argument. It was caught by counting "Test case" lines, and the real run is `green2.log`.

Extrapolated to the owner's 29 241-position cube in a Debug build: about 3 min (was about 44 min). The
remaining cost is `embed` (per-pixel `log1p` and binning), and file I/O is not included. Optimised,
the same cube takes a few seconds.

## Independent refuter (Sonnet), same day

The refuter found no refuting observation. It checked the handback itself: both files were
`cmp`-identical to their pristine copies.
- **BLAS call: NOT REFUTED.** Row-major + Upper + Trans with lda = d writes Σ vᵀv into the
  row-major upper triangle (j ≥ i), which is what `finish`'s mirror expects (checked against the
  SDK's `cblas_new.h`). Its own wrong-direction mirror turned all 3 tests red
  (`refuter-mA-wrong-mirror-dir.log`, exit 65).
- **Coverage: NOT REFUTED.** A stale row at a chunk boundary (`batched = 1` after a flush) turned
  the 2 multi-chunk tests red. The below-one-chunk test stayed green, as it must
  (`refuter-mB-stale-reuse.log`).
- **P2: PARTLY REFUTED, stated plainly here.** The parity harness is 400 positions, a single chunk,
  so it is **blind to chunking**; its "identical" lines say nothing about flush or boundary
  correctness. P1's two multi-chunk tests are the only multi-chunk evidence. The mutations show
  they are sensitive at the boundaries.
- **Numerics, memory, cancellation, the two-pass path: NOT REFUTED.** 1e-12 sits above the n·ε
  reordering bound (about 2.4e-13 at n ≈ 1 100). The batch is fixed at 8 MB. Accumulation happens
  only in pass 1, and a cancelled run drops the unflushed batch with the local accumulator.
- **Wording.** An earlier line said the Debug build "explains" the 2026-09-24 stall. The probe
  excludes file I/O, so the stall is **consistent with** the Debug cost; the probe does not explain
  it.
