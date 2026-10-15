# The switch to CuboKit (C1, C2) against py4DSTEM — a new registration, C′ (2026-10-15, tier 1)

Opened because C1 and C2 of `cubokit-switch-registration-2026-10-15.md` failed as worded in lane C (nothing landed):
P2 (float-cube virtual images, old against new, bound 1e-6: measured up to 2.35e-6, HAADF on Al–Mg–Si) and P5 (centre of
mass on positions without a negative pixel, bound 1e-3 px: 7.0e-3 px on py4DSTEM's 512 × 512 small cube). Both bounds
compared the app's new numbers with its OLD Float32 numbers; the claim that matters is agreement with the reference. Not an
amendment: a new claim, against an oracle the lane did not use, checked by a fresh refuter before anything lands. Built on
CuboKit **0.1.0** (round 2: `consumers-0.1.0.md`, nothing breaks from 0.0.3; the app's `FriedelOrigin`, `BeamstopMask` and
`ProbeKernel` copies that clash with the kit's names go in the same change).

## The oracle
CuboKit's real-data exports of py4DSTEM `f050d207` on the owner's five cubes (`~/Library/Caches/CuboKit/real-data`,
regenerable by CuboKit's `tools/slice-*/pins.py`; outside every repo): per cube, the float64 definition (`*_f64.npy`) and
py4DSTEM's own calls (`*_py4dstem_native.npy`) for the BF, ADF, centred-circle and off-axis DF images, the mean and the max
pattern, and slice 2's centre-of-mass and rotation chain. The geometries are the ones in each cube's `pins.json`.

## Claims (through the app's façade: `VirtualDetector.tiledImage`, `tiledDPStatistics`, `tiledCenterOfMass`, the adapter)
- **C′1, images and patterns.** On the five cubes, for every exported geometry: virtual images within 1e-12 of max |image|
  of the float64 export; the mean within 1e-12 of max |mean|; the max pattern exactly equal. (The old app differed by up to
  2.35e-6 and 1.07e-5; py4DSTEM's own float32 calls differ from float64 by up to 1.9e-5 on the mean.)
- **C′2, centre of mass.** The app's CoM field, before its reference subtraction, within 1e-9 px of the float64 export
  (`.cpu` path) on every position of the five cubes, negative pixels included (no clamp).
- **C′3, rotation.** The app's grid curve (before its 0.1° refinement) equals the exported `s2-chain_curve` /
  `_curve_transposed` at the shared integer angles to 1e-9 relative, and the app's chosen transpose flag equals py4DSTEM's
  on all five cubes.
- **C′4, nothing else moves.** Integer cubes: images bit-identical to the old app (held in lane C); the masks pixel-identical
  (P1, held); probe size within 2.3e-5 px of the old (P6, held); every unit test other than lane C's new `CuboSwitchTests`
  unchanged; the residency harnesses' equality claims bit for bit, their "zero staging copies" and "one tick" claims
  retired with the reason (the kit's `CubeSource` returns `[Float]`, so a resident buffer is copied once per tile).

## Recorded, not claimed (product costs for the owner, with the kit asks)
A resident-cube virtual image 0.006–0.02 s → 0.08 s (no zero-copy source in the kit); centre of mass 0.21 → 0.77 s and the
rotation solve 0.18 → 0.76 s (the kit's reducers and `RotationSolver` are single-threaded); in an app built Debug the kit runs
at -Onone (CoM 48–58 s, rotation 186–217 s); the `Develop` Run configuration and the unit gate build it -O.

## Refuting observations
Any C′1–C′3 value outside its bound on any cube or geometry; any other test or golden that moves. A failure closes C′.
Refuter: one fresh Sonnet, reading the exports itself (under `../tools/memcap.sh`, one cube at a time), never shown the
lane's report.
