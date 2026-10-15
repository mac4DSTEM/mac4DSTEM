# CuboKit switch, lane C (C1 and C2): results (2026-10-15, tier 1)

Registration: `docs/archive/v5/cubokit-switch-registration-2026-10-15.md` (closed: P2 and P5 failed as worded); the claim that replaces it is `cubokit-switch-c-prime-registration-2026-10-15.md`, whose oracle comparison is the refuter's. Measured on CuboKit 0.0.3; the same code on 0.1.0 is re-checked in the second commit of the landing. Measured with one harness (`measure/`, not committed) that runs the
app's own call sites (`VirtualDetector.tiledImage`, `tiledRun`, `tiledDPStatistics`, `tiledCenterOfMass`,
`OriginCalibration.probeSize`, `RotationCalibration.solve`, `DPC.applyRotation`) on the five cubes once on the unswitched
tree (`c86733b2`, the `before` set) and once on the switched tree, the same source both times. The `before` set was recorded
twice and is bit-identical across the two runs (every `app_*` and `kit_*` file). Cubes: Al-Mg-Si 060 (330 x 330 x 64 x 64
float32), Au_ref ROI15 (205 x 310 x 64 x 64 float32), `sim_Au` `4DSTEM_polyAu` (100 x 84 x 125 x 125 uint16; the file also
holds a nano-platelet cube the app's `discoverPrimaryDataset` picks first, which is not the kit's), Particle 1 (90 x 45 x 128 x
128 uint32), py4DSTEM `small_datacube.dm4` (20 x 20 x 512 x 512 uint16).

**Verdicts: P1 pass. P2 FAIL. P3 pass. P4 pass. P5 FAIL (one cube). P6 pass by record.** A failed prediction closes the stage
(ADR 050): C1 and C2 are prepared and gated but not landed.

## C1

- **P1 (masks): pass.** `VirtualDetector.makeMask` against `DetectorMask.make` for 14 geometries on each cube (the presets at
  the measured probe, fractional centre and radius, rectangles, a point, integer centre and radius): 0 differing pixels on
  all five cubes. `tools/virtual-detector-test` passes unchanged (all PASS lines). `tools/virtual-detector-residency` passes
  with two assertions amended, see Findings.
- **P2 (virtual images): FAIL as registered.** Integer cubes (simau, particle, small) are bit-identical for all 12 geometries.
  The two float cubes exceed 1e-6 of max |old|; max |new - old| / max |old| (new = the kit's Double sum, old = the Float32 Metal
  sum; the kit's CPU value is the float64 definition, so the difference is the old kernel's, by the kit's pins, not separately measured here):

  | geometry | Al-Mg-Si | Au_ref |
  |---|---|---|
  | BF circle | 2.5e-7 | 3.6e-7 |
  | ADF annulus (3r to 6r), image and dragged | 1.09e-6 | 1.19e-6 |
  | HAADF annulus, image and dragged | **2.35e-6** | **1.88e-6** |
  | navigator annulus | 1.57e-6 | 1.30e-6 |
  | rectangle | 6.6e-7 | 1.27e-6 |
  | off-axis DF, fractional circle, negative-bound rectangle | 2.4e-7, 2.8e-7, 2.0e-7 | 1.8e-7, 6.0e-7, 7.9e-8 |
  | point | exact | exact |

  Both cubes are dark-subtracted (106 641 of 108 900 and 52 008 of 63 550 positions hold a negative pixel), so a position's
  sum is a difference of large parts, and the Float32 sum of the old kernel is a candidate for an error of that order against
  max |image| (not isolated by an experiment). The kit's value is closer to the definition than the old one, by the kit's own pins (0.0 against float64).
- **P3 (mean and max): pass.** Max pattern exact on all five cubes. Mean pattern max |new - old| / max |old|: Al-Mg-Si 8.2e-6,
  Au_ref 1.07e-5, sim Au 3.6e-6, Particle 4.0e-6, small 7.6e-8 (bound 2e-5). Against the old kernel run with 7-row tiles
  the difference is 2.5e-7 (Al-Mg-Si): the old mean's error was the tile grouping.
- **P4 (speed): pass.** New / old wall time, median of three, streaming, the app's 16 MiB tiles, `-O` (the kit built release;
  Xcode builds it `-O` WMO under the scheme's Run configuration `Develop`, checked in the build log):

  | cube | virtual image (kit CPU) | mean + max (kit Metal) |
  |---|---|---|
  | Al-Mg-Si | 0.26 to 0.34 | 0.91 to 1.10 |
  | Au_ref | 0.24 to 0.33 | 1.01 to 1.27 |
  | sim Au | 0.46 to 1.04 | 0.50 to 0.93 |
  | Particle | 0.59 to 0.70 | 0.81 to 1.02 |
  | small | 0.22 to 0.27 | 0.95 to 1.10 |

  (two runs each; the machine was shared with other lanes.) Choice by P4: the images take `.cpu` (the kit's Metal image is 1.3 x
  slower than the old kernel on Al-Mg-Si, its CPU path 0.4 x); the mean and max take `.metal` (the kit's CPU path is 1.75 x
  the old time on Al-Mg-Si, 1.9 x on Au_ref, above the 1.5 bar). Resident cube, Al-Mg-Si: old single dispatch 0.006 to 0.02 s,
  new tile copies + CPU 0.08 to 0.09 s (not the default path: nothing requests residency by default).
  Configuration: see "Package optimisation" below.

## C2

- **P5 (centre of mass): FAIL on one cube.** |delta| in px between the new shift (kit, CPU, unclamped, NaN to 0) and the old
  (Metal, clamped), against one centre and against the fitted origins (identical to 3 digits):

  | cube | no negative pixel, sum > 0 (n, median / p95 / max) | negative pixels (n, median / p95 / max) | sum <= 0 |
  |---|---|---|---|
  | Al-Mg-Si | 2 259: 4.1e-5 / 9.4e-5 / 1.66e-4 | 106 641: 3.3e-3 / 1.76e-2 / **9.2e-2** | 0 |
  | Au_ref | 11 542: 4.9e-5 / 1.15e-4 / 2.3e-4 | 52 008: 3.3e-4 / 2.3e-2 / **3.06e-1** | 0 |
  | sim Au | 8 400: 1.2e-4 / 2.4e-4 / 4.6e-4 | 0 | 0 |
  | Particle | 4 050: 1.5e-4 / 4.3e-4 / 9.5e-4 | 0 | 0 |
  | small | 400: **3.2e-3 / 5.9e-3 / 7.0e-3** | 0 | 0 |

  The 1e-3 bound on clean positions holds on four cubes and fails on py4DSTEM's small cube (512 x 512 detector; the old
  kernel accumulates 262 144 Float32 terms per position, which is consistent with the size of the difference but was not
  isolated by an experiment; the kit is 0.0 px from float64 there by its own pins). No position holds a
  non-positive sum on any cube, so the zero-sum substitution is not exercised by the data (it is by `CuboSwitchTests`).
- **P6 (probe size, rotation): pass by record.**
  - Probe size on the old mean pattern, new `probeSize` (kit) against old (Float): |dr| <= 1.9e-6 px, |dx0|, |dy0| <= 2.3e-5 px
    (all five cubes). On each tree's own mean the radius differs by up to 8.9e-5 px (Au_ref), the mean having changed in its
    low bits. `ProbeSizeTests` pass unchanged.
  - Rotation. The kit's own chain (CoM, plane-fit reference, 1 degree grid, py4DSTEM sign) gives exactly the registered values:
    Al-Mg-Si 83 T, Au_ref 2 T, sim Au 86, Particle 80 T, small -18. The app keeps its 180-angle list (-89 to 90, the negated
    kit grid) and its 0.1 degree refinement and null, so its angle differs from the kit's by the refinement and the grid. App's
    angle shown in py4DSTEM's sign, old (on the old CoM) then new (on the new CoM): Al-Mg-Si 82.1 T then 82.7 T (kit 83 T);
    Au_ref 1.7 T then 1.7 T (kit 2 T); sim Au 85.5 then 85.3 (kit 86); Particle 78.6 T then 78.5 T (kit 80 T); small -17.2 then
    -17.4 (kit -18). Transposed flag equal everywhere; `carriesRotation` equal everywhere (true, true, true, true, false).
  - The new code on the OLD field isolates the code from the changed field: curves differ by <= 1.3e-5 relative (Al-Mg-Si 1.2e-5),
    the refined angle by 0.0 to 0.2 degrees (one to two 0.1 degree steps on a flat minimum: 82.1 to 82.2, 85.5 to 85.3, 78.6 to
    78.5, 1.7 and 17.2 unchanged). The change of the field itself (the clamp's removal) moves the curves by up to 5e-3 (Al-Mg-Si).
  - `DPC.applyRotation` on the old field and the old angle: max |new - old| 2.4e-7 to 9.5e-7 absolute (6.7e-8 to 1.2e-7
    relative).

Other timings (old to new, `-O`, three runs): centre of mass Al-Mg-Si 0.21 to 1.1-1.4 s (5 to 6 x), Au_ref 0.125 to 0.73-0.89,
sim Au 0.19 to 0.40-0.53, Particle 0.105 to 0.26-0.28, small 0.135 to 0.47-0.72 (kit CPU in place of Metal: the kit advises
CPU for dark-subtracted cubes); rotation solve Al-Mg-Si 0.19 to 0.87-1.06 s, Au_ref 0.10 to 0.52-0.72, sim Au 0.014 to 0.07,
Particle 0.006 to 0.03-0.05, small 0.001 to 0.01 (the kit's serial grid in place of the app's all-core Float loop; the null's 15
surrogates stay parallel).

## Memory of a pass (coordinator's request: the per-tile MTLBuffer audit)

Peak `MTLDevice.currentAllocatedSize` and peak `phys_footprint` over one call, sampled every 1.5 ms, Al-Mg-Si (330 x 330 x
64 x 64) and Au_ref, streaming, the app's 16 MiB tiles for images. Increase over the value just before the call
(`phys_footprint` baselines sit near 2 GB in this harness; only the increase is the call's):

| call | old: allocated / footprint | new: allocated / footprint |
|---|---|---|
| virtual image, 16 MiB tiles (109 tiles) | +16 MB / +10 MB (Au_ref +15 / +8) | +0 / +0 (CPU path, no Metal buffer) |
| virtual image, 2 MiB tiles | +4 MB / +4 MB | +0 / +0 |
| mean + max, default tiles | **+1701 MB** / +1687 MB (Au_ref +993 / +993) | +62 MB / +124 MB (Au_ref +63 / +126) |
| mean + max, 2 MiB tiles | +11 MB / +31 MB | +5 MB / +0 |

The old image pass does NOT keep every tile's buffer alive on these cubes: the allocated size peaks at one tile (16 MB) over
109 tiles, so the audit's growth did not reproduce for `tiled` at this size. The old mean + max took one 1.7 GB tile (the
app's budget is physical memory / 24); the new path takes the smaller of that and the kit's 64 MiB, and its Metal pass peaks at
62 MB. The kit's paths do not grow with the tile count.

The memory cap of the 12:30 rule: `ulimit -v` and `setrlimit` are refused by this macOS (EINVAL), so the harness stayed tiled
(its own peak is the 2 GB baseline above); the coordinator's `tools/memcap.sh` is the way, and `measure/run.sh` now uses it
(the runs above predate it).

## Package optimisation (coordinator's request: which configuration is P4 measured in)

Xcode builds a package dependency by the configuration NAME. Checked in the build log (`-verbose`, CuboVirtual and CuboCore
compile lines): the scheme's Run configuration `Develop` compiles the kit `-O -whole-module-optimization`; `Debug` compiles
it `-Onone`. The test target does not build under `Develop` ("Unable to resolve Swift module dependency"), so the in-app
numbers below are `Debug` with `SWIFT_OPTIMIZATION_LEVEL=-O` on the command line (what `tools/run-tests.sh unit` does, and
which reaches the packages) and plain `Debug`. Al-Mg-Si, streaming, 16 MiB tiles, three runs, a test host on a shared
18-core machine (the kit's CPU reducers and `RotationSolver.solve` are single-threaded; only the null's 15 surrogates fan out
through `concurrentPerform`; the images' Metal-free CPU path used one core):

| call | old (unswitched, `swiftc -O`) | new, kit `-O` (Develop-equivalent) | new, kit `-Onone` (Debug) |
|---|---|---|---|
| virtual image, ADF | 0.33 to 0.44 s | 0.09 to 0.13 s | 0.09 to 0.14 s |
| mean + max | 0.24 to 0.28 s | 0.19 to 0.25 s | 0.20 to 0.26 s |
| centre of mass | 0.21 s | 0.77 s | **48 to 58 s** |
| rotation solve | 0.18 s | 0.71 to 0.76 s | **186 to 217 s** |
| resident virtual image | 0.006 to 0.02 s | 0.075 to 0.084 s | 0.18 s |

P4 (virtual image, the registered quantity) holds in both configurations because its cost is in vDSP, which is not Swift
code. The centre of mass and the rotation solve are Swift loops in the kit: at `-Onone` they are 230 and 1000 times slower
than at `-O`. A Debug build the owner runs therefore stalls on Prepare > rotation (minutes) unless the package is
optimised: the scheme's Run (`Develop`) is not affected; a Debug run, or any unit test that calls them at scale, is.
SwiftPM gives the consumer no way to optimise a dependency in Debug (a kit finding, not patched here).

## Findings for the kit and the plan

1. **No zero-copy resident read.** `CubeSource.readScanTile` returns `[Float]`, so a resident cube (an `MTLBuffer`) is copied one
   tile at a time. `tools/virtual-detector-residency` asserted one whole-cube dispatch (a single progress tick) and zero staging
   copies for the reducers; both are retired claims for the images and the statistics. Amended assertions, same file: both arrays
   report one tick per tile, and the statistics make exactly one tile copy per tile; every equality assertion (resident ==
   tiled, bit for bit, including the statistics on the Metal path) is unchanged and passes. Cost: Al-Mg-Si resident virtual
   image 0.006 to 0.02 s becomes 0.08 s.
2. **`RotationSolver` has no cancellation and no multicore grid**; the app calls it for the grid, 21 refinement points and 15
   surrogate fields. A `scoreAngles` entry point returning only the curve, or a parallel grid, would restore the old 0.2 s.
3. **`CenterOfMassReference.normalize` is applied with `.given`** for the app's single-centre case too (a constant field):
   `.none` means "the shift is the measured centre of mass", which the app never wants.
4. **Kit convention.** The kit's first component and angle are py4DSTEM's: the field enters as (row = the app's y, column = the app's
   x), the angle negated, the transpose flag unchanged; `corrected.column` is the app's x'. Verified numerically (see P6) and
   pinned by `CuboSwitchTests`.
5. **Package optimisation.** The kit's Swift loops (`CenterOfMass`, `RotationSolver`) need `-O`; see the table above.
6. **Existing tests and gates.** No existing unit test moved: 2420 passed, 0 failed, 4 skipped before and after, plus the 7 new tests (2427). `tools/virtual-detector-test`: `center_of_mass` max error 0.0 became 1.6e-7 (passes). `tools/virtual-detector-residency` and `tools/resident-cropped-view` amended as in finding 1 (the zero-copy claim now covers the diffraction and origins only).
