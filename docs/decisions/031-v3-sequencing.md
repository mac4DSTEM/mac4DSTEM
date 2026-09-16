# 031 — v3 sequencing

Dates: 2026-08-28 (decided), 2026-09-03 (AnalysisRunner added)

Status: live

## Decision

Five items decided 2026-08-28. (1) v3 is a sequence, not a bet: all themes
are wanted, order comes from two scarce resources (one Gate B campaign in
flight at a time; the owner's driving time) plus hard dependencies —
calibration foundation, polar transform/I(q), grain segmentation, notebook
export, Materials Project importer may interleave; multi-phase → precipitates
→ EDX, and PDF/fluctuation microscopy once the polar transform exists, are
dependency-gated. (2) grain segmentation and multi-phase ship together —
segment, then identify each grain's phase; accepted consequence: multi-phase
needs point-group coverage, delaying segmentation even though segmentation
itself needs no crystal model. (3) the notebook exports the recipe as
py4DSTEM code, no comparison — a translation with an inline `DEVIATION` at
each divergent step. (4) Materials Project is an importer that embeds the
fetched structure with its provenance in the sidecar, with a required
warning that MP lattice parameters are DFT-relaxed (~1% off measured). (5)
precipitates enter v3 as a design session, implementation unscheduled,
settling four questions (per-object result shape, export, sidecar storage,
what a density refuses when it cannot state its denominator) — later
superseded in its segmentation approach by ADR 019. Added 2026-09-03: a run
layer (`AnalysisRunner`, one instance per family, with an injected host) is
the recorded next consolidation item, unscheduled; the run functions stay on
`AppState` until then (ADR 002).

## Why

Order comes from scarce review/driving capacity and real dependencies, not
from a fixed roadmap — stated explicitly so a later reader does not read the
ranking as a commitment.

## Governs

`ROADMAP.md`'s sequencing (once merged); the deferred `AnalysisRunner`
design (not yet in code — `mac4DSTEM/App/AppState.swift` still owns the run functions).

## Sources

- `ROADMAP.md` § "Decided 2026-08-28" (five items; the original `v3-plan.md` §1 is in git history before 2026-09-16)
- `ROADMAP.md` § "Decided 2026-08-28", the "Added 2026-09-03" AnalysisRunner line
- 2026-09-03 "The run functions stay on `AppState` (7c 4b)", log line 373
  (decisions.md's corroborating entry for the AnalysisRunner deferral)
