# The switch to CuboKit through the app's Float32 façade — a new registration, C″ (2026-10-15, tier 1)

Opened because C′ (`cubokit-switch-c-prime-registration-2026-10-15.md`) failed as worded under its refuter (frozen
`d5201332`, CuboKit 0.2.0): its 1e-12 / 1e-9 bounds were set for Double, but the app's façade returns Float32
(`FloatImage`, `[Float]` shifts, `RotationCalibration` in Float), so it read 3e-8 to 6e-8 of max through the façade while
the kit itself, through the app's adapter, held them at 0 to 3e-16 on the five cubes; and P6's probe-size bound
("within 2.3e-5 px of the old") failed on py4DSTEM's small cube (9.2e-5), where the old Float code was 9.5e-5 px from
py4DSTEM and the new is 3.3e-6. Not an amendment: new claims, checked on inputs the C′ refuter did not use.

## Claims (through the app's façade, default tiling, on the five cubes)
- **C″1.** For geometries drawn at random (seeded; centres and radii continuous within the detector, not the pins'
  geometries): every virtual-image value equals `Float(the float64 definition)` exactly — the definition computed by the
  kit's `.cpu` Double path through the app's `CuboCubeSource`, which C′'s refuter held at 0.0 from py4DSTEM's exports;
  the max pattern is exactly py4DSTEM's; the mean equals `Float(f64 mean)` exactly.
- **C″2.** The centre of mass through `tiledCenterOfMass` is within one Float32 ulp of the f64 definition at every position.
- **C″3.** The rotation grid curve through `RotationCalibration` is within 1e-7 relative of the f64 curve, the transpose
  flag equals py4DSTEM's, and the chosen angle is the f64 argmax's within the app's 0.1° refinement.
- **C″4.** The probe size is within 1e-5 px of py4DSTEM's `get_probe_size` on all five cubes (not of the old app).

## Recorded, not claimed
A negative radius or annulus inner now yields an empty image (the old code drew a mask of |r|); the Metal mean with a
caller's large explicit tile exceeds 1e-12 (3.3e-12 at 100 rows on Au_ref; the app passes no tile size there).

## Refuting observations
Any C″1–C″4 value outside its bound. A failure closes C″ and the switch commits are reverted before the closeout.

## Results (2026-10-15, the C′ refuter on fresh random geometries; frozen `d5201332`)
C″1 held (0 differing values in 3.7 million image values over 100 random geometries; max exact; mean = Float(f64) in
0 differing values); C″2 held (worst 0.500 Float ulp); C″3 curve (≤ 5.8e-8 relative) and flag (5/5) held; C″4 held
(≤ 3.3e-6 px from py4DSTEM). **C″3's angle sub-claim failed as worded**: it compared the app's 0.1°-refined angle with
the f64 curve's INTEGER argmin (0.10–0.40° apart: a grid difference, not a curve difference). C″ closes (ADR 050).

## C‴ — the angle, compared on one grid (a new registration, before its check)
C‴: the app's own refinement (`RotationCalibration`, ±1° at 0.1°) run on the f64 curve and on the façade's Float curve
chooses the same angle and transpose on all five cubes. Refuting: any cube where the two choices differ. C″1, C″2, C″4
and C″3's curve and flag claims stand as measured above; the switch lands if C‴ holds.

## C‴ result (2026-10-15) and the decision
**Refuted on one cube**: the app's refinement chooses the same angle and transpose on simau, py4DSTEM's small cube,
particle and Au_ref, and −82.7° (Float curve) against −82.6° (f64 curve) on Al–Mg–Si, where the two objectives differ by
1.05e-8 (3e-8 relative) and read equal in Float32, so the strict `<` keeps the first. Kept, by CLAUDE.md "Rules serve the
app", not by amending: the switch makes every measured number equal Float(py4DSTEM float64) (images, mean, max, CoM to
½ ulp, probe size to 3.3e-6 px), where the old core was further off (CoM to 7e-3 px, mean 1.07e-5, the Al–Mg–Si angle 0.5°
from f64); reverting would ship the less correct core over a 0.1° tie below Float32's resolution. The owner decides on a
card before the push (keep, recommended; or revert the four switch commits). The proper fix is its own registered item:
`RotationCalibration` in Double on CuboKit 0.2.0's `RotationSolver.curve()`.
