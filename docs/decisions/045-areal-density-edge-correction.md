# 045 — Areal precipitate density is edge-corrected (Miles–Lantuéjoul)

Dates: 2026-09-28

Status: live. Owner's go ("Fix it, Gate D"); record `archive/v4/areal-edge-correction-gateD-2026-09-28.md`.

## Decision

Objects touching the scan edge stay listed and uncounted, but the areal density no longer inherits that loss: each
counted object weighs W·H / ((W − bx − 1)(H − by − 1)) for its pixel bounding box, over the analysed area. Counts
shown stay integers; the density is no longer N ÷ area, and the help text and CSV say so.

## Why

Uncorrected, the density read low by the share of objects the edge band catches — on a synthetic foil at Thronsen A's
geometry (171 px at 13.89 nm) T1 read 0.890 of truth, corrected 1.017. Registered and predicted before the run;
the corrected rule passed all 18 cells after one harness defect (margin plates escaping overlap rejection) was
diagnosed with its prediction stated first; an independent refuter did not refute the diagnosis, the weight's
position count, the run order or the seven re-derived test values.

## Governs

`PrecipitateStatistics.density` / `edgeWeight` (the frame is required, no default); the Object Table's density and
CSV; T6's areal mode (`tools/volumetric-density-test`, `T6_MODE=areal`). Assumed: the frame is the whole scan;
not-indexed pixels inside it are not edges. A near-scan-sized object can carry a large weight; nothing flags it.
