# Gate D — `occupiedPositions` and the radius-only aperture drag, 2026-09-30

Two open items, each pre-registered before its experiment (scratchpad `p2/*-prereg.md`, not retained). Tests:
`RegisterGateDFixTests.swift` (`StrainCentralOnlyPositionsTests`), `ApertureDragOriginTests.swift`. Independent refuter: owed.

## 1. `occupiedPositions` counted central-beam-only positions
- **Diagnosis.** `StrainMapping.estimateLatticeBasis`: the 8 % cluster-support bar was `ceil(0.08 × positions with ANY peak)`; a
  central-only position adds no observation, so a lattice in L of N positions needed L ≥ 0.08 N. Fix: the bar counts positions
  that hold a peak beyond `minRadius` (`nearestRadii.count`, the D023 population). py4DSTEM has no per-position count (maxima of
  the whole-scan vector histogram), so the 8 % bar is mac4DSTEM's own — inline DEVIATION note.
- **Measured** (400 positions, 24-vector lattice, lattice at L evenly spread positions, rest central-only): old → basis at
  X = 0–92 % central-only, NIL at 93 / 95 / 99 % (L = 28 / 20 / 4); new → basis at all, and the 93 / 95 / 99 % results equal the
  old result with EMPTY positions in their place (control, byte-identical) — a central-only position now weighs what an empty
  one does. Every row where the old code already found a basis is identical, for 0 px and ±0.15 px jitter.
- **Shipped numbers.** Demo cube (`AlMgSi_demo.h5`, detection stride 3, 34 × 34 positions, 16 central-only, probe 3.0 px):
  bar 93 → 92, candidates 20 → 20, chosen basis, `StrainMapping.compute` exx / eyy / exy / θ / residual / mask arrays
  **byte-identical** (`cmp`). `strain-test`, `strain-frame-test`, `fit-overlay-test` green; `StrainFrameTests` green.
- **Seen, not fixed:** with ±0.15 px jitter the basis search often returns a non-primitive pair (20 / 41, 18 / 29 px) — old and
  new alike (the empty-position controls show it too); a support tie-break question, separate.
- **Limit:** with L tiny the bar is 1 and a handful of positions can define the basis; the 50 % observation-support and
  condition gates still apply, as they did for any small fully-occupied scan.

## 2. A radius-only aperture drag destroyed the fitted origin
- **Diagnosis.** `ApertureOverlay.emit` rounded centre AND radii on every handle drag; after an origin fit or restore the live
  centre is fractional (owner data (69.3133, 54.5009)), so a drag of only a radius handle published (69, 55).
  `AppState.updateAperture` compares centres with `!=` → the centre-change branch: origin maps set aside, recorded mean cleared,
  provenance `.manual`. Radii rounding is intended; centre rounding of an UNCHANGED centre is the defect.
- **Fix.** Pure `Aperture.snappedEdit(from:patternWidth:patternHeight:)` (`Core/Analysis/VirtualDetector.swift`): the centre is
  snapped (and clamped after rounding, ui-08) only when the gesture changed that coordinate; radii always snap. `emit` calls it.
- **Moves:** nothing for an integer centre (published aperture identical). At a fractional centre a radius drag now keeps the
  fitted origin and the centre, so the virtual image is computed at the fitted centre instead of one shifted ≤ ½ px per axis.
- **Unverified on screen.** Drive: fit or restore the origin (Prepare shows a fractional Aperture center), Imaging ▸ Virtual
  Detector, drag only the outer-radius handle → origin still fitted, no "Restore Fitted Origin"; then drag the white centre handle
  → origin goes Manual and Restore appears.

## Gates
Unit subset (`StrainCentralOnlyPositionsTests`, `StrainEmptyPositionMedianTests`, `StrainFrameTests`, `ApertureSnappedEditTests`,
`ApertureRadiusDragKeepsFittedOriginTests`): all green, `xcodebuild test` exit 0. Mutation run (old occupied count + unconditional
centre rounding), exit 65: red are `testALatticeInFivePercent…`, `testARadiusOnlyEditKeepsTheFractionalCentreBitForBit`,
`testAnInnerRadiusEditKeepsTheCentreToo`, `testARadiusOnlyDragLeavesTheFittedOriginAlone`; green controls
(`testAMajorityLattice…`, `testACentreDrag…`, `testAnIntegerCentre…`, `StrainEmpty…`) as designed.
