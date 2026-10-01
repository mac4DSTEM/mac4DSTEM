# Lane SB report (2026-10-01)
## Predictions
Brief predictions P1-P5 (BRIEF.md, unedited) stand. Design decision (2026-10-01, before any run): templates and experiment are
distinguishable at the call sites (plan.generate vs the two matcher sites), so buildPolar gets `exactAzimuth: Bool = false`:
false (templates) = linear interpolation between floor/floor+1 then the existing blur; true (experiment, 2 matcher sites + the
acom-matching-test scalar reference) = azimuthal Gaussian at the exact azimuth, sigma = azimBlurBins, normalised to the spot weight, no post-blur.
Extra predictions: on-grid experiment spots give the same taps as blur (differences ~1e-7); buildPolar time <= 1.5x.
(2026-10-01, before first unit run) New class ACOMSubBinAzimuthDepositionTests (4 tests) predicted GREEN on the fix, RED on a revert to
nearest-bin for testTemplateDeposition..., testExperimentDeposition..., testDepositionWraps...; testOnGrid... stays green on revert (by design).
Overlay mirrored fix: no automated test (needs Calibration+plan); verified by derivation from makeOrientationResult comment, unverified on screen.
Unit run 1 (unit-1.log, EXIT=65): all green except testOnGrid... (max diff 9e-5 on a 0.26 peak: the exact Gaussian keeps one extra far tap at 4 sigma, so
its normalisation differs ~1e-4). Prediction "~1e-7" MISSED (1e-4); tolerance set to 2e-4, still catches any real position change.
Tests: ACOMSubBinAzimuthDepositionTests. Green: unit-2.log EXIT=0 (4 passed). Mutation (af rounded to nearest bin): break-1.log EXIT=65,
red on testDepositionWraps..., testExperimentDeposition..., testTemplateDeposition...; testOnGrid... stays green by design. Reverted (cmp with OrientationPlan.fixed.swift), 
unit-1.log: ACOM classes (Row1MirrorZone, Row4Row5, Session, ScanSelection, FitOverlayPresentation) all passed apart from the tolerance issue above.
Harness results (acom-*.log, all EXIT=0): P1 acom-convention-test.log Au sampled in-plane<20 deg = 121 (>=120 MET; the "~130" proxy MISSED), mirror 122.
P2 acom-mirror-test.log Al lambda random: sampled >3 deg 9 of 107 (<=9 MET), mirror 4 of 93 (<=3 MISSED by one; flat-Ewald 6/107 + 4/93; WS2 0/200).
(2026-10-01, before democube-sb / grainb-*) P3: grain A median stays ~5.0 deg (winner t165; the on-grid [001] vertex issue is not azimuth-rounding);
grain B moves from 6.50 deg (t84) to < 3 deg (maybe t1 = 0 deg); grain C stays 0.00; grainb flat sweep: off-grid winners at the quarter-bin angles become t1.
RESULT (democube-sb.log, grainb-200-flat.log, grainb-200-wl.log, EXIT=0): P3 MISSED on the demo cube (A 5.027 t165, B 6.499 t84, C 0.000 t2 - identical to before).
grainb flat: on-grid B now t106 3.56 deg (was t1 0.00 exact); Al_111 on-grid score 0.9977 (was 1.0000). P4 MISSED with variant A (template linear+blur vs experiment
exact Gaussian): the two sides no longer share a kernel, so an exact on-grid pattern no longer scores 1. Diagnosis: the template's linear interpolation adds width the
experiment Gaussian does not have. Amendment 2026-10-01: trying variant B (both sides linear + the existing blur, identical deposition), measuring before choosing.
Variant B (both sides linear + blur) grainb-200-flat-B.log EXIT=0: Al_111 on-grid score 0.9982 (not 1.0000), B on-grid still t106 3.55 deg (0.9253 vs t1 0.9093), off-grid t160 1.84 deg.
So grain B's winner is NOT decided by azimuth quantisation: sub-bin deposition raised the neighbours t106/t160 (3.6/1.8 deg from t1) over t1 whose old on-grid win was a
quantisation coincidence. Mechanism for the demo cube's B error (6.50 deg, t84) not established by this lane; no inference from the null. Measuring convention/mirror under B to choose.
DECISION 2026-10-01 (measured, B vs A): convention-test Au sampled 121 / mirror 125 (B, acom-convention-test-B.log) vs 121 / 122 (A, convention.A.log); mirror-test Al lambda >3 deg
sampled 9/107, mirror 3/93 (B, acom-mirror-test-B.log) vs 4/93 (A); WS2 0/200 both. Variant B (template and experiment share linear interpolation + the existing blur) chosen:
simpler, no new parameter, better on the gates. The Gaussian experiment path and exactAzimuth were removed. Tests rewritten for B (the earlier unit-2/break-1 logs belong to variant A).
Final runs below are all on variant B.
(2026-10-01, before timing run) P5: buildPolar per call within 1.0-1.3x of HEAD (the loop adds one extra add per radial tap; blur dominates).
P5 timing.log EXIT=0: HEAD 49.3/48.3 us, now 48.8/49.3 us per buildPolar call (ratio 1.0): MET.
## Final (variant B) — all EXIT=0
unit-3.log 35 ACOM/overlay tests passed; break-2.log EXIT=65 red (3 of 4 tests, nearest-bin mutation), reverted, unit-4.log EXIT=0 (4 passed). core.log EXIT=0, inventory.log EXIT=0.
final-acom-convention-test.log Au sampled 121 / mirror 125; final-acom-mirror-test.log Al lambda >3 deg 9/107 and 3/93, WS2 0/200, CPU 1.46 ms/pattern;
final-acom-matching-test.log all passed; final-democube.log A 5.027 (t165) B 6.499 (t84) C 0.000 (t2); final-grainb-flat/-wl.log.
P1 MET (121 >= 120; proxy ~130 missed). P2 MET (3/93, 9/107). P3 MISSED (B unchanged 6.499, t84; synthetic grainb off-grid: t160 1.84 deg, was t106 3.56 deg: improved; on-grid t1 0.00 -> t106 3.56).
P4 MISSED for the grainb synthetic on-grid B (t1 exact -> t106 3.56 deg; score of t1 0.9101 -> 0.9093, t106 rose 0.9270->0.9253 off... ) - convention/mirror/matching on-grid cases pass. P5 MET (1.0x).
Overlay mirrored fix: FitOverlays.acomTemplateOverlay draws pi - (azim + angle) when result.mirrored; no automated test, unverified on screen.
Proposed doc line: ACOM polar images deposit azimuth sub-bin (linear, templates and experiment alike); DEVIATION recorded in buildPolar.
