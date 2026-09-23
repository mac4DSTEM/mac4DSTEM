# 038 — Precipitate objects finish in the phase-mapping room; the known-variants evidence guard ships on

Dates: 2026-09-23 (night)

Status: live. The owner's words that night: "ship the guard at 0.15 %, k ≥ 1", answered "guard only";
then "finish the precipitate analysis pipeline now … fast and native and simple and pure macOS",
with the drive-before-surface rule waived for the night. The choices marked **(assistant)** were
made inline under that brief, for the owner to overrule on sight.

## Decision

1. **The guard.** `PhaseVectorSettings.knownVariantsMinimumSpecificReflections = 1`, on by
   default for `.knownVariants`. The detection-floor default stays at 0.5 %. The Core guard
   reproduces the probe's measured inline guard byte for byte (Gate D:
   `archive/v4/known-variants-guard-gateD-2026-09-23.md`). It is shown in the known-variants
   settings as "Phase-specific reflections, at least"; 0 turns it off. Its value is recorded in
   the sidecar provenance.
2. **Objects stay in the phase-mapping room**, as a "Precipitates" section under Result
   (`UI/PrecipitateObjectsSection.swift`). No new room, so none of the five frozen-shell files
   change (035). **(assistant)**
3. **The object table is its own window** (`UI/PrecipitateObjectsWindow.swift`,
   `WindowGroup(for: PrecipitateObjectReport.self)`): a native sortable `Table`, the per-phase
   summary above it, a phase filter, a "Counted Only" toggle and Export in its toolbar. It holds
   a **snapshot value**, not a live link to the dataset window's `AppState`, which is
   per-window (`DatasetWindow`). It can stay open beside the map; a new run means opening it
   again. **(assistant)**: a sheet would block the map; a table inside the inspector is too
   narrow.
4. **Minimum object size is a reader setting, default 1 px (off)**, kept across datasets. Small
   objects stay listed and drawn (dimmed) but are not counted. Never a shipped cut: the
   published truth's cuts (4 / 782 / 10 px) belong to its dataset
   (`docs/cloud/2026-09-23/T2-direction-check.md`). **(assistant)**
5. **The calibration is read when the table is built**, not when the objects are segmented, so
   a scan scale changed after a run can never leave a stale density. This closes the gap the
   2026-09-23 map found in `setManualRPixelSize`.
6. **"Show Objects"** publishes a `precipitate_objects` product. Counted objects are drawn in
   their phase colour; edge and small objects are dimmed, so the picture shows exactly what the
   numbers count. **CSV export** uses SwiftUI `.fileExporter` and carries the provenance,
   including `validation: none`, in `#` comment lines. **(assistant)**
7. **Segmentation runs off the main actor**, with a generation token: a newer run or a dataset
   change always wins over a stale result.
8. **What driving the app changed (2026-09-23 night, `datasetA_stride3.h5`, 0.15 % floor, known
   variants).** Thronsen's Al, θ′ and T1 CIFs all imported as "VESTA_phase_1", so legend, rows
   and table could not tell them apart. `CIFImport.displayName` now uses the file name when the
   `data_` block is VESTA's placeholder. Every phase row, table row and summary line carries the
   map's colour swatch. Numbers use the reader's locale, never an exponent (the CSV keeps POSIX).
   The table subtitle shows a local date. The window opens at 1180 × 680. **(assistant)**

## Not decided here

- The `lengthPx` definition: centre to centre + 1, not the end-to-end extent (PR #2's
  cross-check). An owner decision.
- An object-level pass bar: `docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md`.
- Selecting a table row does not yet highlight the object in the pane.
