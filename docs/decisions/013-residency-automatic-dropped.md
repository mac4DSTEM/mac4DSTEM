# 013 — Residency `.automatic` dropped, not tuned

Dates: 2026-08-18 (decided); 2026-08-19 (implemented, archive)

Status: live

## Decision

`.automatic` residency was dropped from `ResidencyAdmission`, not tuned to a
better value; `measuredWorkingSetFraction` stays nil by decision, kept only
as the return path's shape, not a value someone should set.

## Why

The decision is recorded tersely in the v2 contract entry ("`.automatic`
residency dropped, not tuned"); the fuller original statement is in the
archived v2 session record: `.automatic` was dropped from `Residency` and
`measuredWorkingSetFraction` set nil, "kept as the return path" — not
dormant, not a half-finished feature.

## Governs

`mac4DSTEM/Core/Data/ResidentCube.swift`, `mac4DSTEM/Core/Data/LoadConfiguration.swift`'s
`ResidencyAdmission.measuredWorkingSetFraction`.

## Sources

- 2026-08-18 "The v2 contract and the three gates" (`.automatic` residency
  dropped, not tuned), log line 17
- Evidence: `docs/archive/v2-session-records/s3.md` (2026-08-19, the fuller
  original statement; verified present)
