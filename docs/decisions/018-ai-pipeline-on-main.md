# 018 — AI pipeline on `main`, sixth workspace, not one folder; PCA stays; ridge parked

Dates: 2026-09-11

Status: live

## Decision

The AI pipeline (`DiffractionEmbedding`, `Precipitates/*`) is ported to
`main` by hand-applied forward port, reversing the 2026-09-08 "leave on the
branch" call now that the reason for leaving it (dead Core in a tree about to
ship v3.0.0) has lapsed. It gets a sixth `WorkspaceArea` case, "AI Analysis"
— named by method, against the outcome-naming rule (D1), because the owner
judged discoverability decisive: precipitate density and diffraction
grouping fit no existing room's outcome-based subtitle. The AI work is NOT
consolidated into one `AI/` folder: only `LearnedDiskDetector.swift` imports
CoreML, and `Core/` stays organised by subject. PCA stays over NMF for now
(deterministic, fast, already gated; NMF remains a named comparison). The
ridge filter is parked, not retired — it is fixable (compare both Hessian
curvatures, not just the most negative), and it lost its own pre-registered
baseline on a tie for a correctable reason.

## Why

`WorkspaceArea` naming by method rather than outcome is a deliberate,
owner-overruled exception. An `AI/` folder would group by technique, which
D1 forbade when it renamed Bragg to "Strain & ACOM", and would mislabel two
files that are not AI.

## Governs

`WorkspaceArea` (sixth case), `mac4DSTEM/Core/ML/`,
`mac4DSTEM/Core/Analysis/Precipitates/`, `DiffractionEmbedding.swift`.

## Sources

- 2026-09-11 "the AI pipeline is ported onto `main`, reversing \"leave\"", log line 892
- 2026-09-11 "the AI work gets a sixth workspace, \"AI Analysis\"", log line 904
- 2026-09-11 "the AI work is NOT consolidated into one folder", log line 1033
- 2026-09-11 "PCA stays for now", log line 1067
- 2026-09-11 "the ridge filter is PARKED, not retired", log line 1089
