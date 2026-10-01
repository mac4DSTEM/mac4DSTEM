# Slot 2 lane R — R3 ptychography ground truth, R2 the difference map (Gate D), 2026-10-01

The implementer's report verbatim (Fable 5.1). Its scripts and the logs it cites are in `slot2-r-record-2026-10-01/` (README: env and run order). The last section supersedes the earlier proposed doc lines (the refuter's corrections).

# Lane R (R3 then R2) — ptychography ground truth, then the difference map (Gate D). Report, 2026-10-01

Implementer: Fable 5.1. Lane dir $SP/R (SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/a00d4764-d3a5-4c47-8ef8-dead6b906c64/scratchpad). Written incrementally; every number names its log.

## Summary
(filled at the end)

## Diagnosis (Gate D)
(filled as the candidates are refuted)

## Predictions (dated, BEFORE each run; never edited — amendments are new dated lines)

### Gate D register (R2), written 2026-10-01 before any experiment ran
Trigger: a scientific number moves (the DM object/error) and the cause is not established. Read line by line against
`Core/Analysis/SingleslicePtychography.swift`: `ptychographic_methods.py` 1621–1668 (shift/overlap), 1811–1925 (projection sets),
2097–2180 (projection-sets adjoint), `singleslice_ptychography.py` 795–1000 (loop + constraints call), `phase_base_class.py`
1829–1917 (positions), 1923–2030 (patches/bincount), 2197–2212 (`_constraints`), `ptychographic_constraints.py` 29–57, 421–470,
1139–1200, `utils.py` `fft_shift`.

Candidates and the observation that would refute each (written first):
- (a) one mean origin vs py4DSTEM's per-pattern fitted origin (`PtychographyPreparation.swift` DEVIATION). Refuted if: on a synthetic
  cube with the origin exactly on a pixel and identical corner-centred amplitudes on both sides, the two DM runs still differ beyond
  float noise (then (a) is not the operator difference); and on graphene, if py4DSTEM forced to the app's one mean origin still shows
  the 8–15 % mid-run GD gap and the DM split.
- (b) DM parameters: app a = −α, b = 1, c = 1+α, α = `projectionParameter` (default 1), norm-min 1; py4DSTEM `DM_AP` a = −p, b = 1,
  c = 1+p, p = `reconstruction_parameter` = 1.0 in reference_ptycho.py, normalization_min 1 (phase_base_class.py 2053–2063).
  REFUTED BY THE SOURCE READ: identical. (The R1 arms: `arm-a5.log` used the options' defaults; `py-dm600.log` used 1.0.)
- (c) probe update / constraint order. py4DSTEM: adjoint (object then probe, both from the SAME exit waves and the pre-update object
  patches) then `_constraints`; app: the same accumulation inside the pattern loop, the update after the loop, then constraints.
  Identical for the update. BUT `_object_constraints` (ptychographic_constraints.py 421–470) applies `_object_threshold_constraint`
  — |object| clamped to ≤ 1 — UNCONDITIONALLY for `object_type == "complex"` (line 455–458: `if self._object_type == "complex":
  current_object = self._object_threshold_constraint(...)`), every iteration, GD and DM alike. The app's equivalent is
  `constrainObjectAmplitude`, an option that defaults to FALSE (`PtychographySettings.swift:28`) and was false in every R1 arm
  (`parallax-ptycho-real-probe/main.swift:492` builds default options). This is candidate (e1), the one the diff shows.
  Refuted if: the app's DM on graphene WITH `constrainObjectAmplitude = true` still splits from py4DSTEM's by > 10 % at iterations 3–5,
  and the GD mid-run gap stays 8–15 %.
- (d) canvas pad / object padding. py4DSTEM pads both axes by roi[0]/2 and then `center_positions_in_fov=True` shifts every position by
  (mean − canvas/2) (singleslice_ptychography.py 470–477); the app pads each axis by its own half and never recentres. For a SQUARE
  detector and a raster whose extent is an integer number of pixels, both are no-ops: graphene 101×101 at 16 px → mean 864 =
  1728/2, shift 0 (arithmetic; the R1 arms report canvas 1728 on both sides). Refuted by arithmetic for graphene; recorded as a
  real (sub-pixel) convention difference for other scans — reported, not fixed (R3's synthetic is built so the shift is 0 too).
- (e2) float32 sensitivity: DM at α = 1 is a non-contractive map; two implementations with different FFTs (vDSP vs pocketfft) may
  amplify 1e-7 differences. Tested by perturbing py4DSTEM's own input by 1e-6 relative and watching its DM history against itself.
  Refuted if the self-perturbed run tracks within 1e-3 per iteration while app-vs-py splits.

## Predictions (dated, BEFORE each run; never edited — amendments are new dated lines)
P1 (2026-10-01, before the synthetic E0 run; synthetic = 16×16 scan at 2.0 Å (3.2 px), 64×64 detector, q 0.025 Å⁻¹/px, 80 keV,
semiangle 20 mrad, rolloff 2 mrad, canvas 112², pure-phase object of 40 Gaussian "atoms" 0.2–0.6 rad, noiseless, exact starting probe;
defocus 200/400/600 Å, seed 1 each; py4DSTEM fed the SAME float32 amplitudes/positions/probe with forced zero origin shifts,
rotation 0, no recentring):
  - GD (32 it, step 0.5, norm-min 1), app with constrainObjectAmplitude = true vs py4DSTEM: error histories agree to < 1e-3 relative at
    every iteration; final object phase |Δ| < 1e-3 rad over the crop.
  - DM (α = 1, 32 it), app clamp on vs py4DSTEM: agree to < 1e-2 relative through all 32 iterations (the port is the same operator;
    noiseless data keeps the map tame).
  - app clamp OFF vs py4DSTEM: GD differs by > 1 % at some iteration; DM differs by > 10 % at some iteration (the clamp is the
    operator difference).
P2 (truth, same run): GD 32 it: Pearson(phase, truth) ≥ 0.90 on the 48×48 crop at every defocus, RMS residual < 0.10 rad (truth
std ≈ 0.1–0.15 rad); DM 32 it: Pearson ≥ 0.95, RMS < 0.05 rad; error histories monotone for GD, DM may oscillate but ends below
GD's. Registration shift |Δ| < 0.2 px on both sides. Wrong-sign defocus probe (−D, app builder): Pearson < 0.5 at every defocus.

### E0 result (2026-10-01, run-e0-1.log; scores in score-*.log): the synthetic inputs reach py4DSTEM bit-identically
(`positions/amplitudes/probe max_abs_delta 0.0` for every fixture). GD app(clamp on) vs py4DSTEM: error histories within 9.2e-3
relative (df400; P1 said < 1e-3 — NOT held at that bar; the first iteration agrees to 6e-7, the gap grows from 2e-3 at it 2),
final phase |Δ| ≤ 2.2e-3 rad on a 0.1-rad-std truth. Clamp OFF: 27 % (the clamp IS an operator difference; P1's third line held).
DM at norm-min 1: BOTH sides diverge on noiseless data with the exact probe — py4DSTEM's own DM_AP error 0.005 → 0.27 → … →
2.6e8 at it 32, truth Pearson 0.90 at it 1 then 0.25–0.58 at it 2 and ≈ 0 by it 16; the app tracks it to ≤ 1.8e-2 relative through
it 20 (then the two exponential blow-ups drift apart, 21 % at it 32). So P1's DM line held as "same operator"; P2's DM line
(converges to truth) FAILED on both sides. New candidate (f), written before the sweep: DM with `normalization_min = 1` divides the
object/probe update by the GLOBAL maximum of the probe-intensity sum instead of the local one, so the "overlap projection" the
difference map reflects about is scaled down wherever the illumination is below its maximum — it is no longer a projection, and
the reflector 2P_O − I overshoots (amp_rms 0.21–0.30 after ONE DM iteration vs 0.007 for GD). Refuting observation: if DM at
normalization_min 0.1 still diverges on the synthetic on both sides, (f) is wrong.
P3 (2026-10-01, before the sweep): DM at norm-min ≤ 0.2 converges on all three fixtures on both sides — truth Pearson ≥ 0.95 by
iteration 8 and ≥ 0.98 at 32, rms < 0.03 rad at 32 — beating GD at the same iteration count; norm-min 0.5 is marginal; app vs
py4DSTEM histories within 2e-2 at every iteration once converging. Self-sensitivity (py4DSTEM vs itself with amplitudes perturbed
by 1e-6 relative): GD histories differ by ≥ 1e-3 somewhere in 32 iterations (the app-vs-py GD gap is within the algorithm's own
sensitivity); DM at norm-min 1 differs by > 10 % by it 32. py4DSTEM's own pipeline (plane-fit origin, cubic shift, recentring,
own probe) vs the forced-same run: GD final Pearson differs by < 0.01.

### Sweep + arbiter results (2026-10-01; sweep-1.log, sens-1.log, ref64-gd.log, ref64-dm.log, score-cp.log)
P3 NOT held as written: DM at norm-min 0.5 and 0.2 still diverges on every fixture (object collapses to 0 by it 32 on both sides);
at 0.1 it peaks at it 8 (truth Pearson 0.967–0.970) and diverges by it 32 (−0.02 / 0.35 / 0.02); at 0.05: 0.974–0.985 at it 8,
0.03 / 0.71 / 0.94 at 32; at 0.02: 0.987–0.992 at it 8 (better than GD's 0.95–0.97 at it 8), 0.02 / 0.976 / 0.977 at 32 (df200
collapses). GD (nm 1) 0.983–0.985 at 32, GD (nm 0.1) 0.991. The app tracks py4DSTEM through every one of these (error rel diff
≤ 1.8e-2 while both converge; final objects within 0.02–0.06 rad where both are still converging; identical collapse where not).
Candidate (f) stands only in part: the normalization is why DM at the app's default (1) fails at once; a small normalization
makes DM the better method for ≤ 8 iterations and does NOT make it stable. py4DSTEM's vendored tutorials never call DM_AP (grep,
References/, 0 hits). Self-sensitivity to a 1e-6 amplitude perturbation: 3e-7 (GD), 8e-4 (DM nm 1) — P3's "≥ 1e-3" NOT held,
because that perturbs the data, not the model's rounding (see the arbiter). py4DSTEM's own pipeline vs the forced-same inputs
(plane-fit origin 31.998/31.995 px → cubic shift; recentring 0 px as built): amplitudes differ up to 4 % (113 / 2648), GD truth
Pearson 0.9848 vs 0.9849 (unchanged), error history 1.4e-3 at it 1 → 21 % at it 32 (the relative gap of a 4e-5 error) — P3's
last line held. The arbiter (float64 numpy, ref64.py): after ONE GD iteration from identical inputs the float64 code differs from
the app by 5.1e-3 and from py4DSTEM by 4.4e-3; its own float32 twin differs from them by 4.9e-3 / 3.4e-3. Every pair differs by
≈ 5e-3 after one iteration, so the app–py4DSTEM gap IS the float32 band, not an operator difference. Mechanism (hypothesis, test
next): at iteration 1 the model spectrum is the band-limited probe; outside its aperture |F| is rounding noise while the measured
amplitude is not, so `A·F/|F|` takes a rounding-seeded phase there and each implementation seeds it differently.
P4 (before the run): ref64.py with the projection phase forced to 0 where |F| < 1e-6·max|F| (both dtypes): float64 vs float32
agree to < 1e-4 at iteration 1 (vs ≈ 5e-3 without the mask). If they still differ by ≈ 5e-3, the mechanism is wrong.
P5 (fixed probe, before the run): DM with the probe FIXED (py4DSTEM fix_probe=True; app fixProbe) at nm 0.1 converges monotonically
on all three fixtures — truth Pearson ≥ 0.98 at it 32 on both sides, no collapse — i.e. the instability is the joint probe update.
P6 (seeds, before the run): fixtures df400 seeds 2 and 3: GD nm 1 truth Pearson at it 32 within 0.975–0.990 on both sides, app–py
error rel diff max < 3e-2; wrong-sign probe (app-built at −D) GD Pearson < 0.5 on every fixture.
P4 HELD (ref64-mask.log): float64 vs float32 after one GD iteration 4.2e-3 unmasked → 1.49e-7 with the projection phase forced to
0 where |F| < 1e-6·max (and the same at 1e-4). The app–py4DSTEM GD gap is rounding-seeded phases at zero-model Fourier pixels;
the operator is the same. GD truth scores, all fixtures (score-gd-all.log): app it 32 Pearson 0.9834 / 0.9851 / 0.9841, rms
0.018 / 0.017 / 0.018 rad (py4DSTEM 0.9833 / 0.9849 / 0.9841); app-built probe path 0.9833 / 0.9853 / 0.9840 (|Δ| to the fixture
probe path ≤ 2e-4); app–py error rel diff max 1.3e-2 / 9.2e-3 / 1.8e-2 (fixture probe), ≤ 3.2e-2 (app-built probe, which differs
from ComplexProbe at 1.7e-6 — the same rounding band); final phase |Δ| ≤ 1.5e-2 rad. Wrong-sign probe (−D, app-built) GD: Pearson
0.12 / 0.20 / 0.13 at it 32 with registration shifts of 9–20 px (no alignment found) — P2's control line held. Clamp off vs truth:
0.9834 / 0.9845 / 0.9825 (vs 0.9834 / 0.9851 / 0.9841 on) — the clamp changes the result by < 2e-3 in Pearson here (pure-phase truth).
P5 PARTLY held (seeds-fixp-1.log, py4DSTEM fixed probe): nm 0.1 — no collapse on any fixture (it 8: 0.983 / 0.979 / 0.980; it 32:
0.948 / 0.978 / 0.971) but not monotone (df200 falls 0.983 → 0.948) and below the predicted 0.98 on two of three; nm 1 with the
probe fixed still diverges (0.27 / 0.22 / 0.20 at it 8). So the normalization at 1 is fatal on its own; the joint probe update
adds the late collapse. P6 held: seeds 2/3 GD it 32 py 0.9803 / 0.9873, app 0.9804 / 0.9874; wrong sign 0.20 / 0.21; app–py GD
error rel max in seeds-rel.log. DM nm 0.02 seeds 2/3 at it 8: py 0.983 / 0.986, app 0.986 / 0.988 (tracking ≤ 4.3e-3); at it 32
py 0.037 / 0.885 vs app 0.976 / 0.988 — past ≈ 16 iterations the two DMs part ways (final |Δ| 1.18 rad on seed 2): the map is
chaotic there and no implementation detail decides it.
G1 (graphene, before the run; cube /Volumes/PL_SSD_2TB/4D_STEM_Datacubes/twisted_bilayer_graphene.hdf5, defocus −600, rotation 0,
8 iterations, q 0.025, R 5.0, 80 kV, semiangle = the app's half-max radius 25.24 px): app DM nm 1 with the clamp ON vs py4DSTEM
DM_AP nm 1 at −600: iterations 1–3 within 2 % (R1's clamp-off arm at +600 was 10.7 % at it 3), both non-monotone after; the
clamp-off arm at −600 splits by > 5 % at it 3. G2: at nm 0.05 both DMs' 8-iteration object phase correlates with py4DSTEM's GD −600
object (py-df-600-auto, R1 scratch) at ≥ 0.6 after registration, and with each other at ≥ 0.6; their error histories within 5 %
at every iteration. G3: the app's DM nm 0.05 final error is below its GD −600 final error (2.64e-4, arm-a2.log).
App–py4DSTEM DM error-history relative maxima (seeds-rel.log = the table printed 2026-10-01 from sweep/, out/, seeds/):
| run | it 1–8 | it 1–16 |
|---|---|---|
| nm 1 df200 / 400 / 600 | 2.7e-2 / 1.8e-2 / 4.2e-3 | 2.7e-1 / 1.8e-2 / 1.2e-1 |
| nm 0.5 | 3.8e-2 / 2.5e-2 / 2.5e-2 | 3.8e-2 / 2.9e-2 / 3.3e-2 |
| nm 0.2 | 2.8e-2 / 2.7e-2 / 1.9e-3 | 4.6e-2 / 3.9e-2 / 1.9e-3 |
| nm 0.1 | 3.9e-3 / 3.4e-3 / 2.3e-3 | 6.1e-2 / 3.4e-3 / 3.7e-2 |
| nm 0.05 | 3.8e-3 / 4.6e-3 / 1.5e-3 | 3.8e-3 / 6.6e-3 / 1.5e-3 |
| nm 0.02 | 3.2e-3 / 5.2e-3 / 1.2e-3 | 7.4e-3 / 6.8e-3 / 2.3e-3 |
| nm 0.02 seeds 2 / 3 (df400) | 4.3e-3 / 4.3e-3 | 1.2e-2 / 9.0e-3 |
GD (nm 1, clamp on) app–py rel max over 32 it: 1.3e-2 / 9.2e-3 / 1.8e-2 (df200/400/600), 7.5e-3 / 1.3e-2 (seeds 2/3).
Graphene, py4DSTEM side (gr/py-dm-m600-nm1.log, gr/py-dm-m600-nm0.05.log; −600 Å, rotation 0, 8 it): DM_AP nm 1 errors
[0.0627 0.1129 0.0670 0.3656 0.2969 0.7674 0.1677 0.5521] (non-monotone, phase std 1.24 rad = filled ±π); nm 0.05
[0.0627 0.0122 0.0066 0.0493 0.0932 0.3902 0.7324 4.5286] — three converging iterations, then it diverges; phase std 1.26.
So G2's py4DSTEM half will not hold at 8 iterations (py4DSTEM's own DM diverges on this cube at nm 0.05 by it 4); the app arms decide
whether the two agree in doing so. (truth.py trap found and fixed before the harness ran: py4DSTEM keeps `initial_probe_guess` by
reference and updates it in place — the first run rewrote the fixture's probe for the next ones; `.copy()` + an assert now.)
Graphene app arms (gr/arm-r2a..d.log, 2026-10-01 10:00–10:05, −600 Å, 8 it; py side gr/py-dm-m600-nm*.log and R1's py-df-600-auto):
r2a DM nm 1 clamp ON  [0.062454 0.113139 0.050017 0.311165 0.162338 0.805543 0.575337 0.347774]
r2b DM nm 1 clamp off [0.062454 0.113139 0.078678 0.723686 6.292641 0.603341 0.353963 0.536872]
r2c DM nm 0.05 clamp ON [0.062454 0.012174 0.006258 0.049027 0.092657 0.386500 0.732504 4.794999]
r2d GD clamp ON [0.062454 0.015651 0.004259 0.001322 0.000558 0.000354 0.000297 0.000278]
G1 NOT held: with the clamp on, the app's DM at nm 1 matches py4DSTEM's at it 1–2 (0.3 %, 0.2 %) and splits at it 3 (0.0500 vs
0.0670, 25 %; clamp off 17 %): at nm 1 the map diverges from iteration 1 on both sides and the float band separates them by it 3
on this noisy cube, as the synthetic showed at nm 1 (1.8e-2 within 8 it, 27 % by 16). G2's py4DSTEM half failed (its DM diverges by
it 4 at nm 0.05); the parity half HELD better than predicted: at nm 0.05 the app's DM tracks py4DSTEM's through the whole
divergence — per-iteration gaps 0.3 / 0.4 / 5 / 0.6 / 0.6 / 1 / 0.01 / 6 % (gr-compare.log). G3 moot (both DMs diverge).
P7 (before the harness run): tools/singleslice-ptychography-test/run.sh prints "all passed", exit 0; its new section's rows show GD
Pearson 0.983–0.985, rms 0.017–0.018, shifts |Δ| ≤ 0.02 px, app–py GD histories 9e-3–1.8e-2, phase ≤ 6e-3 rad, clamp-off gaps
0.20–0.31, wrong sign 0.12–0.20, DM nm 1 within 2.7e-2 and nm 0.02 within 5.2e-3; the Swift scorer within 2e-3 of truth.py's.
Runtime < 3 min including the swiftc build.
gr-compare.log (graphene): GD −600 with the clamp ON vs py4DSTEM GD −600: per-iteration gaps 0.32 / 0.42 / 0.45 / 0.22 / 0.37 / 1.1 /
1.5 / 1.7 % (R1's clamp-off arm a2: 0.3 / 0.7 / 2.5 / 8.6 / 8.4 / 2.4 / 1.9 / 3.3 %) — candidate (e1) HOLDS for GD: the 8–15 %
mid-run gap of every R1 arm was the missing amplitude clamp. Object phase vs py4DSTEM's: raw 0.688 / registered 0.687 / σ4
low-passed 0.886 (R1 at −600: 0.690 / 0.689 / 0.791), rms 0.0136 rad, shift (0.0, 0.05) px. DM nm 0.05 app vs py: both filled ±π
(std 1.28 / 1.25), phase Pearson 0.577 raw / 0.590 registered — the two implementations diverge the same way.
harness-1.log: EXIT=133 in 18 s — Foundation's JSON reader refused a denormal double (1.17e-313, a parabolic-peak shift in
truth.py's scores); fixed by zeroing |x| < 1e-300 in `score`. P7 stands for harness-2.

## Diagnosis (Gate D) — the register's outcome
Question: why the app's DM and py4DSTEM's differ 8–15 % mid-run on graphene, and whether the ported DM converges.
- (a) one mean origin vs per-pattern: NOT the operator difference — on bit-identical synthetic inputs (no origin step on either
  side) GD and DM behave as described under (e1)/(e2); on the synthetic, py4DSTEM's own origin pipeline changes amplitudes by up to
  4 % and the GD truth score by 1e-4 (0.9848 vs 0.9849). Remains a recorded DEVIATION; no number it moves was found.
- (b) DM parameters: refuted by the source read (identical a, b, c, α, norm-min).
- (c)/(e1) the unconditional |object| ≤ 1 clamp (py4DSTEM `_object_threshold_constraint`): SURVIVES for GD — on graphene it is the
  whole 8–15 % mid-run gap (≤ 1.7 % with the clamp, gr-compare.log); on the synthetic clamp-off GD differs 20–31 % from py4DSTEM
  while clamp-on differs ≤ 1.8e-2. For DM it is necessary but not sufficient (r2a vs r2b).
- (d) canvas pad / recentring: refuted by arithmetic for square detectors and integer-pixel scan extents (graphene, the synthetic);
  a real sub-pixel convention difference otherwise — reported, not fixed.
- (e2) float32 sensitivity: SURVIVES as the explanation of every residual gap. Proven on the arbiter: one GD iteration from
  identical inputs differs by ≈ 5e-3 between float64 and float32 of the SAME code, and by 1.5e-7 once the projection phase is
  zeroed where the model spectrum is rounding noise (outside the probe aperture at the flat start). DM at norm-min 1 is an
  expanding map from iteration 1 (py4DSTEM's included), so this band grows to 25 % by iteration 3 on graphene and 27 % by 16 on the
  synthetic; at norm-min ≤ 0.05 the two DMs track each other through 8 iterations on the synthetic (≤ 5e-3) and on graphene
  (≤ 6 %), including through py4DSTEM's own divergence.
- (f) normalization_min = 1 turns DM's overlap projection into a scaled-down one: it is why the app's default DM fails at once
  (amp_rms 0.21–0.30 after one iteration vs 0.007 for GD; truth Pearson 0.90 → 0.25–0.58 at it 2). A small normalization makes
  DM the better method for ≤ 8 iterations (0.987–0.992 vs GD 0.95–0.97 at it 8) and does not make it stable: it collapses by
  iteration 32 at every normalization on at least one of five fixtures, with the probe fixed it drifts (0.983 → 0.948), and on
  graphene py4DSTEM's own DM_AP diverges from iteration 4 at norm-min 0.05 and from iteration 1 at norm-min 1.
Survivor: the ported DM IS py4DSTEM's DM_AP (same operator, same trajectories, same divergence); what differs on graphene is the
clamp (fixed by one option) and, past it, float32 sensitivity of an unstable iteration. The algorithm as exposed — py4DSTEM's
DM_AP with joint probe update and the app's normalization default — does not converge on noiseless synthetic data or on the
graphene cube on EITHER side; py4DSTEM's vendored tutorials never use it.
harness-3.log (2026-10-01): "singleslice-ptychography-test: all passed", EXIT=0, 232 s wall (P7's "< 3 min" NOT held: 3.9 min
including the swiftc build, reference.py, truth.py 12 s and the 38 MB JSON decode); every number in P7 held — rows in the log.
harness-2.log: EXIT=133, a second JSON refusal (8.2e-298): the harness decodes every array as [Float], so truth.py now zeroes
|x| < 1e-37 (float32's normal floor) in `fmt`. Both failures were the fixture's encoding, not the science.
P8 (before the mutation runs, each a full harness run under the lock, exit on its own line in mut/<name>.log): defocus-sign
(Core `chi`: −defocus → +defocus) → red at the app-built-probe check (its Pearson ≈ 0.13–0.20 against the fixture probe's 0.98);
dm-projection-a (Core: a = +α) → red at the DM parity check (nm 1 or 0.02, gap ≫ 0.1); clamp-off (harness runs GD with the clamp
off) → red at the GD parity bar (gap 0.20–0.31 > 5e-2); neg-control-off (the "wrong sign" probe built at +D) → red at the
wrong-sign check (Pearson 0.98, not < 0.5); scorer-mean (Pearson without mean removal) → red at the scorer cross-check (|ΔPearson|
≥ 2e-3 against truth.py's). Each restored byte-identical (cmp) and the harness green again (harness-3 stands as the green run;
a final green run follows the last mutation).

## Changes
- tools/singleslice-ptychography-test/truth.py (NEW): the synthetic truth cube (16×16 scan, 64² detector, defocus 200/400/600 Å,
  pure-phase object of 40 Gaussians) and py4DSTEM's own GD (32 it) / DM_AP (8 it at norm-min 1 and 0.02) on bit-identical inputs,
  scored against truth; source-locks the unconditional clamp and the DM exit-wave reset; float32-exact JSON.
- tools/singleslice-ptychography-test/main.swift: `TruthDocument` + `scoreAgainstTruth` (registration, phase offset, Pearson, RMS)
  and the R3 section (scorer cross-check, GD parity + truth bars, app-built probe, wrong-sign control, clamp-off anti-vacuity,
  DM parity over 8 iterations; DM truth scores printed, not pinned). run.sh runs truth.py and passes truth.json as argv[2].
- tools/parallax-ptycho-real-probe/main.swift: `--constrain-amplitude 0|1` (py4DSTEM's unconditional |object| ≤ 1 clamp), recorded
  in the saved JSON; usage string.
- Core: UNCHANGED (no number moved; the diagnosis found no port error). App/UI: untouched (outside the write-set; lines proposed).

## Tests (new checks, each broken; mut/<name>.log, exit on its own line)
(filled from mut/all.log below)

## Runs
| what | log | exit |
|---|---|---|
| dump tool builds (swiftc, ptychography sources) | build-dump-1.log, build-dump-2.log | 0, 0 |
| synthetic E0 (3 fixtures × py same GD/DM × app 8 variants) | run-e0-1.log | 0 |
| scores / per-checkpoint | score-cp.log, score-gd-all.log | 0 |
| arbiter | ref64-gd.log, ref64-dm.log, ref64-mask.log | 0 |
| norm-min sweep | sweep-1.log | 0 |
| sensitivity + own pipeline | sens-1.log | 0 |
| fixed probe + seeds | seeds-fixp-1.log | 0 |
| graphene (lock 09:58–10:05) | graphene-run.log, gr/py-dm-m600-nm{1,0.05}.log, gr/arm-r2{a,b,c,d}.log, gr-compare.log | all 0 |
| harness | harness-1.log 133 (denormal), harness-2.log 133 (sub-Float), harness-3.log 0 (232 s) | |
| core / inventory | core-1.log 0, inventory-1.log 0 (rerun at the end: core-2 / inventory-2) | |

## Measurements
Synthetic truth (position-bounds 48×48 crop, truth phase std 0.097 rad; Pearson / rms rad), app = clamp on, fixture probe:
| fixture | GD 8 it app / py | GD 32 it app / py | DM nm 1, 8 it app / py | DM nm 0.02, 8 it app / py | DM nm 0.02, 32 it app / py |
|---|---|---|---|---|---|
| df200 s1 | 0.941 / 0.940 | 0.9834 / 0.9833 (0.018) | 0.03 / 0.05 | 0.988 / 0.989 | collapsed / 0.02 (sweep-1) |
| df400 s1 | 0.952 / 0.952 | 0.9851 / 0.9849 (0.017) | 0.25 / 0.21 | 0.989 / 0.987 | 0.975 / 0.976 |
| df600 s1 | 0.946 / 0.946 | 0.9841 / 0.9841 (0.018) | 0.06 / 0.03 | 0.992 / 0.992 | 0.978 / 0.977 |
| df400 s2 | — | 0.9804 / 0.9803 (0.018) | — | 0.986 / 0.983 | 0.976 / 0.037 |
| df400 s3 | — | 0.9874 / 0.9873 (0.017) | — | 0.988 / 0.986 | 0.988 / 0.885 |
(harness-3.log rows for s1; seeds-fixp-1.log for s2/s3; sweep-1.log for the 32-it DM.) Wrong-sign probe GD 32 it: 0.12 / 0.20 / 0.13
/ 0.20 / 0.21. DM over norm-min at 32 it (py, s1, three fixtures): 0.5 → collapse ×3; 0.2 → collapse ×3; 0.1 → −0.02 / 0.35 / 0.02;
0.05 → 0.03 / 0.71 / 0.94; 0.02 → 0.02 / 0.98 / 0.98; GD nm 0.1 → 0.991 ×3. Fixed probe DM nm 0.1 at 32: 0.948 / 0.978 / 0.971.
Parity (app vs py4DSTEM, relative error-history gap): GD 32 it ≤ 1.8e-2 (five fixtures; the float32 band, arbiter 5e-3 per
iteration); DM 8 it ≤ 2.7e-2 at nm 1, ≤ 5.2e-3 at nm 0.02 (table above, seeds-rel). Graphene: GD clamp on ≤ 1.7 % (was 8.6 %);
DM nm 0.05 ≤ 6 % through a shared divergence; DM nm 1 25 % at it 3.
Cost: harness 232 s wall (harness-3.log); each app graphene DM stage 40 s / 1.98 GB, GD 24 s / 0.73 GB (arm-r2*.log SUMMARY lines).
UI cost: none (no UI change).

## Deviations from the brief
1. R3's "register … Pearson and offset-removed RMS on the illuminated interior": the crop is the position-bounds crop the app
   displays (= py4DSTEM's object_cropped), not a probe-intensity threshold (a threshold would be a dataset property).
2. "record the error history per iteration": the data-error history is recorded on both sides for every run; the TRUTH score
   per iteration is recorded for py4DSTEM (store_iterations) and at checkpoints 1/2/4/8/16/32 for the app (score-cp.log,
   sweep-1.log), not every iteration.
3. DM gets NO convergence bar in the harness (the data refuse one: it collapses by it 32 on ≥ 1 of 5 fixtures at every
   normalization); parity over 8 iterations is pinned instead and the truth scores printed.
4. The ≥ 3 seeds/defocus rule: 3 defocus values × seed 1 in the harness; seeds 2/3 at df400 in the exploration (5 fixtures) —
   the bars sit ≥ 2.8× outside all five.
5. The brief's "the DM is non-monotone in py4DSTEM too at these settings" is confirmed and sharpened: it diverges in py4DSTEM at
   EVERY setting tried on noiseless data by it 32, and on graphene by it 4 at nm 0.05.
6. Gate D fix: none in Core. The one option that moves graphene's GD onto py4DSTEM's history (the clamp) already exists; its
   default lives in App/PtychographySettings.swift (outside the write-set) — proposed below, not changed.

## Proposed doc lines
status.md handoff (R row): "R2/R3 (2026-10-01): ground truth harness — GD reaches a known object with a defocused probe
(Pearson 0.983–0.985 at 32 it, rms 0.017–0.018 rad, three defocus values; app = py4DSTEM to ≤ 1.8e-2 on bit-identical inputs;
wrong-sign probe 0.12–0.20). DM diagnosed: the port IS py4DSTEM's DM_AP (tracks it through 8 iterations at ≤ 2.7e-2 synthetic,
≤ 6 % graphene), and that algorithm diverges on both sides — at the app's default normalization from iteration 1, at any
normalization by 32 (synthetic) / 4 (graphene, nm 0.05). Owner card: remove DM (ADR 049) or keep it capped. The 8–15 % GD
mid-run gap on graphene was py4DSTEM's unconditional |object| ≤ 1 clamp (app option, default off): 1.7 % with it on."
open-items: replace the DM line with "Difference map: diverges on both sides (py4DSTEM's DM_AP included) on noiseless synthetic
data and on graphene; owner decision pending (remove / keep with the clamp forced, norm-min default ≤ 0.05 and ≤ 8 iterations)."
Add: "Ptychography `constrainObjectAmplitude` defaults to off; py4DSTEM clamps always. Parity needs it on — flip the default
(App/PtychographySettings.swift:28) or label the difference."
plan Log: "R2+R3 landed 2026-10-01 — truth.py + harness R3 section (harness-3.log 0, 232 s; 5 mutations red); Gate D: no port
error, DM diverges in py4DSTEM too; clamp explains GD's 8–15 %; graphene arms r2a–d."
Record: docs/archive/v4/slot2-r-record-2026-10-01.md = this report (the supervisor's call).

## Decision sheet input (DM, for the owner; ADR 050 format)
Problem: the app's difference map, py4DSTEM's DM_AP ported faithfully, does not converge — in py4DSTEM either.
A. Remove DM (recommended; ADR 049 finish-or-remove, lean app): delete `.differenceMapAlternatingProjections`, the retained
   exit waves, `projectionParameter` and its UI row; the harness keeps GD's truth bars. Effort ½ session; risk none (GD is the
   method the owner has driven; py4DSTEM's tutorials use GD only).
B. Keep DM as a short-burst method: clamp forced on, normalization default 0.02–0.05 for DM, iterations capped at 8 (where it
   beats GD: 0.987–0.992 vs 0.95–0.97 on the synthetic), labelled "unstable past 8". Effort 1 session + drive; risk: the cap and
   default are dataset properties (five fixtures, one real cube); graphene diverges at it 4 even at nm 0.05.
C. Keep as is, labelled "diverges": no code; the room ships a method that fails at its defaults.
Second opinion: the refuter should check whether DM with a FIXED probe (py fix_probe) at nm 0.1 is stable enough to be
offered as "DM, probe fixed" — measured 0.948–0.978 at 32 it without collapse (seeds-fixp-1.log); not pursued here.

## Open questions for the supervisor
1. App default `constrainObjectAmplitude = true` (parity with py4DSTEM; truth score unchanged within 2e-3): a one-line App change
   outside this lane's write-set — yours or a card.
2. The harness now takes 232 s (was faster); if the scientific gate budget minds, truth.py can drop to two fixtures or the JSON
   to float16-safe sizes — I left the measured geometry in.
3. R1's record rows (8–15 % mid-run GD gap) can be amended: cause = the clamp (gr-compare.log).
4. `tools/parallax-ptycho-real-probe/run.sh`'s header comment does not list the new flag (one line; left for the commit).
P9 (before the run): mutation dm-nm-mismatch (the harness runs the app's DM at half py4DSTEM's normalization) → red at the NEW
DM parity check only (the dm-projection-a mutation was caught first by the pre-existing 4×6 DM fixture, so it does not show the
new check bites); expected message "DM (norm-min 1.0, 8 it) error history differs … (limit 0.1)".

## Tests — results (mut/all.log, mut/dm-nm-mismatch.out; each restored byte-identical by cmp; harness-4.log green after, EXIT=0, 234 s)
| mutation | red exit | caught by |
|---|---|---|
| defocus-sign (Core chi −defocus → +defocus) | 133 | the pre-existing R1 ComplexProbe pin fires first ("probe case defocus only, |Δ| 0.124") — P8 named the new app-built-probe check; the harness stops at the earlier check, so the new one's bite is shown by neg-control-off instead |
| dm-projection-a (Core a = +α) | 133 | the pre-existing 4×6 DM fixture ("DM/AP iteration errors differ") |
| dm-nm-mismatch (app DM at half py's norm-min) | 133 | NEW DM parity check: "differs by 851 (limit 0.1)" (P9 held) |
| clamp-off (harness GD without the clamp) | 133 | NEW GD parity bar: 0.197 > 5e-2 (P8 held) |
| neg-control-off (control probe built at +D) | 133 | NEW wrong-sign check: 0.9833 vs 0.9834 (P8 held) |
| scorer-mean (Pearson without mean removal) | 133 | NEW scorer cross-check: 0.9865 vs 0.9833 (P8 held) |
core-2.log: core EXIT=0; inventory-2.log: inventory EXIT=0 (both on the restored tree).

## Summary
1. R3: the ptychography harness now scores the app against a KNOWN object with a defocused probe (3 defocus values) and against
   py4DSTEM on bit-identical inputs: GD reaches truth (Pearson 0.983–0.985, rms 0.017–0.018 rad; app = py4DSTEM to ≤ 1.8e-2;
   wrong-sign probe 0.12–0.20); harness-4.log all passed, EXIT=0; 6 mutations red.
2. R2 Gate D: the ported DM IS py4DSTEM's DM_AP (same trajectories to ≤ 2.7e-2 synthetic / ≤ 6 % graphene at nm 0.05, same
   divergence); the algorithm diverges on BOTH sides — at the app's default normalization from iteration 1, at every normalization
   by it 32 on noiseless data, on graphene by it 4; residual gaps are the float32 band of an unstable map (arbiter: 5e-3 per
   iteration from rounding-seeded phases, 1.5e-7 masked). No Core fix; owner card: remove DM (recommended) or cap it.
3. The 8–15 % mid-run GD gap of R1's graphene arms was py4DSTEM's unconditional |object| ≤ 1 clamp: with the app's existing
   option on it is ≤ 1.7 % (gr-compare.log). Proposed: flip the App default (outside this lane's write-set).

## git status --short (final, git-status-final.txt)
 M tools/parallax-ptycho-real-probe/main.swift
 M tools/singleslice-ptychography-test/main.swift
 M tools/singleslice-ptychography-test/run.sh
?? tools/singleslice-ptychography-test/truth.py

## 2026-10-01, after the refuter (HOLDS WITH CORRECTIONS; $SP/R/refuter.md) — corrections applied
- (2) main.swift check (6): the DM norm-min 1 parity is now PRINTED, not pinned (an expanding map, 3 fixtures, 3.7× margin); the
  norm-min 0.02 pin (≤ 5e-2; measured ≤ 5.2e-3 on 5 fixtures) stays. Re-run: harness-5.log (below). The dm-nm-mismatch mutation
  targeted the nm 1 pin ("norm-min 1.0 … 851 (limit 0.1)"); it halves BOTH normalizations, so the nm 0.02 pin should now catch it
  (app at 0.01 vs py at 0.02) — P10 (before the run): red at "DM (norm-min 0.02, 8 it) … (limit 0.05)"; if the gap at 0.01 vs 0.02
  is under 5e-2 the mutation no longer bites and that is recorded as such.
- (6) tools/parallax-ptycho-real-probe/run.sh header names `--constrain-amplitude`.
- (1) $SP/R/archive/ staged (280 KB, no file > 500 KB, no .npy): synth.py, ref64.py, probe_repro.py, the drivers reconstructed
  verbatim from the session's inline commands (run-e0.sh, run-sweep.sh, run-sens.sh, run-seeds-fixp.sh, run-arbiter.sh,
  gr-compare.sh), graphene.sh, finish.sh, harness.sh, build-dump.sh, mutate.sh, mutate-all.sh, mutate2.sh, dump/main.swift, the
  refuter's dm64.py + dm64-wrongprobe.py, logs/ (harness-4, mut-all, mut-dm-nm-mismatch, sweep-1, seeds-fixp-1, sens-1,
  ref64-*, gr-compare, arm-r2a–d, py-dm-m600-nm*, graphene-run, run-e0-1, score-*, dm64-*) and a README with the env and the run
  order. SP is a required variable in the lock-taking scripts; REPO/PYTHON default at the top. Left out: fixture JSONs (12 MB each,
  `synth.py make` regenerates them), run-output JSONs, truth-*.json (38 MB; truth.py), *.npy.

### Proposed doc lines, rewritten (supersede the earlier section; refuter must-fix 3–5)
status.md handoff (R row): "R2/R3 (2026-10-01): the ptychography harness scores the app against a known pure-phase object with a
defocused probe (200/400/600 Å), STARTING FROM THE EXACT PROBE (a self-consistency test of the inverse operator and the defocus
sign, not probe recovery) and against py4DSTEM 0.14.19 on bit-identical inputs at matched settings (fix_probe_com=False,
clamp on): GD at 32 it Pearson 0.983–0.987 / rms 0.017 rad on a 0.097-rad truth, still converging (0.994 / 0.011 at 64,
dm64-1.log); app = py4DSTEM to ≤ 1.8e-2; wrong-sign probe 0.12–0.21. 4 new checks broken, 2 mutations caught upstream. DM:
the port is py4DSTEM's DM_AP (tracks it ≤ 5.2e-3 over 8 it at nm 0.02; ≤ 6 % on graphene at nm 0.05); py4DSTEM's single-pass
DM_AP with the joint probe update collapses on both sides — float64 too (dm64-1.log), on graphene by it 4 — owner card: remove.
The GD gap on graphene (8.6 % on R1's arm a2) was py4DSTEM's unconditional |object| ≤ 1 clamp: 1.7 % with the app's option on
(gr-compare.log). Scientific gate +≈ 3 min (harness 234 s). Record: docs/archive/v4/slot2-r-record-2026-10-01/."
open-items: replace the DM line with "Difference map: py4DSTEM's single-pass DM_AP with joint probe update diverges on both sides
(noiseless synthetic, float64 included; graphene by it 4 at its best normalization); owner decision pending — remove (refuter
and lane agree) / keep labelled." Add: "Ptychography parity with py4DSTEM needs two switches the app defaults OFF: the
|object| ≤ 1 clamp (`constrainObjectAmplitude`, py4DSTEM unconditional) and the probe-CoM constraint (py4DSTEM default
fix_probe_com=True; parity was measured with it off on both sides). Flipping the clamp default moves a user-visible amplitude map
on real data (the probe/object scaling ambiguity is re-split): Gate D trigger — run graphene arm r2d before/after and record it."
plan Log: "R2+R3 landed 2026-10-01 — truth.py + harness R3 section (harness-5.log 0, 234 s; P7's < 3 min NOT held, the gate grew
≈ 3 min); 4 new checks broken (clamp-off, neg-control-off, scorer-mean, dm-nm-mismatch), defocus-sign and dm-projection-a caught
upstream by R1's probe pin and the 4×6 DM fixture; Gate D: no port error, DM collapse intrinsic (refuter's float64), clamp
explains the GD gap; graphene arms r2a–d; archive slot2-r-record-2026-10-01/."
Results of the corrections (2026-10-01): harness-5.log "all passed", EXIT=0, 232 s (DM nm 1 gaps now printed in its rows: 2.7e-2 /
1.8e-2 / 4.2e-3). P10 HELD: dm-nm-mismatch against the unpinned harness is red at the nm 0.02 pin — "DM (norm-min 0.02, 8 it)
error history differs from py4DSTEM's by 0.290984 (limit 0.05)", EXIT=133 (mut/dm-nm-mismatch-2.out; main.swift restored
byte-identical). core-3.log EXIT=0; inventory-3.log EXIT=0. Archive updated with harness-5.log and mut-dm-nm-mismatch-2.log.
git status --short (my files only; the other lane's edits are also in the tree): M tools/parallax-ptycho-real-probe/main.swift,
M tools/parallax-ptycho-real-probe/run.sh, M tools/singleslice-ptychography-test/main.swift, M tools/singleslice-ptychography-test/run.sh,
?? tools/singleslice-ptychography-test/truth.py.
