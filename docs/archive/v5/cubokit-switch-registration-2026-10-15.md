# The switch to CuboKit 0.0.3 — registration (2026-10-15, tier 1)

Registered before any switch code, at `7f192da9` plus the pin seam. The kit's claims and the behaviour that changes are
`CuboKit/docs/consumers-0.0.1.md`, `-0.0.2.md` and `-0.0.3.md` (tag `0.0.3` = `8a337cc7`); this file states what
mac4DSTEM predicts on its own fixtures and cubes. The kit is the py4DSTEM definition in Double (its status: 0.0 px and
distance 0.0 from py4DSTEM's float64 on the owner's five cubes), so the app's numbers move TOWARD the reference; each
move is measured before it lands. One refuter on the frozen switch. Gate D does not apply (no diagnosed defect).

## Stages (each lands on its own after its gates)
- **C1, virtual imaging and the mean and max patterns.** A `CubeSource` adapter over `FourDArray` (consumer note 0.0.1
  §2); `VirtualDetector.tiledImage`, `tiledRun` and `tiledDPStatistics` call sites become `VirtualImaging.image` and
  `VirtualDiffraction.meanAndMax`; `makeMask` becomes `DetectorMask.make`; the rectangle is clamped to 0 before the call.
  Real-space masks and selected-area diffraction stay the app's.
- **C2, centre of mass, probe size, rotation.** `tiledCenterOfMass` → `CenterOfMass.measure` + `normalize`;
  `OriginCalibration.probeSize` → `ProbeSize.estimate`; `RotationCalibration.solve` → `RotationSolver.solve`;
  `DPC.applyRotation` → `RotationSolution.corrected`. The Fourier iDPC integration stays the app's.
- **C3, per-position origins and centred virtual imaging.** `tiledMeasuredOrigins` and the origin shader →
  `OriginMeasurement.measure`; the smooth fit → `OriginFit.fit`; centred images → `VirtualImaging.image(...centeredOn:)`.
  Registered here, built after C1 and C2.

## Predictions
- **P1 (masks).** Masks are pixel-identical for integer centres and radii; `tools/virtual-detector-test` (the digits cube,
  five geometries, exact sums) and `tools/virtual-detector-residency` pass unchanged.
- **P2 (virtual images).** Integer cubes bit-identical; on the owner's float cubes max |new − old| / max |old| ≤ 1e-6.
- **P3 (mean and max).** Max pattern exact; mean pattern max |new − old| / max |old| ≤ 2e-5 (the size of a Float32 tile sum;
  py4DSTEM's own float32 mean is 1.9e-5 from float64 on the Al–Mg–Si cube). Every test that reads the mean (probe size, ring
  hint, origin seeds) passes unchanged.
- **P4 (speed).** A virtual image of the 330 × 330 × 64 × 64 study cube is no more than 1.5× the old wall time on the path the
  app calls (`.metal` where the old call was Metal, unless `.cpu` meets the bar); measured, three runs each.
- **P5 (centre of mass).** On positions with no negative pixel and a positive sum: |Δ| ≤ 1e-3 px. Where pixels are negative
  (the owner's dark-subtracted cubes) the clamp's removal moves the CoM; no size is predicted: the distribution (median,
  95th percentile, max |Δ| px, and the count of zero-sum positions now NaN → 0) is measured on the five cubes and recorded
  before C2 lands.
- **P6 (probe size, rotation).** The app's `probeSize` equals `ProbeSize.estimate` on the five cubes' mean patterns, or the
  difference is recorded; the rotation and transpose chosen equal the kit's (Al–Mg–Si 83° T, Au 2° T, simulated Au 86°,
  particle 80° T, py4DSTEM's small cube −18°), or each difference is recorded with the app's old choice.
- **P7 (origins, C3).** Origin maps move to `get_origin` (Gaussian-filtered argmax, then CoM in r · rscale); the per-cube
  distribution of |Δ| px is measured before C3 lands. Tests that encode the old window's behaviour
  (`OriginWindowSensitivityTests`, `RegisterGateDFixTests`, `CalibrationReReferenceTests`) are amended only with the old and
  new values written in this file's results section.

## Checks
Unit, core, scientific and inventory gates on `main` after each stage; the counts reconciled by name; every new tier-1 test
broken once. The cubes are `$MACEM_DATA/4dstem/training_dataset/` (Al–Mg–Si 060, Au_ref ROI15, sim poly-Au, Particle 1)
and py4DSTEM's `small_datacube.dm4`. One fresh Sonnet refuter per landed stage set, never shown the lane's report. A failed
prediction closes the stage and opens a new registration (ADR 050). **Publication**: CuboKit is private and mac4DSTEM
public, so the switch commits stay local until the owner opens CuboKit or decides otherwise (asked of the coordinator).
