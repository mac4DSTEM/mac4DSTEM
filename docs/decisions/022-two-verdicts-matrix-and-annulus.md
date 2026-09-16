# 022 — Two verdicts a user reads: matrix gets the last word; spotty annulus (withdrawn)

Dates: 2026-09-14

Status: live; the annulus clause was withdrawn the same session (see 023)

## Decision

A grain of the matrix phase seen on another orientation is reported as
`.matrix`, not "not indexed" — matrix removal never ran for that position,
but the crystal there IS aluminium, and a phase fraction computed over the
map is right only if it counts as aluminium. The evidence line carries the
numbers either way. The same entry also took, then withdrew within the
session, a rule that a Bragg-spot annulus makes the ellipse fit refuse
rather than warn: the shipped statistic (90th-percentile azimuthal bin at
4× the median) was measured by Gate B to be wrong in both directions — it
refused a legitimate amorphous halo and stopped firing on the multi-grain
case it was built for. The refuse-vs-warn question and its replacement test
are ADR 023.

## Why

A hatched "unknown" over a quarter of the scan would be a worse lie than a
neutral grey; the matrix label is the truthful answer to what the crystal at
that position is, whether or not matrix removal ran there.

## Governs

The phase-map `.matrix` label assignment in `mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift`.

## Sources

- 2026-09-14 "Two verdicts a user reads: the matrix gets the last word, and a
  spotty annulus is refused rather than flagged — TAKEN, THEN WITHDRAWN THE
  SAME SESSION", log line 1286
