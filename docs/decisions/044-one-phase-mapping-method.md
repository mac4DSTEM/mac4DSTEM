# 044 — Vector matching is the app's one phase-mapping method; Thronsen's four are references

Dates: 2026-09-28

Status: live. Owner's decision ("yes to vector matching"), taken on the board's "The path" section.

## Decision

The app maps crystal phases one way: Bragg disks from the calibrated detector, then vector matching with the
known-variants rule (`PhaseVectorMatching.swift`). No second phase-mapping mode is added for NMF, template matching
or an ANN.

Thronsen et al.'s four methods (ADR 042) enter as **references in `tools/`**: run on inputs we choose (A3a on the
stride-3 cube now, A3 on the full dataset on the stronger Mac) and used to score the app. Their ANN is the one
**challenger**: a whole-pattern classifier on the Neural Engine may replace vector matching only if it beats it
under the T4 bar on data with truth, and it would arrive through the label → train route (track C, ADR 043), not
as a fourth mode.

## Why

Vector matching explains each call disk by disk (the owner's "disks claimed per phase" request), reuses the same
calibrated disk set as strain and orientation, needs no per-dataset training or hand-set thresholds, and passes
every T4 metric but one on Thronsen A. NMF decomposes the whole cube at once and needs hand-set thresholds per
component; template matching already serves orientation (ACOM). Several modes would multiply the surface and the
validation work for the same answer.

## Governs

ROADMAP B2 (ports only if they earn a place), the AI Analysis room's phase-mapping mode, the room plan (C5/B4).
