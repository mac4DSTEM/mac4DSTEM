# The switch to DiffractoKit 0.0.3 — registration (2026-10-15, tier 1)

Registered before any switch code, at `7f192da9` plus the pin seam. The kit's own claims and its list of numbers that move
are `DiffractoKit/docs/consumers-0.0.3.md` (tag `0.0.3` = `0156172b`); this file states what mac4DSTEM predicts for its
own fixtures and how each prediction is checked. Gate D does not apply: no defect is diagnosed, and every moved outcome is
a registered amendment of the kit, named below. One refuter on the frozen switch.

## Scope
Two lanes, disjoint files.
- **E (ellipse)**: `Core/Analysis/EllipseCalibration.swift` goes; `EllipseCalibration`, `EllipseCalibrationFit`,
  `EllipseProfileParameters`, `EllipseCalibrationModel` come from `DiffractoGeometry`; the fit takes
  `DiffractoGeometry.DiffractionPattern(width: qx, height: qy, pixels:)`; `Calibration`'s ellipse transform and offsets
  become `EllipseTransform` calls.
- **X (crystal)**: `Crystal.swift`, `ScatteringFactors.swift` and the parser half of `CIFImport.swift` go; `CrystalModel`
  holds a `CrystalStructure`; presets are `CrystalStructure` builders keeping the hand site lists (kit item 9);
  `ACOMCrystalSymmetry` is mapped from `LaueClass` (m-3m → cubic, 6/mmm → hexagonal, 2/m with b unique → monoclinic,
  else identity); `MaterialsProjectImport` uses the same mapping and the kit's element lookups; `OrientationResult`'s
  `detectorBasis`, `PhaseReferenceLibrary.lowIndexZoneAxes` and `cartesianZoneAxis` become `ZoneAxis` calls.
- **Not in this switch** (each its own later item): the wavelength (kit item 12: `DPC.electronWavelengthAngstrom` is
  2.6–2.8e-5 below CODATA-2018; a number-moving change that gets its own registration); `ZoneAxis.project` for the
  template excitation error (it carries the wavelength); vector matching, the reference library, the orientation plan's
  weighting and the ACOM reduction (not in 0.0.3); the five ring-fit gaps of the kit's registration-slice-3 §7 (fixed in
  the kit, taken through a later pin).

## Predictions
- **P1 (bit identical).** `CrystalMathTests`, `CIFMultiBlockTests`, `EllipseNoisyRingTests`, `EllipseStopRuleTests`,
  `CalibrationEllipseRow29Tests`, `ResultOrientationTests`, every ellipse and ring-fit test, the ADR 069 plants
  (`tools/ellipse-calibration-test`) and the β″ B2 tests pass unchanged, with their tolerances unchanged. Basis: kit item 13.
- **P2 (reflection lists).** For every preset (Al, Au, Si, Mg, ideal hcp, WS2, β″, the cubic editor's structures) and the
  repo's CIF fixtures, the kept reflections after the 1e-4 cut have bit-equal |g|, Re F, Im F and |F|² and the same set as
  `7f192da9`; order within an equal-|g| ring may differ (kit item 8). Checked by a consumer test that compares the switched
  list against values recorded from `7f192da9` before the switch.
- **P3 (model identity).** `revisionID`, `contentFingerprint` and every `provenance` string of the presets and the repo's
  CIF fixtures are byte-equal to `7f192da9`'s (they key sidecars and libraries). Recorded before, compared after.
- **P4 (accepted inputs; kit items 1–4).** Every CIF the app imported at `7f192da9` imports with the same
  `ACOMCrystalSymmetry`. Tests that asserted a refusal with no kit counterpart change outcome, and only these:
  `testTrigonalCellInHexagonalSettingIsRejectedNotOverSymmetrized` and
  `testAccidentallyCubicMetricWithoutA111ThreeFoldIsRejected` (CIFImportTests),
  `testTwoSitesCannotShareOneTargetInTheSymmetryMap` (CIFSpaceGroupOrderTests),
  `testRow6PyriteTypeCubicMetricButNoFourFoldIsRefused` (MaterialsProjectImportRow6Tests),
  `testRhombohedralRCentredPrimitiveStandardisesToHexagonalThreeSites` (MaterialsProjectImportTests): each now imports,
  as `.identity` ("Unreduced"), never as cubic or hexagonal. The over-symmetrisation each guarded against is still
  refused, which is what each test asserts after the switch. New refusals: a singular rotation and a non-finite or
  over-1000 coefficient (kit item 4).
- **P5 (ACOM).** Template libraries built from the presets give the same orientation maps on `ResultOrientationTests` and
  the `acom-*` harnesses: any change is at most a tie broken differently inside one ring (kit item 8), reported per case.

## Checks
Unit, core, scientific and inventory gates on `main` after each lane lands; a test count reconciled by name (removed tests
named with the kit test that holds the same plant); every new tier-1 test broken once. One fresh Sonnet refuter on the
frozen switch, given this file, the kit's consumer note and the diff, never the lane's report. A failed prediction closes
this item and opens a new registration (ADR 050).
