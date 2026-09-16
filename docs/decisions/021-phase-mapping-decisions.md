# 021 — Phase mapping lands unvalidated; matrix stated by the user; β″ built in; angle modulo symmetry; chance guard; completeness

Dates: 2026-09-11, 2026-09-12
Status: live

## Decision
**Method choice** (from `docs/archive/v3/phase-mapping-method-choice-2026-09-11.md`, not the
log — see Sources). Vector matching is chosen over template matching, ANN and
NMF-only: its hardest dependency, accurate Bragg peak positions, is this
app's largest existing investment (`DiskDetection`, `TiledDiskDetection`, the
learned detector, `BraggVectors` computed once and shared by strain/ACOM).
Template matching swings 12 accuracy points on pre-processing; ANN needs
~10 000 simulated patterns per phase; NMF alone needs hand-labelling and
stays the exploratory step, not the quantitative one.

**Implementation** (in the log, 2026-09-12). Output is labelled `validation:
"none"` everywhere; step 3 (scoring against published ground truth) is
deliberately deferred, not skipped. β″ is built-in (Andersen et al. 1998,
Table 3 set 3), not import-only — an imported CIF does not survive a new
session, so a recipe built on one cannot replay. `PhaseDefinition.Role` marks
exactly one phase as matrix, stated by the user, never inferred or defaulted
to first-in-list. The in-plane angle is reported modulo the projected
symmetry (`matrix_in_plane_deg_mod_symmetry`) — spots alone cannot separate a
symmetry-equivalent orientation. The chance guard (`maximumVectorsPerEntry`)
stays although inert at shipped settings, since nothing else bounds what a
library's size costs on a vector-rich pattern. Completeness is a
chance-level test (beat `chanceMatchFraction` by 5×), not a minimum matched
fraction — a capped library can never reach a fraction on a richer pattern.

## Why
Each implementation choice answers a measured failure: 99.2%→5.5%
random-vector accuracy without the chance guard; 0% indexed on the fraction
test completeness replaced.

## Governs
`PhaseReferenceLibrary.swift`'s `PhaseDefinition`, `PhaseDefinition.Role`,
`chanceMatchFraction`; `PhaseVectorMatching.swift`;
`AppState+PhaseMapping.swift`'s `matrix_in_plane_deg_mod_symmetry`.

## Sources
2026-09-12 log lines 1151 (unvalidated), 1168 (β″ built-in), 1184 (matrix by
user), 1194 (angle mod symmetry), 1205 (chance guard), 1220 (completeness).
Method-choice reasoning is found ONLY in
`docs/archive/v3/phase-mapping-method-choice-2026-09-11.md` — the log has no
entry choosing between the four methods, only entries assuming vector
matching already chosen.
