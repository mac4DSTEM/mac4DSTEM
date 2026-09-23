# Architecture — superseded narrative (moved 2026-09-23)

Verbatim passages moved out of `docs/architecture.md` when it was brought
current for HEAD after the v4.0.0 release (2026-09-23). Each is superseded
by the cited evidence in `docs/architecture.md` itself; nothing here is
live.

## "The window is three columns" (UI contract rule 6) — superseded by the shipped v4.0.0 shell

Written mid-way through the window rebuild (owner decision 2026-09-22,
phase 1 not yet accepted on screen). Superseded by the shipped anatomy
(ADR 035/036/037; `docs/archive/v4/window-design.md`;
`docs/architecture.md` § "The UI contract" as rewritten 2026-09-23 —
no canvas header, the toolbar carries the room, `InspectorRows`' flat HIG
sections, the `LayoutPolicy.datasetWindowMinimumSize` 915-pt floor).
Original text:

> 6. **The window is three columns with one job each** (`window-design.md`,
>    owner decision 2026-09-22; phase 1 not yet accepted on screen). Left is
>    navigation, right is the Settings · Info inspector; both run from the
>    toolbar to the window bottom and collapse completely. Centre owns the
>    science, an infobar and the process area. Its header keeps workspace ›
>    dataset at the left and the primary action, Save to Session and Reveal
>    grouped at the right; the space between them follows centre width as
>    either side panel toggles. The standard toolbar holds only window-level
>    controls. Readiness has one home, the Settings tab's first section.

## "Ownership today and where it is going" — superseded by the completed seams plan

Written while the `AppState` seams plan was mid-flight (some seams landed,
some not). Superseded by the plan's completion (all seven seams, 2026-09-18;
`docs/archive/v4/appstate-seams-plan.md`) and by later feature work;
`docs/architecture.md`'s current "Ownership today and where it is going"
lists the actual owner types at HEAD (`mac4DSTEM/Session/*.swift`,
`mac4DSTEM/App/AppState+*.swift`, grepped 2026-09-23). Original text:

> Today `AppState` (`App/AppState.swift`) owns loading, session state, calibration,
> every analysis's parameters and dispatch, product publication, replay and
> recovery; `ContentView` reconstructs workflow rules from it. Extracted seams
> already exist (`DatasetResidency`, `SessionGates`, `WorkspaceNavigation`,
> `StrainProduct`, `ReplayRun`, `QCalibrationRun`, `SessionCalibrationFramePolicy`,
> `FitOverlayPresentation` — C5's first extraction, 2026-09-07: the diffraction
> pane's fit overlays as a value over a snapshot — `PtychographySettings`,
> 2026-09-17: the single-slice ptychography input controls, the result stays
> on `AppState` like `StrainProduct`'s split between controls and map).
> The target (`archive/v2/v2.5-plan.md` §4): `ScientificProduct` as an
> immutable value owning pixels, axes, units, frame, calibration snapshot,
> validity and provenance, with `ProductPresentation` separate; narrow
> per-analysis controllers; a typed task registry that is also the recipe
> vocabulary, so live runs and replay share one execution path; `AppState`
> reduced to composition and window coordination.
> Rules while migrating: no new stored state in `AppState`; a feature names its
> owner first; adapters carry an expiry condition; numerical code is split only
> at scientifically meaningful boundaries. `AppState.swift` +
> `Support/ResultExport.swift` are size-tracked by `inventory` against the
> previous commit (`HEAD^` on a clean tree, `HEAD` on a dirty one — C5,
> 2026-09-07): the hard "never net positive lines" form of that rule is
> **overruled (owner, 2026-09-16)** — `inventory` now reports the delta instead
> of failing on it, since growth is allowed where one of these two files is the
> honest home for the state; the caution is real, the block is not. A commit
> that grows them says in its message why no other home would do. Extractions
> still follow the plan's §4 order above, one at a time, each with a green
> boundary and a reopen test.
