# Decisions

An ADR here distils a settled question: what was decided, why, what it
governs. To add one: take the next number, write one file in
`docs/decisions/`, add one row below. The pre-2026-09-16 log (97 entries) is
archived verbatim at `docs/archive/decisions-log-2026-08-17-to-2026-09-16.md`;
an ADR's "log line N" means that file's line N (original line + 2, its header).

| ADR | Title | Dates | Status |
|---|---|---|---|
| 001 | Layering: DSTEMCore/DSTEMSession packages | 09-02, 09-03 | live |
| 002 | `AppState` composition root and size budget | 08-17, 09-03/07/16 | live (09-07 form superseded) |
| 003 | Gate D | 08-18, 09-04 | live |
| 004 | Gate B independent review | 08-18, 08-31, 09-02 | live |
| 005 | Inventory is the review | 09-02 | live |
| 006 | py4DSTEM pin and DEVIATION notes | 09-03, 09-14 | live |
| 007 | Versioning and release naming; a raised system requirement is a major | 09-02, 09-03, 09-11, 09-22 | live |
| 008 | macOS floor and arm64-only | 09-04, 09-11, 09-22 | live (floor raised 14→27 09-22; v3.0.0 stays for older systems) |
| 009 | UI contract | 09-03, 09-04, 09-07 | live (09-03 AppKit superseded) |
| 010 | System presentation and run action | 09-03, 09-04 | live (toolbar placement superseded 09-22, `docs/archive/v4/window-design.md` §6) |
| 011 | Status strip readouts | 09-04, 09-12 | live (09-04 narrowed; throughput and the Performance rows moved to the Run tab by 034, 09-21) |
| 012 | Refusals not defaults | 09-04, 09-05 | live |
| 013 | Residency `.automatic` dropped | 08-18 | live |
| 014 | Learned disk detector | 09-06/07/08 | live — Core ML vs Core AI revisit owed (owner, 09-23) |
| 015 | Even-count median | 09-09 | live |
| 016 | Accessibility crash deferred | 09-11 | live |
| 017 | Pane click selects | 09-11 | live |
| 018 | AI pipeline on main | 09-11 | live |
| 019 | Precipitates by classification | 09-11 | live |
| 020 | Accelerate new-LAPACK flag | 09-11 | live |
| 021 | Phase-mapping decisions | 09-11, 09-12 | live |
| 022 | Two verdicts: matrix and annulus | 09-14 | live (annulus withdrawn same day) |
| 023 | Ellipse refusal degeneracy | 09-14, 09-15 | live |
| 024 | Rotation and zone-axis nulls | 09-15 | live |
| 025 | HDF5 lock | 09-15 | live |
| 026 | Step 3 thresholds and orientation relationship | 09-15, 09-16 | live |
| 027 | `unit` free-space floor | 09-12 | live |
| 028 | Rules overruled 2026-09-16 | 09-07, 09-16 | live |
| 029 | Working methods | 08-31, 09-02/07/16 | live |
| 030 | Lessons promoted from the archive | 08-25–09-16 | live |
| 031 | v3 sequencing | 08-28, 09-03 | live |
| 032 | Docs consolidation and the ADR layout | 09-16, 09-17 | live |
| 033 | v3.1 leads with the origin validity mask (disclosure-only) | 09-17 | live |
| 034 | Bottom workspace holds live state; the inspector holds durable state (Xcode utility-pane form) | 09-21, amended 09-22 twice | live state split; Run tab folded into the infobar, two panes (036) |
| 035 | Frozen shell; width budget at the ideal columns; no toolbar title | 09-22 | live |
| 036 | The toolbar carries the room (file + live run display in the centre; run/stop, Save, Reveal, dataset menu over the room; only the toggle over the inspector); breadcrumb row removed; infobar 28 pt | 09-22 evening | live (supersedes §6.2 of the morning) |
| 037 | Inspector rooms are `GroupBox` cards; Prepare the reference | 09-22 evening; superseded 09-22 night | superseded: flat HIG sections in `InspectorRows` (cards dropped on Apple's guidance) |
| 038 | Precipitate objects finish in the phase-mapping room (section, snapshot table window, minimum size, CSV); known-variants evidence guard ships on at 1 | 09-23 night | live |
## Superseded or history (verbatim in the archive log)

27 of 97 entries are superseded/history (Table 3 of
`docs-inventory-live.md` marks them `n`; REPORT §1.2 said 21 — see `report-A3.md`):
09-02 tag before ship (v2.0.0 never built) · 09-03 columns are AppKit's
(deleted 09-04) · 09-03 one split-view contract (retired 09-04) · 09-03
steps 2c–4, unattended (implemented) · 09-03 step 2a, unattended
(implemented) · 09-03 presentation pass = complete rework (finished) · 09-03
v2.5.0 next, Track B retired (redefined 09-16) · 09-04 `UI2` prefix dropped
(renaming) · 09-04 status-bar reserved slot (superseded 09-12) · 09-07
consolidate before any feature (plan closed 09-11) · 09-07 C0 closed · 09-07
C1 docs made true · 09-07 C2 hygiene · 09-07 C5 AppState rule is a number
(hard form overruled 09-16) · 09-07 C6 Python "one truth rule" (superseded by
C7) · 09-08 C7 sessions 1–4 and its Gate B campaign (implementation log) ·
09-08 C8 engines stay on branch (reversed 09-11) · 09-08 C4(c) drive
delegated · 09-09 3.0.0 ships a UI looked at (shipped) · 09-11 (2nd round)
unattended port behaviour · 09-11 `docs/ai-ml/` brief ported (one-off) ·
09-11 class ID template-matched, recommended (superseded same day, see 019)
· 09-15 orientation relationship lands inert (superseded same day, see 026).
