# S15: R–Q rotation in datacubes exported before 2026-09-28 — 2026-09-30

Residual of ADR 040 decision 2 (`rq-sign-gateD-2026-09-28.md`). Outcome: **label only; no number moves.**

## Diagnosis
- The datacube writer (`BraggVectorEMDWriter.writeCalibratedDataCubeFile`) has stamped the file root
  `authoring_program = "mac4DSTEM"` since b2fe7db (2026-07-13). `QR_rotation_convention` exists only from 9f89c43 (2026-09-28).
  py4DSTEM's writer stamps "emdfile" (References: `Particle_1…bin8.h5`, `Al_Mg_Si_060….h5`).
- So (author "mac4DSTEM") ∧ (no marker) identifies **the writer**, exactly: a datacube written by this app before 2026-09-28.
  The Gate D note "cannot be told apart from a py4DSTEM file" was wrong on that point.
- Reopened today, `H5Reader.pixelCalibration()` reads `QR_rotation` and `AppState+Open` negates it unconditionally
  (py4DSTEM's file sign → app sign), with no warning.

## The convert option, and why it was refuted
First patch: treat every such file as app-signed and negate on read (so it reopens with the angle it was exported from).
Refuted by the supervisor, on the history: **before 9f89c43 the app imported a py4DSTEM `QR_rotation` raw and exported it raw.**
An unmarked export therefore holds the app's sign if the rotation was measured in mac4DSTEM, and py4DSTEM's if it was imported
from a py4DSTEM-calibrated cube. The stamp cannot say which; converting would silently flip the second kind. Reading as today is
right for the second kind and wrong for the first; either way a silent choice is worse than a label.
(The convert patch is kept at `$SP/s15/v1/patch.diff` in the session scratchpad only.)

## What landed
- `RQRotationConvention.isUnmarkedExportOfThisApp(authoringProgram:convention:)` and `legacyNote`.
- `PixelCalibration.qrRotationNote`, set by `H5Reader.pixelCalibration()` for exactly that case; `qrRotationRad` passes through unchanged.
- **Owed wiring (not landed; `AppState+Open.swift` was owned by another session):** after the `rotationRad` assignment in
  `AppState+Open.swift` (~l.466) add `if let note = pc.qrRotationNote { statusText = note }`. Until then the note exists in Core and
  is tested, but nothing shows it on screen (unverified on screen).
- `tools/training-dataset-campaign/main.swift` (diagnostic): import now converts py4DSTEM → app (was raw), export writes py4DSTEM's
  sign plus the marker (was the app's, unmarked), and the report's `rotation_degrees` is now py4DSTEM's convention with
  `rotation_degrees_app_internal` beside it (a relabel; the solver's number is unchanged). Typechecks (`v2-tc.log`, exit 0).
- Tests (`RQLegacyExportTests`, 3; `RQLegacyExportLabelTests`, 2; 23° through the real writer and reader): an unmarked export keeps
  today's number (app −23° from a file value +23°) and carries the note; a marked export and an export with no rotation carry none;
  a py4DSTEM-authored or unstamped file is not labelled (pure test; no writer produces "emdfile").
  Red with the API stubbed (`v2-red-stub.log`, 2 red); green 29/0 with RQRotationConvention, StrainFrame and DatacubeDiscovery
  (`v2-green.log`); four one-line mutations red (marker check dropped, author check dropped, reader converts, note dropped).

## `Si-SiGe_calibrated.h5`
The one References datacube of this kind: author mac4DSTEM, `QR_rotation` = −1.5464 rad (−88.6°), no marker. Its derivation
names `Si-SiGe.dm4` as the source and DM4 has no rotation, so the value was **measured in the app → app sign**; for this file a
conversion WOULD be right (it would open at app −88.6°, row +88.6°, where today it opens at app +88.6°, row −88.6°). It is not
converted because the rule cannot know that in general. The owner may re-export it from the app (a marked file then reads
correctly). Nothing under References/ moves; no test or harness reads this file's rotation.

## Not changed
The parallax fit's rotation needs no flip: `ParallaxAberrationFitter` is source-locked to py4DSTEM at asymmetric angles
(`tools/parallax-aberration-test`) and never reads the calibration's rotation. Read from the code, not driven.

## Landed (orchestrator, 2026-09-30 night, after the supervisors)
- The note is shown durably: `CalibrationProvenance.rotationImportNote`, appended to the R–Q row's detail while the rotation is
  still `.importedFile` (measuring, typing or a sidecar retires it), and once on the status line (logged). Shortened after drive
  2B saw the long text take six lines: "Sign unrecorded (exported by mac4DSTEM before 2026-09-28): check it before DPC, strain
  or parallax." Red/green: `RQLegacyExportTests.testAnUnmarkedExportShowsItsNoteOnTheRotationRow` 4 / 0, red with either wire cut.
- Campaign report: `rotation_degrees` KEEPS ITS KEY but now carries py4DSTEM's sign (the app's is `rotation_degrees_app_internal`),
  so an old and a new campaign JSON differ in sign under one key; nothing in the repo reads it (Fable supervisor 3).

