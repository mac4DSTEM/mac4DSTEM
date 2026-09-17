# 024 — Rotation null keeps the field's structure; zone-axis sweep is its own null

Dates: 2026-09-15

Status: live

## Decision

The rotation-calibration null draws phase-randomised surrogates of each
channel — the amplitude spectrum (hence correlation length, anisotropy,
mean) is kept, only the phases are randomised independently per channel,
destroying exactly the cross-channel gradient relation a rotation is. A
rank test over fifteen surrogates (Theiler et al. 1992) is then exact by
construction. Chosen over a block bootstrap because a block size is a
constant to defend and a spectrum is not. Separately, the zone-axis sweep
supplies its own null for the chance floor: on a real crystal a wrong axis
explains 11–25% of the vectors through shared reflections, so every axis in
a 49-axis sweep clears five times disc chance on a clean plant — the
question "is this axis better than a wrong one" needs the sweep's own median
as the comparison, at a measured 2× bar.

## Why

The morning's permutation null (shuffling scan positions) tested spatial
whiteness, not rotation structure; `tools/rotation-null-probe` reproduced why
it was wrong: a rotation-free field's certification rate rose with its
correlation length. For zone axis: the disc-chance rule alone could not
catch an owner-observed ⟨112⟩ false positive at 8%, because the true
comparison is against a wrong-axis sweep, not against noise.

## Governs

`RotationCalibration.solve`, `tools/rotation-null-probe`, `ZoneAxisFit`.

## Sources

- 2026-09-15 (night) "the rotation null keeps the field's structure", log line 1371
- 2026-09-15 (night) "the zone-axis sweep is its own null", log line 1392
