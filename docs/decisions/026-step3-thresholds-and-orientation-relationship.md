# 026 — Step 3: Friedel floor, reach, detection default 0.5%, cliff ¾ pair radius, OR as parallel vectors, stopping rule

Dates: 2026-09-15, 2026-09-16

Status: live

## Decision

Three measured decisions turned step 3 on: a Friedel-pair floor (2 matched
vectors clear when survivors hold u and −u within the pair radius, 3
otherwise — T1 recall 6%→59%); an outer reach in the matcher
(`maximumVectorInvAngstrom`, default 0 = the detector) so a cropped pattern's
edge ring of unexplained maxima doesn't fail every position; a
relative-threshold reference excluding the direct beam
(`relativeReferenceMinimumRadiusPx`, default 0 = py4DSTEM's rule), measured
from the brightest maximum, not the array centre. The detection default
stays py4DSTEM's 0.5% (a per-dataset override is the user's to make). The
verdict cliff (`notIndexedAboveInvAngstrom`) moved 0.01→0.015 (detector
scaling 0.5→0.75px) after the half-pixel cliff was shown rejecting honest
6–11-vector fits. The orientation relationship (OR) ships stated as pairs of
parallel lattice vectors/planes/directions — frame-free by construction — a
list of library-frame degrees was tried first and shown to cut recall on
real positions (near 22°/67°) for a reason still open. 2026-09-16: step 3
gets a stopping rule — measure the peak cap, then the detector kernel, then
the T1 reference, each pre-registered; if still above 3% mislabelled after
those three, the pre-registration is revisited rather than the knobs.

## Why

Each threshold is a property of the dataset it was measured on until proven
on every dataset it will touch (ADR 029's threshold rule) — the six
successive improvements (98.26%→6.64%) are recorded precisely so the
stopping rule has a documented history to check against, not to justify
indefinite knob-turning.

## Governs

`mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift`'s
`maximumVectorInvAngstrom`, `relativeReferenceMinimumRadiusPx`,
`notIndexedAboveInvAngstrom`; `mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift`'s
`OrientationRelationship`; `tools/phase-map-probe`, `tools/thronsen-dataset`.

## Sources

- 2026-09-15 "the three decisions step 3 turned on, taken and measured", log line 1424
- 2026-09-15 "the detection default stays py4DSTEM's 0.5%", log line 1467
- 2026-09-15 "the orientation relationship lands inert, without a panel control" (superseded same day), log line 1478
- 2026-09-15 "the verdict cliff is three quarters of the pair radius, and the OR earns its control", log line 1493
- 2026-09-15 "the orientation relationship is stated as parallel vectors, and gets its control", log line 1512
- 2026-09-16 "step 3 gets a stopping rule, set before the measurements", log line 1526
