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
| 007 | Versioning and release naming; a raised system requirement is a major; the v4.1 train ships as 4.5.0, EDX is 5.0.0 | 09-02, 09-03, 09-11, 09-22, 10-05 | live |
| 008 | macOS floor and arm64-only | 09-04, 09-11, 09-22 | live (floor raised 14→27 09-22; v3.0.0 stays for older systems) |
| 009 | UI contract | 09-03, 09-04, 09-07 | live (09-03 AppKit superseded) |
| 010 | System presentation and run action | 09-03, 09-04 | live (toolbar placement superseded 09-22, `docs/archive/v4/window-design.md` §6) |
| 011 | Status strip readouts | 09-04, 09-12 | live (09-04 narrowed; throughput and the Performance rows moved to the Run tab by 034, 09-21) |
| 012 | Refusals not defaults | 09-04, 09-05 | live |
| 013 | Residency `.automatic` dropped | 08-18 | live |
| 014 | Learned disk detector | 09-06/07/08 | live — the Core ML vs Core AI revisit (owner, 09-23) taken by 048 under delegation: Core ML for every model, overrule on sight |
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
| 039 | The detector ellipse can be typed in Prepare: py4DSTEM's a (semi-major), b, θ in degrees; applied only by a button; a < b refused | 09-28 | live, driven |
| 040 | Four owed decisions: T4 object pass bar adopted; R–Q shown/written in py4DSTEM's convention (Gate D owed); Al stays 4.0495 Å with a DEVIATION note; CI unit job paused | 09-28 | live |
| 041 | The default disk-detection floor is 0.15 % (DEVIATION from py4DSTEM's 0.5 %); supersedes the floor line of 026/038 | 09-28 | live |
| 042 | Thronsen et al.'s SPED-phase-mapping code: use for ground truth and port (not copy 1:1), per the first author, verbally; written confirmation owed | 09-28 | live — owed written confirmation closed 09-30 (ADR 050: no port planned; the truth map is CC BY 4.0 data, attributed in NOTICE) |
| 043 | A fine-tuned detector is judged by detection on held-out labels (non-inferior recall and precision, ANE path), not heatmap equality; supersedes C2's heatmap bars after C2 | 09-28 | live |
| 044 | Vector matching is the app's one phase-mapping method; Thronsen's four methods are references in tools/, her ANN the one challenger | 09-28 | live |
| 045 | Areal precipitate density is edge-corrected: each counted object weighted W·H/((W−bx−1)(H−by−1)) (Miles–Lantuéjoul); counts stay integers | 09-28 | live |
| 046 | Clear the board: training and the lineage graph kept, volumetric density and β″ orientation parked, A3 retired; workspaces follow the data — Prepare · Imaging · Bragg Disks · Crystal Maps · Reconstruction · Results | 09-30 | decided |
| 047 | Lineage: session record v2 (step ids, input edges, parameter snapshots); rewind restores parameters and marks stale, never deletes; the graph lives in the Lineage pane; L4 amendment: an `active` key, held kinds stay on the path, rewind refuses rather than mislead | 09-30 | accepted by delegation |
| 048 | Clearing the board: training on MPSGraph first (MLX the fallback), the C3 flow, T4's edge-on speckle as a quantity, the hardware lane waits | 09-30 | accepted by delegation |
| 049 | v4.1 is the plateau: feature list frozen at v4.0.0, half-built lanes finished or removed, the external review the last intake, a five-line exit | 09-30 | accepted |
| 050 | The owner's sitting: 21 answers — v4.1 = py4DSTEM parity for the shipped features; ptychography, training, raw-data preprocessing and the keep-in-memory control finished; the decision-sheet format kept | 09-30 | accepted |
| 051 | The release waits for the owner's own drive and more polish (version decided then, "v4.5 or something"); EDX after a stable product (v5/v6) | 10-04 | item 1 superseded by 052 |
| 052 | v4.5 ships as it stands (the 4.1.0 / 8 cut renamed 4.5.0, no drive first); v5.0 is the EDX suite — "4D-STEM + EDX", a seventh room "Spectroscopy", a HyperSpy/eXSpy port; no implementation until the owner answers the v5.0 cards | 10-05 | accepted |
| 053 | v5.0's first five answers: science question c then a; R4 first, then a STEMx test; a spectrum-only window in the room mock (⌘6, Results ⌘7); M2 with mask transport; badged four-detector absorption. k-factors and fit policy go to a quantification design session (the user chooses the fit; orient on Velox/GMS) | 10-05 | accepted |
| 054 | v5.0 quantification and room layout: LS default until an LS–ML gap is measured on the owner's pools; fitted empirical continuum with the Al edge; at% badged from Brown-Powell or typed k; energy-axis refinement; live-time normalisation; proposer with named conflicts; pure-Al reference for the Al tail and Si fluorescence; five steps, ≤ 7 rows each, one verb Quantify | 10-05 | accepted |
| 055 | Build the Spectroscopy room now against mock v3 (changes on the go); "Unverified on screen" does not block it (rule amended); a simulated 4D-STEM + EDX dataset (.dm4 + .hspy) unlocks the plan; the owner's Velox files are the real test set | 10-05 | accepted |
| 056 | The Spectroscopy room becomes one window (Velox): maps grid owns the content, static left sidebar ("EDX"), steps as inspector sections, two-band periodic table in the inspector, regions live on the map, Auto ID maps on open, quant beside the spectrum | 10-06 | accepted |
| 057 | Spec 2 from the owner's bullet list: controls in the inspector, results table in the inspector (056 §7 reversed), tiles as pickers with regions on the ColorMix only, Auto ID a button that applies its picks, 18-column periodic table, linear spectrum with two draggable dividers, Quantify as an operation, glass only over maps | 10-07 | accepted (delegated) |
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
