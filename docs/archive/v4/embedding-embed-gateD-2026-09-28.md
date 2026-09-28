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
