# The ring fit on the owner's data, then two starts and a seed check — Gate D (2026-10-14)

ADR 068 (card M2, the owner's **d**): the step-2 item `ring-sigma-start-gateD-2026-10-13.md` closed as not met; this is
the new item. Tier 1 (a number a scientist reads can move: the b/a and θ the app applies to every Bragg vector). Step (i)
measures the owner's data first; step (ii), the registration of the new candidates, is written after (i) and before any
run of them. Nothing lands from this record without its gate.

## Step (i) — the owner's cubes, measured before the registration (plan and predictions, before any fit)

**Sources** (decided by the session, overrule on sight; the owner, 2026-10-14: decide in the app's interest). The app's
Fit runs on the Bragg-vector map in Disks mode (raw peak intensities collapsed onto the mean origin, no ellipse,
`AppState+Calibration.swift:144-162`, built by `DiskDetection.swift:711` `calibrated` and `:746` `map(qy:qx:)`) and on
the mean diffraction pattern otherwise; the centre guess is the aperture centre.
- **S1** Al-Mg-Si 060 (`References/training_dataset/Al_Mg_Si_060_…_20260712.h5`, 330 × 330 × 64 × 64), mean pattern.
- **S2** the same cube's Bragg-vector map from the owner's saved vectors (its `.mac4dstem.h5` sidecar: `_v_uncal`, the
  `qx0`/`qy0` origin maps), built the app's way.
- **S3** `polycrystal_2D_WS2.h5` (128 × 128 × 128 × 128; py4DSTEM's ellipse/strain tutorial data), mean pattern.
- **S4** the same cube's Bragg-vector map from py4DSTEM's own detection with its tutorial's parameters
  (`orient_strain_01_WS2.ipynb`, the vendored py4DSTEM), mapped the app's way. These peaks are py4DSTEM's, not the app's.
- **S5** Ni65Cu35 ROI6 (`website/datacube/COPL_Ni65Cu35_…_20240912.h5`, 200 × 200 × 32 × 32), mean pattern only (a 32 px
  detector).
- Carried: Au_ref's mean pattern, step 2 lane P5 (8 annuli).

**Method.** Each source's centre guess is what the app would use (the mean pattern: the centroid of its brightest 1 % of
pixels, as P5; the map: the mean origin). Its annuli are read off its radial profile about that guess — one per ring, the
ring's peak ± half the distance to the neighbouring minimum, plus each widened by 2 px — and written to
`ring-fit-two-start-gateD-2026-10-14/annuli/` **before any fit**. The fit harness (`…/harness/main.swift`, checked to
reproduce lane P5's Au_ref lines digit for digit) runs the conic seed and the default-argument `fitBestAvailable` under
HEAD, (a), (b) and (ab) (the held step-2 diffs).

**Measured per annulus:** model; a, b, b/a, θ, centre; residual; profile parameters; flags (I1 = 0, a ring σ at its 0.25 px
floor or its 2 × outer ceiling, I0 at its limit, a profile ring outside its annulus); the seed's mean radius and b/a, and
|R_profile / R_seed − 1|; which of HEAD's and (a)'s profile fits costs less; the background under the ring (the fitted
central term and constant at the ring radius, relative to I1) and the noise (residual relative to I1). Truth-free check: the
detector's distortion is common to every ring, so b/a and θ should agree across a source's annuli and between a cube's mean
pattern and its map.

**Predictions** (a measurement to inform the registration; a failed prediction is recorded, not amended):
- Pi1: the mean patterns (S1, S3, S5) are tailed (the central term at the ring ≥ 0.4 × I1 on most annuli) and nearly
  noise-free (residual ≤ 0.05 × I1); there (a)'s estimator returns nil on most annuli and (a) equals HEAD, as on Au_ref.
- Pi2: the maps (S2, S4) have a flat background and spotty rings; on each, HEAD returns at least one flagged fit, (b)
  refuses at least one, and HEAD and (a) differ on at least one annulus.
- Pi3: across a source's annuli, HEAD's b/a spreads by more than 0.01 when a flagged fit is included and by at most 0.01
  among unflagged fits; (a)'s and (b)'s spreads are no larger than HEAD's.

## Step (i) — results (2026-10-14; `ring-fit-two-start-gateD-2026-10-14/step-i/`, logs `runs/<source>-<variant>.log`, `analysis-i.txt`)

Sources and annuli were committed before any fit (`2dd58796`). The harness's conic seed was first run at fit1D's default
residual cap; it now uses `fitBestAvailable`'s own seed cap (0.4), and every fit field is unchanged by that (compared line
by line). "Flagged" = I1 = 0, a ring σ at its floor or ceiling, the central σ at its floor, or the ring outside its annulus.

- **Al-Mg-Si 060, mean (S1) and saved-vector map (S2): the Fit refuses every annulus** (2 + 8), `insufficientAngularCoverage`
  with 2–11 of 36 bins (bound 30, sparse floor 12), before any ring model runs. The rings are 2–4 zone-axis spots; neither
  the defect nor any candidate is reachable on this cube with the default Fit.
- **WS2 mean (S3):** 6 profile fits, 4 `insufficientSignal` (the outer rings). No flags; b/a 0.9979–0.9998 (spread 0.0019).
  (a) differs on 3 annuli by ≤ 0.13 px in R and ≤ 4e-4 in b/a; (b) = HEAD. The background is flat (a ~5e-9 floor beyond a
  2.75 px central beam), not tailed.
- **WS2 map (S4, py4DSTEM's peaks):** 10 profile fits, b/a 0.9933–0.9995 (spread 0.0062; 0.0045 unflagged). Flags: a ring σ
  at its ceiling on the two narrow annuli R1, R2 and the central σ at its floor on R5 — none a b/a outlier. (b) refuses
  nothing; (a) differs on R3w (R +0.82 px, ending with a σ at its ceiling, b/a 0.9976 → 0.9993).
- **Ni65Cu35 mean (S5):** 2 profile fits of 6 annuli (4 refused: coverage or residual). **R3 is a dead ring on HEAD** (I1 = 0,
  a σ at the floor) with b/a 0.947 against the conic's 0.989; (b) refuses it to the conic; (a) = HEAD; its seed move is only
  3.6 %, under the seed check's 8 %. R3w: an unflagged profile fit, b/a 0.970.
- **Au_ref (carried):** A4 a dead ring (seed move 13.4 %; (b) refuses it), W4 a ring outside its annulus with a σ at its
  ceiling (seed move 71.7 %; only the seed check would refuse it), W3 a σ at its ceiling (seed move 1.9 %; b/a 0.9824, in
  line with the other annuli), A2 the central σ at its floor. (a) = HEAD on every annulus.
- **Predictions:** Pi1 not held — S3 is flat, not tailed, and (a) moved 3 of its 6 fits slightly; S1 was not exercised
  (refused); S5 and Au_ref held ((a) = HEAD). Pi2 partly — S2 not exercised; on S4 flagged fits exist and (a) differs from
  HEAD on one annulus, but (b) refuses none. Pi3 not held as stated — on Au_ref HEAD's unflagged fits still spread 0.0134
  in b/a, and on S4 the flagged fits are not b/a outliers.

**What this means for the registration.** On the owner's data the failure that appears is not the noisy-ring drift of the
synthetic sets but the dead ring (Au_ref A4, Ni65Cu35 R3; the floor guard catches both) and a ring fitted outside its
annulus (Au_ref W4; only the seed check catches it). The two-start fit changed nothing on these sources beyond sub-pixel
moves and S4 R3w. Real patterns therefore stay in step (ii)'s sets as the cases that decide whether a guard refuses right
fits; the noisy synthetic sets decide the two-start fit.
