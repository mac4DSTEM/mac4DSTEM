# The electron wavelength from DiffractoKit — registration (2026-10-15, tier 1)

Registered before any code. Kit item 12 of `DiffractoKit/docs/consumers-0.0.3.md` (tag `0.0.3` = `0156172b`): the app's
two wavelength formulas are replaced by `ElectronWavelength.angstroms(volts:)` (CODATA 2018). Split from the switch's
registration (`diffractokit-switch-registration-2026-10-15.md`, "Not in this switch") because it is the one number it moves.

## The change
`DPC.electronWavelengthAngstrom(voltageKV:)` (12.2639 / √(V (1 + 0.97845e-6 V))) → `ElectronWavelength.angstroms(volts:
kV × 1000)`, keeping its `nil` for a non-positive or non-finite voltage; `ParallaxPreprocessor.electronWavelengthAngstrom
(energyEV:)` (rounded constants) → `ElectronWavelength.angstroms(volts: eV)`. Nothing else in the app computes λ.

## Predictions
- **W1.** At 200 kV the new λ is 0.025079340450548003 Å; the DPC form's 0.02507865865 Å is 2.72e-5 relative below it
  (80 kV −2.84e-5, 120 kV −2.80e-5, 300 kV −2.64e-5) and the Parallax form's 0.02507933736 Å is 1.23e-7 below.
  A test pins these (old and new, both forms, four voltages) from the kit's documented values, not from the Swift.
- **W2.** Every quantity linear in λ moves by exactly that relative amount and nothing else: the calibration readout's
  mrad per pixel (1000 λ dq), the exported angle units, the Parallax probe angles, aberration frequencies and depth-section
  χ. A test that pins one of them at a tolerance tighter than 3e-5 relative is re-recorded, with its old and new value in
  the commit message and the results below; none looser moves.
- **W3.** The ACOM excitation error s_g = g·n + λ|g|²/2 changes only in its curvature term (2.7e-5 relative of λ|g|²/2,
  about 1e-8 Å⁻¹ at |g| = 1 Å⁻¹): the orientation maps of `ResultOrientationTests` and the `acom-*` harnesses keep every
  best-match index; correlation scores move by at most 1e-6 relative.
- **W4.** The Parallax harnesses (`tools/parallax-*`) stay inside their registered tolerances (the 1.2e-7 shift is below
  every one of them).

## Refuting observations
Any best-match index change in W3; a W2 quantity that moves by other than the λ ratio; a harness outside its tolerance.
One refuter shared with the switch's refuter (the same frozen tree). Not claimed: any microscope's true voltage.

## Results (2026-10-15, lane W; nothing landed)
W1 held (the kit's λ at 80/120/200/300 kV to 1e-15 Å; old DPC offsets −2.8377e-5 / −2.7952e-5 / −2.7186e-5 / −2.6358e-5;
Parallax −1.23e-7 at 200 kV; 3 mutations red). W2 held (only the λ ratio moved; the aberration-free probe goldens moved
with the Parallax λ). W3 held, but the `acom-*` harnesses pass a literal λ: a direct run with the old and the new value
gave identical outputs (210 / 210). **W4 failed**: `parallax-preprocessing-test` pins the Parallax λ to py4DSTEM's own
rounded-constant value at 1e-12 and the kit's sits 3.1e-9 Å (1.23e-7) away. The item closes (ADR 050); patches in the lane
only. The Parallax code is a port whose test is parity with py4DSTEM, so its λ stays py4DSTEM's: W′ below.

## W′ — the DPC form only (a new registration, before its code)
`DPC.electronWavelengthAngstrom(voltageKV:)` → `ElectronWavelength.angstroms(volts: kV × 1000)` with its nil guard;
`ParallaxPreprocessor.electronWavelengthAngstrom(energyEV:)` unchanged (py4DSTEM's constants, a parity port).
- **W′1.** DPC returns the kit's λ at 80/120/200/300 kV to 1e-15 Å; the Parallax function returns py4DSTEM's rounded-form
  values (0.04175715620292005, 0.03349214889517896, 0.025079337357037376, 0.019687486388201916 Å) to 1e-15 Å.
- **W′2.** The mrad-per-pixel readout moves by the DPC ratio only (0.2507865865 → 0.2507934045 at 200 kV, dq 0.01).
  `parallax-preprocessing-test`, the ptychography probe goldens and `singleslice-ptychography-test` are unchanged.
- **W′3.** Unit, core, scientific and inventory green with no other golden re-recorded.
Refuting: any W′ line; any other test or harness that moves.
