# 012 — Refusals not defaults: `probeSize` nil, a file's labels decide datacube-ness, DM4 calibration domains

Dates: 2026-09-04, 2026-09-05

Status: live

## Decision

Discovery refuses a rank-3 or rank-4 node only on a signal a known writer
stamps (emdfile/py4DSTEM's `_labels_`, or this app's `RGBA` dim / `rgba8`
units); `DatasetDescriptor.storedRank` records whether a cube was promoted
from rank 3. `probeSize` returns nil, and origin calibration throws
`probeNotMeasurable`, when a pattern has no finite intensity above zero,
rather than carrying on against an invented probe with a "measured"
provenance. DM4 axis order (scan vs. detector fastest) is decided from real-
space vs. reciprocal calibration units, not axis size; a contradictory or
mixed pair no longer refuses the file — it opens detector-fastest with no
pixel sizes and the reason in the log.

## Why

An absent number the user can supply beats a plausible one nobody measured.
A closed file for a wrong calibration takes the override away from the user
who is the only one positioned to fix it. Gate B refuted the first reason
given for a detector-plausibility floor: the calibration fixture is itself
stored rank 4, so a floor scoped to rank 3 would not have caught it.

## Governs

`DatasetDescriptor.storedRank`, `probeSize`, `probeNotMeasurable`,
`mac4DSTEM/Core/Data/DM4Reader.swift`'s axis-order logic.

## Sources

- 2026-09-04 "A file's own labels decide what is a datacube; no size floor", log line 319
- 2026-09-05 "Nothing measurable is a refusal, not a default", log line 343
- 2026-09-05 "DM4 calibration domains decide which axis pair is scan", log line 355
