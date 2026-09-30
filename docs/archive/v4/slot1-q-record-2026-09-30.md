# Slot 1 lane Q — science quick wins: the record (2026-09-30 night)

The implementer's report of record (Sonnet 5.5; its own report write was refused by the harness, so the supervisor saved the handback), then the independent refuter's verdict (Fable 5.1, read-only) is `slot1-q-refuter-2026-09-30.md`. Corrections the refuter required were applied before landing: the window-sensitivity read takes the caller's window scale and bounds its sample by bytes (a broken-first test); no surfacing line ships until the demo fixture's 3.36 px (S14-D, table row 50) is measured; the conclusion "the demo cube is not truth-bearing for ACOM" is withdrawn — grain B's 6.50° is invariant under Q, kMax and candidate F, so it is matcher/plan-side, undiagnosed, its own Gate D; the caveat is lost on rewind, sidecar restore and re-reference (documented, not persisted); ADR 050's "disagrees" half did NOT ship — on the owner's cube the Q row reads "Measured" with the ratio shown beside it. Logs named here lived in the session scratchpad and are not retained.


## Summary
1. (a) The owner's Al–Mg–Si cube is MIS-ASSIGNED on the app's own path: raw 060 stride-3 reads ratio 1.367 (1.428 with his ellipse) vs 1.155; Q −12.7 / −12.6 %. Demo 1.4129 (Q −13.45 %); Thronsen A 1.4146 (−13.22 %). Mechanism: the Al [001] majority has no {111}, so the (200) ring is taken as (111).
2. Predictions held: Al rings ((200) at 0.06–1 % of truth Q), demo, Thronsen, r1 px. Missed (marginal): raw/binned 060 ratios 1.367/1.374 (predicted ~1.38–1.45). Wrong: sim_Au 1.1265 (2.44 % apart), not 1.148. Wrong: WS₂ is not a healthy control — its reference is (0002), second shell (0004) (expected 2.000); Q −55.5 %, 13.3 % apart.
3. Badge: `.notSelfChecked` reads "Shell ratio unchecked — <reason>" on the Q readiness row (still `.ready(.measuredInApp)`) and Prepare's "Q shell check" row. Threshold-free; ships.
4. No "disagrees" line ships: H = 4.07 % (healthy, incl. the recorded 1-px sim_Au case), M = 13.34 % (WS₂) → 2H 8.14 % ≥ M/2 6.67 %: the pre-registered rule fails. The mismatch number stays visible. Decision card below.
5. (b) The demo cube is NOT truth-bearing for ACOM even at true Q: base at Q 0.012 gives B 6.50° at both kMax, A 5.03° at kMax 1.2 (0.00° at 0.9). F at true Q: C stays t2 (0.00°) → the S20 regression was the probe's Q, not F (prediction held). F moves A 5.03° → 3.18° at kMax 1.2. Cost: F 3.8× slower CPU (0.25 → 0.95 s per 10 000 positions). F stays After v4.1.
6. (c) `OriginCalibration.tiledRun` returns `windowSensitivityPixels`: compact cubes 0.000–0.066 px, Particle_1 0.34 px, bullseye 3.82, Au_ref 5.31 px. Cost < 0.06 s everywhere except the gzip row-chunked demo cube: 0.84 s (I/O).
7. (d) Gate D diagnosis written (below); nothing implemented.
8. Not done: the 2026-09-29 "0.006577 / 1.0846" row does not test this estimator (Diagnosis).
9. Tests: 7 badge + 4 window tests; 5 mutation runs each red on exactly the predicted tests; final 30/0.

## Diagnosis
- The 09-29 "Q 0.006577, ratio 1.0846, [001] 92.9 %" row came from `tools/lattice-calibration-probe` (Python lattice_fit.py on dumped peaks; `almgsi-raw-stride3-registration-2026-09-29.md`); "1.0846" is the ELLIPSE axis ratio (19.50/17.97 binned; 78.2/72.1 px raw), not a shell ratio — silent on this estimator.
- `References/thronsen-datasetA/datasetA_stride3.h5` is Thronsen's dataset A (171², 128², Q 0.01904), not the owner's cube. The owner's raw cube: `/Volumes/PL_SSD_2TB/NAS_Backup/00_inbox/4DSTEM_170330/ROI_5/mac4dstem_subsampled/060_STEM_SI_stride3.h5` (110×110×256², 3.2 GB), measured read-only with `--tile-rows 12`; also his binned 060 cube (64²).
- sim_Au and WS₂ files carry Q = 1 "pixels": references used — sim_Au 0.019827 (the app's 2026-09-01 value, itself ≈ +2.4 % biased); WS₂ 0.019448 (the independent (11-20) shell, W4b).
- Mechanism of the −13 %: estimator bias REFUTED (sim_Au, same estimator, four equivalents/position, reads −2.7 %); origin error REFUTED (demo origin (63.50, 63.50), MAD 0.65 px vs 41 px); wrong truth Q REFUTED (r1 × truth Q lands on the (200) |g|: demo +0.06 %, Thronsen −0.2 %, raw −0.8 % (−0.9 % ellipse), binned −1.0 %). SURVIVES: ring mis-assignment — Q error pinned at 1 − √3/2 = 13.4 % (−13.45, −13.22, −12.70, −12.52). Demo per grain: A→(200) 100 %, B→(111), C→(220); the median lands on the majority grain (A = 53.5 % of non-vacuum positions). His cube: (200) at 70–72 % of positions; the other 28–30 % sit nearer the (111) radius at truth Q — unresolved (ellipse smear or precipitate reflections).

## Predictions, as recorded
(a) stated in the transcript before the probe was built (~22:12). (b) stated before the first S20 run (logs 22:30:57 onward). (c) real-data numbers and the mutation expectations: reasoned in working notes before each run but NOT posted as visible text — flagged.

## Changes
- `Core/Analysis/QCalibration.swift`: `uncheckedNote` on `QCalibrationShellCheck` ("Shell ratio unchecked — <reason>"), threshold-free; the one-shell reason shortened to "only one shell is detectable"; note (5) in the thresholds-history block records the 2026-09-30 measurements and the failed rule.
- `Session/QCalibrationRun.swift`: `selfCheckSummary` uses `uncheckedNote`; a measured ratio keeps its text.
- `Core/Data/Calibration.swift`: new `CalibrationProvenance.qShellCaveat` (beside `rotationImportNote`); the Q row detail appends the caveat only while `qScale == .measuredInApp` and the pixel size equals the one the caveat was made for (a typed/restored/rewound scale never carries another value's caveat). Beyond "only the .qScale item" because the readiness report takes only Calibration + CalibrationProvenance.
- `App/AppState+ACOM.swift`: sets the caveat from `estimate.shellCheck.uncheckedNote`; status says "shell ratio unchecked".
- `Core/Analysis/OriginCalibration.swift`: `windowSensitivityPixels(data:descriptor:probeRadius:)` — strided sample ≤ 200 positions, the same GPU kernel at k 1.2 and 2.5, median distance; `windowSensitivitySampleIndices`, constants, a fifth labelled `tiledRun` tuple element `windowSensitivityPixels: Float?` (callers use labels). Centre-of-mass only (nil for Friedel); errors leave it nil.
- `tools/q-shell-probe/` (run.sh, main.swift) + `q-shell-probe` in the `diagnostic` array of `tools/run-tests.sh`.
- `UI/PrepareSettings.swift` NOT edited (the row already renders `selfCheckSummary`). UI cost: one detail line (~28 pt) when unchecked; 0 rows otherwise.

## Tests (new: QCalibrationShellBadgeTests ×7, OriginWindowSensitivityTests ×4)
| run | mutation | expected red — got (exit 65) |
|---|---|---|
| A | uncheckedNote returns a note when mismatch > 0.1 | testAMeasuredShellCheckIsNeverWordedUnchecked, testAMeasuredRatioThatDisagreesByFarCarriesNoCaveat |
| A | drop the .measuredInApp guard in the Q row | testTheCaveatNeverDescribesAnotherValue |
| A | selfCheckSummary back to "Not self-checked" | testThePrepareLine… |
| B | drop the pixel-size equality | testTheCaveatNeverDescribesAnotherValue |
| B | remove the AppState+ACOM assignment | testACrystalWithOneShellLeavesAnUncheckedCaveatOnTheQRow |
| C | delete `qDetail += …` | testTheQRowStaysReadyAndNamesWhatWasNotChecked, testACrystalWithOneShell… |
| D | return 0 | testARingedProbeMovesWithTheWindow, testTiledRunReportsTheSameQuantity |
| D | floor the sample step | testTheSampleIsStridedAndNeverExceedsTheLimit |
| E | tiledRun reports nil | testTiledRunReportsTheSameQuantity |
| E | return 5 | testACompactProbeDoesNotCareWhichWindowItGets |
Reverts byte-backed and cmp-verified inside the lock (mut-runA..E.log/.err). Green before (test-1, 30/30) and after (test-final, 30/0: OriginWindowSensitivityTests 4, ProbeSizeTests 12, QCalibrationOriginGateTests 7, QCalibrationShellBadgeTests 7). Fixture values (xcresult activities): compact probe radius 2.922 px → 0.0087 px; ringed radius 6.492 px → 3.8788 px.

## Runs
Build EXIT=0, 0 warnings (build-1.log/.err); core EXIT=0 (core-2.log); inventory EXIT=0 (inventory-2.log). Probe: q-shell-probe/run.sh → probe-*.log, probe-results.tsv, win-*.log, win2-*.log. S20 harness: $SP/Q/s20/ (base = git archive HEAD at 02174c9c; patched = the F patch applied with --include='mac4DSTEM/*', `git apply --check` clean).

## Measurements
### (a) app path per dataset (probe-*.log)
| dataset | truth Q | r1 px | r2 px | obs/exp ratio | positions w/ r2 | Q est | Q vs truth | apart | innermost at truth Q |
|---|---|---|---|---|---|---|---|---|---|
| demo cube | 0.012 | 41.18 | 58.19 | 1.4129 / 1.1547 | 7650 | 0.010386 | −13.45 % | 22.36 % | (200) 52 % |
| Thronsen A | 0.01904 | 25.89 | 36.62 | 1.4146 / 1.1547 | 29241 | 0.016523 | −13.22 % | 22.51 % | (200) 82 % |
| owner raw 060 | 0.006577 | 74.50 | 101.84 | 1.3671 / 1.1547 | 12100 | 0.005741 | −12.70 % | 18.39 % | (200) 70 % |
| same, ellipse 78.2/72.1/20.8° | 0.006850 | 71.43 | 102.00 | 1.4281 / 1.1547 | 12100 | 0.005988 | −12.58 % | 23.68 % | (200) 72 % |
| owner binned 060 | 0.02639 | 18.53 | 25.45 | 1.3737 / 1.1547 | 108900 | 0.023086 | −12.52 % | 18.96 % | (200) 84 % |
| sim_Au | 0.019827 (2026-09-01) | 22.02 | 24.81 | 1.1265 / 1.1547 | 4436 | 0.019287 | −2.72 % | 2.44 % | (111) 96 % |
| WS₂ | 0.019448 | 18.74 | 32.48 | 1.7333 / 2.0000 | 12647 | 0.008661 | −55.46 % | 13.34 % | (10-10) 87 % |
H = 4.07 % (incl. the recorded 1-px sim_Au case; measured healthy max 2.44 %), M = 13.34 % (WS₂): 2H 8.14 % vs M/2 6.67 % — not met.
### (b) demo cube, CPU matching, full scan (s20-*.log; zone-axis error reduced into the cubic fundamental zone)
| run | A | B | C |
|---|---|---|---|
| base, calibrated Q 0.010386, kMax 1.2 | 5.027° (t165) | 6.499° (t84) | 0.000° (t2) |
| patched, calibrated Q, kMax 1.2 | 5.027° | 6.499° | 1.637° (t198) |
| base, Q 0.012, kMax 1.2 | 5.027° | 6.499° | 0.000° (t2) |
| base, Q 0.012, kMax 0.9 | 0.000° (t0) | 6.499° | 0.000° (t2) |
| patched, Q 0.012, kMax 1.2 | 3.176° (t173) | 6.499° | 0.000° (t2) |
| patched, Q 0.012, kMax 0.9 | 0.000° | 6.499° | 0.000° |
Reproduction: rows 1–2 match the S20 record (A 5.03, B 6.50, C 0.00 → 1.64). Verdict: the "all ≤ 0.5° at true Q" prediction was WRONG — B is stuck at 6.50° (winner t84, axis (0.702 0.113 0.703)) in base and patched at both kMax (looks like the "zone axis beyond the bank's sampling" item; not diagnosed). The demo cube is not truth-bearing for ACOM. F's grain-C regression was the probe's Q; F stays After v4.1 on cost.
### (c) window sensitivity, median px between k 1.2 and 2.5 (win*.log)
WS₂ 0.0000 · demo 0.0007 · sim_Au 0.0034 · Si-SiGe_calibrated 0.0190 · owner binned 060 0.0194 · Thronsen A 0.0219 · owner raw 060 0.0664 · Particle_1 0.3384 · bullseye (polyAu) 3.8230 · Au_ref 5.3065; fixtures compact 0.0087, ringed 3.8788. Predictions held for compact cubes (8 of 9 ≤ 0.05; all ≤ 0.07), bullseye and Particle_1; missed on raw 060 (0.066 vs ≤ 0.05) and Au_ref (5.3 vs 2–3). Cost 0.004–0.053 s except the gzip row-chunked demo cube 0.84 s (I/O; 38 % of its 2.21 s tiledRun). Other tiledRun: Thronsen A 4.41 s, bullseye 1.48 s, raw 060 0.63 s.

## Decision card — the Q "disagrees" badge
Problem: the Q row says "Measured" on his Al–Mg–Si cubes while the scale is 12.6–13.4 % low ((200) read as (111)); the shell ratio already shows it (18–24 % apart) in Prepare and the status line; nothing on the Q row says so. Distribution (% apart): healthy sim_Au 2.4 (recorded 4.07 at 1 px displacement); mis-assigned WS₂ 13.3, raw 060 18.4 (23.7 with ellipse), binned 060 19.0, demo 22.4, Thronsen A 22.5.
| option | effort | risk |
|---|---|---|
| A. Ship nothing more (current) | 0 | his cube still reads "Measured" |
| B. Flag at 8.1 % (= 2H); the path exists (`uncheckedNote` returns the ratio text above the line) + 3 tests | ~1 h | catches all 6 mis-assigned cubes, healthy 3.3× lower; but the healthy side is n = 1 + one recorded perturbation and the decided margin rule failed (8.14 > 6.67) |
| C. Flag at M/2 = 6.7 % | ~1 h | same thin healthy side; 1.6× above the recorded 4.07 % |
| D. Fix the assignment (Gate D below) | ~1 day + Gate B | re-pins ~8 harnesses; the healthy cube's best and runner-up pairs differ by only 1.5 points |
Recommendation (implementer): A now; then measure ≥ 3 healthy cubes (Si, Cu/Ni, Mg, real zone axes) and place the line by the rule.

## (d) Gate D diagnosis: ring-sequence assignment (nothing implemented)
Candidate: match observed r2/r1 (and r3) to the crystal's distinct-shell ratios g_j/g_i within the first N shells; Q = mean(g_i/r1, g_j/r2). Offline from the measured r1, r2:
| dataset | best pair (ratio error) | Q vs truth |
|---|---|---|
| demo | (200,220) 0.09 % | −13.45 → −0.01 % |
| Thronsen A | (200,220) 0.02 % | −13.22 → +0.19 % |
| raw 060 | (200,220) 3.33 % | −12.70 → +2.54 % (r1-only +0.80 %) |
| raw 060, ellipse | (200,220) 0.98 % | −12.58 → +0.45 % |
| binned 060 | (200,220) 2.87 % | −12.52 → +2.51 % (r1-only +1.01 %) |
| sim_Au | (111,200) 2.44 %, runner-up 3.93 % | −2.72 → −1.50 % |
| WS₂ | none within 13 % at N ≤ 5; (10-10, 11-20) 0.07 % at N ≥ 11 | unchanged at small N; +0.45 % at N ≥ 11 |
Refuting observations: fcc self-similarity — (200):(220) = (220):(400) = √2; at N = 6 Thronsen A and raw+ellipse flip to +41.7 / +42.1 % wrong → N is a design constant (4–5 works) and r3 or an intensity rank is needed: a threshold-class choice. Healthy margin: sim_Au's pair wins by 1.5 points → needs a tolerance line; the separation problem moves inside the fix. WS₂: works only by coincidence at N ≥ 11; the real defect is the missing (00l) visibility filter (the existing "no l-filter" item).
Harnesses it would re-pin: QCalibrationOriginGateTests (0.024472 pin, ≥ 1.15× ratio pin), QCalibrationShellBadgeTests, tools/q-calibration-gate-test, tools/strain-test, tools/acom-matching-test, tools/real-acom-benchmark, tools/training-dataset-campaign, tools/origin-fit-diagnostics/shell-check.swift, docs/q-calibration-design.md §3.2.

## Proposed surfacing line (supervisor's; AppState+Calibration.swift after the "Origin ✓ …" status)
`if let s = result.windowSensitivityPixels, s >= 1 { statusText += String(format: " · origin moves %.1f px with the refine window (k 1.2 → 2.5)", s) }` — 1 px is a display choice between the compact maximum 0.07 (Particle_1 0.34 stays silent) and the ringed 3.8.

## Open questions
1. Option on the card; the independent second opinion. 2. `qShellCaveat` beyond the .qScale item — acceptable? 3. Should the demo cube stop being the ACOM truth set (B 6.50° at true Q); own Gate D for A/B? 4. 0.84 s on gzip row-chunked files: strided or row-tile sample? 5. The 28–30 % near-(111) positions on his raw cube: unresolved.

## git status (Q's files)
M App/AppState+ACOM.swift · Core/Analysis/OriginCalibration.swift · Core/Analysis/QCalibration.swift · Core/Data/Calibration.swift · Session/QCalibrationRun.swift · tools/run-tests.sh; ?? mac4DSTEMTests/OriginWindowSensitivityTests.swift, mac4DSTEMTests/QCalibrationShellBadgeTests.swift, tools/q-shell-probe/
