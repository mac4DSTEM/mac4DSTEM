# Diffraction-groups `embed` on Accelerate — Gate D, 2026-09-28

Owner, 2026-09-28: "do the embed log1p fix with an agreement fixture too", after the accumulate fix
(`embedding-accumulate-gateD-2026-09-28.md`) left `embed` as nearly all of the Debug cost.

## Diagnosis (registered before any code change)

`DiffractionEmbedding.embed` runs three scalar per-pixel loops over each 128² pattern: clamp and
`log1p` with a running max, then scale by 1/max, then box-bin. `tools/embedding-profile`
(`profile-Onone-after.log`, same day) measured 5.1 s of 6.3 s per 1 000 patterns at 32 × 32 in an
`-Onone` build, and 4.7 s at 16 × 16. That the cost does not depend on the bin size fits per-pixel
loops, not the binning. With `-O`, embed takes about 0.05 s per 1 000.

**Change:** when a pattern's float sum is finite (no NaN or ±Inf, no overflow), use `vDSP_vthr`
(clamp at 0), `vvlog1pf`, `vDSP_maxv`, `vDSP_vsmul`, and `vDSP_sve` per box row for the binning.
Otherwise fall back to the old scalar code unchanged. This keeps the non-finite semantics exactly:
Swift's `max(x, 0)` keeps NaN, which reaches the downstream refusal, and turns −Inf into 0.
`vDSP_vthr` would turn NaN into 0 and hide a bad pixel.

**Refuting observation:** if the per-pixel loops were not the cost, the `-Onone` embed time would
stay near 5 s per 1 000.

## Predictions

- **P1 agreement** (new tests; the old `embed` copied verbatim as the reference): on realistic 128²
  patterns (disks plus background, 16 × 16 and 32 × 32 bins, a non-square detector), every binned
  value agrees to ≤ 1e-6 relative. `vvlog1pf` may differ from `log1pf` by an ulp, and `vDSP_sve`
  sums in a different order.
- **P2 non-finite** (new test): patterns containing NaN, +Inf, −Inf, negatives and −0.0 give output
  **bit-identical** to the old code, NaN positions included.
- **P3 timing** (`tools/embedding-profile`, 1 000 × 32 × 32, `-Onone`): embed drops from 5.1 s to
  under 1 s, and the total from 6.3 s to under 2.5 s. At `-O` it is no slower.
- **P4:** the existing `DiffractionEmbeddingTests` (group labels, explained variance) stay green.
  The gated parity harness stays 8/0. It is blind to `embed` (both of its sides consume the app's
  own features, per its NC6), so it is a regression check only.

## Outcome, same day

P1, P3 and P4 held. **P2 held only in part.** As registered, it also listed negatives and −0.0 as
bit-identical. Those values are finite, so such a pattern takes the Accelerate path: it is covered by
P1's bound (it sits in the finite test set), not bitwise. NaN and ±Inf patterns are bit-identical, as
predicted. Every log ends with exit 0 on its own line.

| | Before | After |
|---|---|---|
| P1 agreement (`DiffractionEmbeddingEmbedTests`, 18 finite disk patterns: 128² at 16 and 32 bins, 96 × 110 at 16) | — | max relative **4.8e-7** (bar 1e-6); **5 986 of 9 216** values differ in their last bits, which proves the Accelerate path ran |
| P2 NaN / +Inf / −Inf patterns, at 16 and 32 bins | — | bit-identical to the old code |
| P3 `-Onone`, 1 000 × 32 × 32 (`profile-Onone-embed.log`) | embed 5.1 s, total 6.3 s | embed **0.53 s**, total **1.76 s** |
| P3 `-Onone`, 1 000 × 16 × 16 | embed 4.7 s, total 5.0 s | embed 0.26 s, total 0.63 s |
| `-O`, 2 000 × 32 × 32 (`profile-O-embed-x3.log`, three runs) | 0.33 s (embed 0.097 s) | 0.22–0.30 s (embed 0.054–0.056 s); one earlier run at 0.37 s was noise in untouched code |
| P4 `DiffractionEmbeddingTests` + gated parity | 10 green; 8 checks, 0 failed | 10 green; 8 checks, 0 failed. Errors shifted slightly because the features changed in their last bits (A 7.16 → 7.04e-9, C 2.54 → 2.85e-8, D 1.94 → 1.41e-6) |

Mutations, each run against the new test class:
- **always fall back:** red, **caught only by the anti-vacuity check**;
- **never fall back:** the NaN test red;
- **no scaling:** red;
- **bin rows shifted by one pixel:** red;
- **no clamp:** red.

The numbers the test prints are not in the xcodebuild log. They were read from the xcresult
(`xcresulttool get test-results tests`), through one measurement run with the bars set impossibly
tight, restored afterwards (`measure.log`).

Extrapolated to the owner's 29 241-position cube in a Debug build: under a minute (was about 44 min
before both fixes). The remaining Debug cost is spread over the projection (0.7 s per 1 000), the
eigen step and the tile path. File I/O is not included.

## Independent refuter (Sonnet), same day

The refuter found no bug. It checked the handback itself: both files were `cmp`-identical, and its
scratch test file was removed.
- **Non-finite semantics: no bug.** From `vDSP.h`, `vDSP_vthr` turns NaN into 0, as the code
  comment says. The finite-sum guard sends every NaN or ±Inf pattern to the scalar path before
  `vthr` sees it. `vthr` keeps −0.0 where Swift's `max` gives +0.0, but the box sum starts at +0,
  so the output is the same (scratch test). Subnormal pixels agree, and no flush-to-zero was seen.
- **Accuracy: PARTLY REFUTED, accepted.** 1e-6 is a property of the fixture (128², boxes ≤ 8 × 8),
  not a general bound. Two stresses exceed it:
  - a 512² detector binned to 16 (1 024-term box sums): **1.8e-6**;
  - a 1e7 spike over a 1e-3 background: **2.1e-6**.

  Neither is a science risk. Both are now `testStressedPatternsAgreeWithinTheWiderBar`, with a bar
  of 5e-6: green on the fix, red with the scaling removed (`green-stress.log`, `stress-m3.log`).
- **Mutations: none survived.** Its own `vDSP_maxv` over half the array, and the last box row
  dropped, both went red (`refuter-m6-maxv-half.log`, `refuter-m7-skip-row.log`).
- **Debug extrapolation: not refuted.** About 42 s by its own scaling (the eigen step is a fixed
  cost), which matches "under a minute". HDF5 I/O is excluded, as stated.
- **Other: no bug.** Pure function, locals only, sequential call sites; `Int32(count)` is safe up to
  4 096² detectors. One extra 64 KB allocation per 128² pattern is already inside the measured
  times.
