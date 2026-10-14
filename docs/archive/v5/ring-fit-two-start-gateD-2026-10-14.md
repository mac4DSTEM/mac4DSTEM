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
