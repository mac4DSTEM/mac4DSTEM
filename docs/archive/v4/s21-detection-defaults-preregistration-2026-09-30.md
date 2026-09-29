# S21 — detection defaults on the bullseye cube: pre-registration (2026-09-30, before any measurement)

Pre-registered from HEAD f73be56 by reading code and records only; the only number computed is the probe's own profile (below).
YELLOW item: measure, refute, propose. A moved number is never committed by this session.

**Dropped, one line:** "TBG finds only the beam" is not measured — no twisted-bilayer-graphene file exists among the nine `.h5` in
`References/training_dataset`, Thronsen A or the demo, and it is off the precipitate/microprobe path (plan drops it).

## Question
"Bullseye detection accepts noise: outer-edge probe size for structured probes open" (open-items.md:77;
`archive/open-items-2026-09-07.md:37`). Which default cuts false detections on the bullseye cube against the A2 labels, and does it move a pinned dataset?
Facts read (not outcomes): probe_template slice 0 is a beam plus a ring — azimuthal mean about (124.76, 124.74), fraction of max by radius 0..11:
1, .985, .76, .31, .055, .065, .34, .67, .76, .58, .24, .05. `OriginCalibration.probeSize` gives r = 7.36 px on it (6.84 on the app's meanDP path; 7.129 pinned);
the 20 %-outer-edge rule (`tools/disk-detector/simulate.py` `probe_radius`, read outside-in) gives 11 (earlier profile read: 11.5).
The app's default flow sets `minPeakSpacing = round(r) = 7` (`DiskDetectionParams.detectorAdapted`, `DiskDetection.swift:552`) at floor 0.15 %, cap 70.
`probeSize` also feeds the origin window (`OriginCalibration.swift:513/570`): it is NOT changed here, only the detection path is (else stop: own Gate D).

## Flows measured (each scored on its own)
- **B_syn** (the app default, Source = Synthetic): trench kernel at r from meanDP (6.84), spacing 7, edge 10, minRel 0.0015, sigmaCC 2, corrPower 1, cap 70.
- **B_flat** (Use File's Probe + Flat): flat kernel from probe_template slice 0, origin from `probeSize` (record 125,125 as well), same params.
Engine: production `DiskDetector`/`ProbeKernel` copied into `$SP/s21/` (a scratch build, tree untouched), not py4DSTEM.

## Datasets
Truth: `tools/disk-detector/labels/bullseye-2026-09-28.json` (40 positions, 370 centres, [row,col], native 250 px), cube streamed under the 2.5 GB footprint guard.
Split by position index: even 20 = selection, odd 20 = confirmation (the rule is chosen on the first, judged on the second and pooled).
Collateral (would any rule touch it): the five pinned cubes (Particle_1, downsample_Si_SiGe, polycrystal_2D_WS2, sim_Au, bullseye; `tools/real-data-acceptance/run.sh`,
S19 pins positions), the unpinned Al_Mg_Si (two files), Au_ref_ROI15, Si-SiGe_calibrated, Thronsen `datasetA_stride3.h5` (ADR 041's floor lives there), the demo cube.

## Statistic
Greedy one-to-one nearest matching within 2 px (3 px reported): recall = matched/370, precision = matched/predicted, per position and pooled; peaks per position; fraction of positions where the beam is the brightest peak.
Validity controls (a result is void without them): the central-beam label matches at 40/40 positions; swapping row/col drops recall (null); B_flat reproduces `bullseye-parity-probe.swift`'s
peak list within 0.05 px at the same settings; each measured detector count equals a second independent run.
Distribution of the gate quantity on every dataset above: R_out (20 % outer edge of the azimuthal profile of the app's own probe-size input) and interior-dip depth D (min of the profile inside R_out / its max).

## Grid (closed, nothing added after seeing results)
spacing {7, 11 = R_out, 22} × minRel {0.0015, 0.005, 0.01, 0.02, 0.05} × relativeToPeak {0, 1}; sigmaCC {1, 2, 3} and corrPower {1, 0.9} one at a time at baseline;
B_syn's kernel radius {6.84, 11}. Selection rule on the even half: max precision with recall >= baseline recall − 0.02.

## Predictions
- **P0** Baseline noise is the cap: B_flat returns 70 peaks at >= 90 % of positions (A2's classical at 0.0015 did at spacing 8/edge 6), precision <= 0.15, recall 0.55–0.80.
  Refuted if baseline precision >= 0.30 (then the premise "accepts noise" is wrong at these settings).
- **P1** Spacing 7 → 11 or 22 alone: precision +< 0.05, recall −0.03..0 (the extra peaks are not duplicates of one disk).
- **P2** The floor is the lever and it trades: precision rises monotonically, recall falls (A2's py4DSTEM curve, 2 px: 0.005 → 0.081 precision / 0.611 recall; 0.05 → 0.436 / 0.362).
  No single scalar meets the bar: precision +0.10 costs > 0.05 recall on the confirmation half.
- **P3** B_syn with kernel radius 11 (the true outer edge; py4DSTEM measured, `bullseye-kernel-truth.py`) raises the beam-brightest fraction from about 41 % to > 90 % and recall by >= 0.10 over B_syn; this is the one lever expected to help.
- **P4** The gate quantity separates: D < 0.25 on the bullseye probe only; every other dataset's D >= 0.5 (flat-topped disks), so a structured-probe rule fires nowhere else.

## Bar to propose (all four, on the confirmation half and pooled)
1. Precision up by >= 0.10 at recall no worse than −0.02, against the flow the rule changes (B_syn or B_flat), 2 px.
2. The rule is a probe-structure gate, not a global default: D-gate fires on none of the other datasets (or each firing is listed with its moves).
3. `tools/real-data-acceptance/run.sh` exits 0 on a scratch copy with the patch — zero change in counts and peak positions on the five pinned cubes — and Thronsen A / demo label maps byte-identical (no default moves there).
4. Every validity control above passed. Failing any: no patch, the result is the measured curve (the quantity shipped, the reader judges).

## What refutes the whole idea
Precision gain < 0.10 for every grid point at recall −0.02 (I expect this for the scalar levers, P2); D >= 0.25 on a non-bullseye probe input; the winner not holding on the odd half; a gain that vanishes at 3 px or under
row/col swap. No mechanism is inferred from a null: a failed lever says only that it did not help on these 40 positions and this label set (label scatter 1.2 px, single labeller).
Overall prediction: bar NOT met for scalar levers (~70 %); met, if at all, only by P3's B_syn kernel radius.

## Amendments (2026-09-30, after GO, before any measurement was read)
- **A1 (definition of D).** "min of the profile inside R_out / its max" is wrong for a smooth flat-topped disk: its own edge bins sit between 0.2 and 0.5 of the max, so D would be < 0.25 on every probe and P4 would fail by construction.
  D is now: min of the integer-radius azimuthal profile over radii 1..r_ring−1 divided by its max, where r_ring is the LARGEST radius at which the profile has a local maximum >= 20 % of the max; D = 1 when r_ring <= 1 (no ring). Profile centre = the `probeSize` centre on the same input. P4's number (< 0.25 bullseye only, >= 0.5 elsewhere) is unchanged.
- **A2 (parity control).** B_flat is compared with `bullseye-parity-probe.swift` run unchanged at its own settings (spacing 8, edge 6, minRel 0.05, origin 125,125) on its 90 strided positions, against the same harness at those settings; the control is the peak lists agreeing within 0.05 px.
- **A3 (build).** All scratch builds use a `git archive HEAD` snapshot under `$SP/s21/repo` (HEAD 04d2560), because the working tree carries other agents' uncommitted edits.
- **A1b.** In A1, r_ring is searched only at radii <= 2 x r_est (the trench's own outer radius), so a Bragg ring in a mean pattern is not read as probe structure. The unrestricted D is reported beside it; the restricted one is the gate quantity. Decided before the profile or the grid was run.
