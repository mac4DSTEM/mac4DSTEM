# Q1b predictions, written 2026-10-01 BEFORE any probe run
"Healthy" = the first (lowest-|g|) allowed ring of the crystal is physically the app's reference ring and the
cube is not an [001]/[011] fcc majority: polycrystal/nanocrystal Au or Ni-Cu (no zone majority), Si on [110] (diamond: (200) forbidden,
so first ring is (111), no alias possible). Truth Q = a file pixel size, in A^-1/px.
1. Si-SiGe_calibrated.h5 (Si diamond a=5.4309, [110]-type cross-section; file Q 0.0062085 A^-1/px = 0.062085 nm^-1, py4DSTEM-calibrated).
   Predict: Q err within +-3 % (SiGe layers shift rings <= ~2 %, file Q itself carries its own error), shell ratio (220/111) 1.633 within 3 %.
2. Au_ref_ROI15 (Au fcc a=4.0782, nano/polycrystal reference, file Q 0.045741 A^-1/px, 64x64 detector, (111)=9.3 px).
   Predict: |Q err| <= 5 %, ratio 1.1547 within 5 %; if it fails it is the ringed probe/origin (window 5.3 px recorded), not an alias.
3. COPL NiCu (fcc, a=3.556 Vegard Ni65Cu35, file Q 0.15683 A^-1/px, 32x32 detector: (111)=3.1 px, (200)=3.6 px, only 0.5 px apart).
   Predict: resolution-limited; Q err anywhere in -10..+5 %, shell ratio unreliable (cluster band 7.7 % ~ the (111)/(200) gap).
   A failure here is a NEW mode (detector sampling), not alias.
4. sim_Au (training_dataset, Au, truth 0.019827 which is itself +2.4 % biased): repeat of the recorded healthy case.
   Predict Q err -2.7 %, ratio 1.1265 (bit-reproducible against slot1 record).
py4DSTEM comparison: py4DSTEM Crystal.calibrate_pixel_size on the SAME app peaks (identity calibration, nominal pixel size = file Q x 1.0,
which equals truth by construction, so start offset 0): predict it returns scale ~1.00 +-2 % on 1, 2, 4; on 3 unknown (1-bin combs).

# Q1b — known-crystal Q on healthy cubes (2026-10-01, read-only; nothing in the repo touched)
Predictions (written before any run): $LD/predictions.md. Logs: logs/probe-{si,auref,nicu,simau}.log/.err (first run),
logs/probe2-*.log (re-run with --dump-peaks, bit-identical RESULT lines), logs/py4dstem.log (py4DSTEM 0.14.19 vendored, py4dstem env),
scripts: probe/ (copy of tools/q-shell-probe + `--crystal si|nicu` + `--dump-peaks`; repo copy untouched), py4d.py, meta.py.
No xcodebuild, no app launch, heavy lock not taken (swiftc only). Probe build reused from build/.

## Why each counts as healthy (stated before measuring)
- Si-SiGe_calibrated: Si diamond, [110]-type cross-section; (200) is forbidden so the first ring is (111) and the [001]/[011] fcc alias cannot occur. Truth = file Q 0.0062085 A^-1/px (py4DSTEM-calibrated by the data's author; SiGe layers can shift rings ~2 %).
- Au_ref_ROI15: Au reference film (nano/polycrystalline, no zone majority), file Q 0.045741 A^-1/px.
- sim_Au: simulated poly-Au, truth 0.019827 (the 2026-09-01 app value, itself ~+2.4 % biased); the recorded healthy case, repeated.
- NiCu_COPL (Ni65Cu35, fcc a=3.556 Vegard, polycrystal, file Q 0.15683): chosen as healthy, but see below — its truth did not survive.

## Table (app = Core KnownCrystalQCalibration via the probe, plane origin fit + detectorAdapted detection; py4DSTEM = Crystal.calibrate_pixel_size on the SAME app peaks, start = file Q x1.0, default broadening)
| cube | crystal | zone / innermost ring at truth Q | truth Q (A^-1/px) | app Q err % | py4DSTEM Q err % (start x1.00; x0.95/1.05/0.90/1.10) | shell ratio obs/exp (apart %) |
|---|---|---|---|---|---|---|
| Si-SiGe_calibrated | Si | [110]-type, (111) 100 % | 0.0062085 | +1.36 | +1.40 (-12.48 / +1.36 / -12.53 / +94.15) | 1.6615 / 1.6330 (1.74) |
| Au_ref_ROI15 | Au | poly, (111) 54 % / (200) 28 % | 0.045741 | -4.41 | -5.30 (-6.14 / -2.12 / -9.08 / -7.24) | 1.2773 / 1.1547 (10.62) |
| sim_Au | Au | poly, (111) 96 % / (200) 4 % | 0.019827 | -2.72 | -1.12 (-1.17 / -1.18 / -1.09 / -1.17) | 1.1265 / 1.1547 (2.44) |
| NiCu_COPL (not counted) | Ni-Cu fcc | (5 3 1) 58 % at file Q = file Q unusable | 0.156828 | -71.97 | +14519 (all starts +14500..17300) | 1.0867 / 1.1547 (5.89) |
Reference rows already on record (slot1 record, same estimator): Al [001] majority demo -13.45, Thronsen A -13.22, owner raw 060 -12.70, binned 060 -12.52, ratio apart 18-24 %; WS2 -55.46 (13.34 %, (0002) reference, other class).
So three counted healthy cubes (n = 3, one a repeat) plus one cube that could not be used.

## Predictions vs result
Held: Si (Q within 3 %, ratio within 3 %), sim_Au (bit-reproduced -2.72 / 1.1265), Au_ref Q within 5 % (-4.41). Missed: Au_ref shell ratio (predicted <= 5 % apart, got 10.62 %); py4DSTEM from a start AT file Q predicted ~0 +-2 %, got -5.30 % on Au_ref (Si +1.40, sim_Au -1.12 held); NiCu Q prediction (-10..+5) missed by 60 points because the file Q does not fit the cube.

## One paragraph: is the [001]/[011] alias the only failure mode seen?
No. In this set the alias itself did not occur (no [001]/[011] fcc majority among the counted cubes; innermost ring was (111) on 54-100 % of positions and the app's estimate sat 1.4-4.4 % from the file Q). Failures of other kinds: (1) Au_ref_ROI15, a healthy-by-construction poly-Au film on a 64x64 detector with an 8 px probe radius (ring 9.7 px, 1.0 equivalent per position, MAD 1.46 px), reads the (200) ring as innermost on 28 % of positions and its shell ratio is 10.6 % apart from 1.1547 with Q only -4.4 % off; that single healthy-side value sits above the 6.7 % (M/2) and 8.1 % (2H) lines the 2026-09-30 record considered, so the "disagrees" line's healthy side is no longer n = 1 at 2.4 % - it is {1.7, 2.4, 10.6} here - and the cause (detector sampling / probe-disk overlap, or a file Q error) is not diagnosed. (2) NiCu_COPL: 32x32 detector, probe radius 0.62 px, 2 peaks per position; the app reads 0.0440 and the file says 0.1568 (3.57x apart); no ring of the crystal lands near the observed radii at the file Q ((5 3 1) at best), and py4DSTEM diverges from that start; whether the file's Q is wrong (DM metadata of a binned cube), the crystal is not fcc Ni-Cu, or the app mis-assigns is not decided - not a usable truth, not counted. (3) py4DSTEM itself has a basin failure on the healthy Si cube: -12.5 % from a 5 % low start (and +94 % from a 10 % high start), i.e. the comb fit is also alias-prone off [001] Al; on Au_ref it sits -5.3 % from a start at truth; only sim_Au is flat (-1.1 % at every start). Distribution only; no threshold proposed. Caveats: n counted = 3 (sim_Au is a repeat); truth Q for the two real cubes is a file pixel size, itself unverified; py4DSTEM k_max 1.0-1.2 A^-1 (not the app's 2.5), peaks strided to <= 6000 positions.
