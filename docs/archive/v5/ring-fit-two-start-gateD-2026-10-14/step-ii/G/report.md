# Lane G report — fixture tests and per-variant gates (ring-fit two-start Gate D, step (ii), 2026-10-14)

(In progress. Predictions are written before the run they concern.)

## Predictions for the tail-plant search (written before any search run)

Generator: lane F's (lanes/F/search/main.swift) with an optional background term value += k (R / max(r,1))^2, r the plain
distance from the plant centre; copy in lanes/G/search/main.swift. Grid: size 192, R 60/65/70, eps 0.01/0.03, theta 20/112.5,
gap 0, noise 0.05/0.10/0.15, k 0.4/0.8, seeds 0-9 = 720 plants per variant. Centre guess truth + (1.3, -0.9), annulus b-20..a+20.
"HEAD right" = status profile and |dR| <= 0.1 %; "a wrong" = |dR| > 1 % (a's profile fit or conic fallback, whatever it returns).
- PG-1: at least 5 of the 720 plants are HEAD right and a wrong; they sit at noise 0.10-0.15 and mostly at k 0.4 (a is inert on
  steep tails, k 0.8 rarely loses a right fit; step 2's S3/S4: a lost 36 of 94 right r2 plants over 512 px sets with noise 0.15/0.30).
  Basis: step 2 refuter's S3/S4 finding (RF2 report), at 512 px and noise >= 15 %; whether it reaches 192 px / 5-15 % noise is the
  open question (S4 showed it at noise >= 5 % with k 0.4).
- PG-2: at least one such plant is a basin: the 1e-9 and 1e-6 px moves of the centre guess leave dR, dba and cerr unchanged
  to 3 significant figures for HEAD and for a. If none at 192 px, I go to 256 px.
- PG-3: cost: a 192 px fit at -O about 0.5-0.6 s each (lane F2), so the test costs about 1 s (one fit plus the render).

## Search result, 192 px grid (head and a; logs/grid192-{head,a}-p{0,1,2}.log, run via heavy-build.sh logs/grid192-head-a.log, exit 0; analysis an.py)

Sanity first (logs/sanity.log, exit 0): the tail-0 DEAD and DRIFT plants reproduce lane F's HEAD numbers to the printed digits
(dR -0.166696 / -0.411401, dba -0.12115 / -0.435648, cerr 5.26656 / 39.0762; a: -0.000908563 / -0.000328231), so the generator
change did not move the tail-0 renderer.
- 720 plants per variant (720 ROW lines in each of head and a). HEAD right (profile, |dR| <= 0.1 %): 626 of 720; HEAD wrong
  (|dR| > 1 %): 16.
- Right at HEAD and |dR| > 1 % under a: **10 of 626**, ALL at k (tail) 0.8, noise 0.10 (8) and 0.15 (2); none at k 0.4.
  PG-1: count >= 5 held (10); noise 0.10-0.15 held; "mostly at k 0.4" NOT held (0 at k 0.4, all 10 at k 0.8).
  In all 10, a ends at dR +2.34 % .. +2.49 % with the ring's inner sigma (ROW field sin) blown out to 37-132 px (outer sigma ~3), HEAD at |dR| <= 0.08 %.
  The ten: n192-R65-e10-t112.5-s100-k1-T80, ...-k5-T80, n192-R65-e10-t20.0-s100-k2-T80, ...-k4-T80, n192-R70-e10-t20.0-s150-k8-T80,
  n192-R70-e30-t112.5-s100-k0-T80, n192-R70-e30-t112.5-s150-k4-T80, n192-R70-e30-t20.0-s100-k0-T80, ...-k5-T80, ...-k8-T80.

## Predictions for c and cbs on the same grid (written before running them)
- PG-4: c and cbs are right (profile, |dR| <= 1 %) on all 10 plants above (c keeps the lower-cost of the two starts and a's cost is
  above HEAD's on tails, step 2 RF2; the HEAD-start result stays available). So the third method is green under c and cbs.
- PG-5: c is not worse than HEAD on more than 2 of the 626 HEAD-right plants (|dR| > 1 %).

## Result: c and cbs on the 192 px grid (logs/grid192-{c,cbs}-p*.log, driver log grid192-c-cbs.log, exit 0; counts by an.py and an inline recount)
Over the 720 plants: wrong (|dR| > 1 % or threw): head 16, a 27, c 16, cbs 16; no variant returns a conic on this grid. Right-at-HEAD
(626) lost (|dR| > 1 %): a 10 (15 at > 0.1 %), c 0, cbs 0. The 16 HEAD-wrong plants are all tail 0.8, R 60, eps 0.03 (HEAD +2.1 .. +2.2 %,
the 1/r^2 tail's own bias on the profile model) and are the same under a, c and cbs to the printed digits: no variant fixes them.
PG-4 held (c and cbs right on all 10 of a's failures); PG-5 held (c loses 0 of 626).

## Predictions for the basin check (written before running it)
- PG-2: for the 10 plants, the centre guess moved by 1e-9 and 1e-6 px (the PERTURB env of the generator, as in lane F / F2) leaves
  dR, dba, cerr unchanged to 3 significant figures under head and a; at 1e-3 px at most the 4th figure moves. If any of the ten moves
  at 1e-6 it is not used.

## Basin check result (logs/robust.log, via heavy-build.sh, exit 0; script robust.sh)
Ten plants x {head, a} x centre-guess perturbation {0, 1e-9, 1e-6, 1e-3} px (both coordinates, as lane F / F2): at 1e-9 and 1e-6
dR, dba, cerr are unchanged to 3 significant figures in all 20 plant-variant pairs (PG-2 held). At 1e-3: unchanged to 3 figures on
the plants k5 (R65 t112.5), k2, k4 (R65 t20), R70 e30 t112.5 s150 k4, R70 e30 t20 k5, k8, under both; moved in the 5th-6th figure of dR
(and the 3rd of cerr, 0.0428 -> 0.0430, a on R70 e10 t20 s150 k8) on the others. The prediction "at most the 4th figure" is slightly
off for one cerr; every cerr is < 0.05 px either way.
**Chosen plant (third test): n192-R65-e10-t112.5-g0-s100-k5-T80** (size 192, R 65, eps 0.01, theta 112.5, gap 0, noise 0.10, seed 5, tail 0.8):
HEAD/none/b2/s dR -2.29e-5 (-0.0023 %), dba +0.00149, cerr 0.0324 px, I1 1.012, sigmas 3.005/3.109; a dR +2.34 %, dba +0.00206, cerr 0.0323, inner sigma 131.6;
c, cbs identical to HEAD to the printed digits (logs/three.log, exit 0). Stable at 1e-3 in both. Fit time at -O: HEAD 0.114 s, a 0.42 s,
c 0.55 s (ms field, logs/three.log): the test costs well under the 1 s the brief allows (192 px sufficed, 256 px not needed).

All seven variants on the three test plants (logs/three.log; dR, status):
| plant | head, none | a | c, cbs | s | b2 |
|---|---|---|---|---|---|
| dead (R70 t0 g60 s100 k3) | profile -16.67 % | profile -0.091 % | profile -0.091 % | conic +1.31 % ("moved the ring 17.7 % from the conic fit.") | conic +1.31 % ("... fell to the 0.25 px floor.") |
| drift (R70 t112.5 s100 k2) | profile -41.14 % | profile -0.033 % | profile -0.033 % | conic +1.02 % ("moved the ring 41.7 % from the conic fit.") | profile -41.14 % (b2 does not see it) |
| tail (R65 t112.5 s100 k5 T80) | profile -0.0023 % | profile +2.34 % | profile -0.0023 % | profile -0.0023 % | profile -0.0023 % |

## Predictions for the gates (written before any gate run)
Skips: 4 on this machine (F2's runs), so passed = total - failed - 4. `func test` counts in the copies: head-c/a-c/c/cbs 2239,
s/head-s 2238, b2 2237, none 2236. All unit runs `TMPDIR=<copy>/tmp heavy.sh <log> <copy>/tools/run-tests.sh unit`, SWIFT_OPTIMIZATION_LEVEL=-O by run-tests.sh.
- G-head-c (HEAD + test-c): RED on exactly testNoisyGappedRingIsNotDrainedIntoTheBackground and testNoisyRingDoesNotDriftOffCentre (3 failed
  assertions each: radius, b/a, centre, as F2's head-a); the tail method green. 2233 passed / 2 failed / 4 skipped of 2239. exit 65.
- G-a-c (patch a + test-c): RED on exactly testNoisyRingOnAnInverseSquareTailKeepsItsRadius, ONE failed assertion (mean radius 0.0234 > 0.01;
  model, b/a 0.0021 and centre 0.032 px pass). 2234 / 1 / 4 of 2239. exit 65.
- G-c, G-cbs (patch + test-c): 2235 / 0 / 4 of 2239, exit 0; core exit 0.
- G-s (patch s + test-s): 2234 / 0 / 4 of 2238, exit 0; core exit 0.
- G-head-s (HEAD + test-s): RED on exactly testNoisyGappedRingFallsBackToTheConicNamingTheMove and testNoisyRingDoesNotDriftOffCentreFallsBackToTheConic,
  4 failed assertions each (radius in the if-let, XCTAssertNil, model == .conic, reason): 2232 / 2 / 4 of 2238. exit 65.
- G-b2 (patch b2 + test-b2): 2233 / 0 / 4 of 2237, exit 0; core exit 0.
- G-none (patch none, no new test): 2232 / 0 / 4 of 2236, exit 0; core exit 0.
- Outside EllipseNoisyRingTests the pass/fail/skip name lists are identical across all eight copies (no patch moves another unit test).
- Tool tools/ellipse-calibration-test/run.sh (Q5): PASS under none and c; FAIL under b2, s, cbs at `grains_12_one_annulus` (the harness stops at the
  first FAIL, so cases after it do not run under those three).

## Tool results: tools/ellipse-calibration-test/run.sh (Q5), via heavy-build.sh, TMPDIR in each copy; logs/{none,c,b2,s,cbs}-harness.log (+ .exit)
| copy | exit | PASS lines | FAIL line |
|---|---|---|---|
| G-none | 0 | 29 | - ("ellipse-calibration-test: all passed") |
| G-c | 0 | 29 | - (all passed) |
| G-b2 | 1 | 11 | `FAIL: grains_12_one_annulus was refused (ringWidthAtFloor) when it should fit — 36 of 36 bins` |
| G-s | 1 | 11 | `FAIL: grains_12_one_annulus was refused (ringLeftSeed(0.7015870417485846)) when it should fit — 36 of 36 bins` |
| G-cbs | 0 | 29 | - (all passed; grains_12_one_annulus "fitted isotropic (a/b 1.0000, 36 of 36 bins)" and "fitted isotropic anyway") |
Q5 held for none, c, b2 and s. **Q5 did NOT hold for cbs**: the registered prediction was FAIL on grains_12_one_annulus; cbs passes all 29 cases, as c does.
(fail() exits at the first FAIL; grains_12_one_annulus is PASS line 12 of a passing run, so under b2 and s the 17 PASS lines 13-29, spotty_single_ring onward, did not run: their behaviour is untested here.)
Unverified hypothesis for the cbs result, not tested: in cbs the guards act per start, so HEAD's start is refused (floor, as in b2) but the half-maximum start
is a second chance that passes every check; b2 and s have one start only. I did not instrument grains_12 to confirm which start returned the fit.

## Test files
- /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/G/test-c/EllipseNoisyRingTests.swift
  class EllipseNoisyRingTests: testNoisyGappedRingIsNotDrainedIntoTheBackground, testNoisyRingDoesNotDriftOffCentre (test-a's two, plants and assertions
  unchanged), testNoisyRingOnAnInverseSquareTailKeepsItsRadius (new: Plant(size 192, R 65, eps 0.01, theta 112.5, gap 0, noise 0.10, seed 5, tail 0.8);
  same assertions as the other two via assertRingIsFound: model asymmetricGaussian, |mean radius / R - 1| <= 0.01, |b/a err| <= 0.01, centre <= 1 px).
  The renderer gained one optional `tail` field (value += tail (R / max(r,1))^2 after the gap, before the noise). Doc comment: both search counts
  (2568 plants -> 221 / 87 dead / 130 drift / 4; 720 plants -> 626 HEAD-right, 10 lost by a, all tail 0.8) and the record path.
- .../lanes/G/test-s/EllipseNoisyRingTests.swift: testNoisyGappedRingFallsBackToTheConicNamingTheMove, testNoisyRingDoesNotDriftOffCentreFallsBackToTheConic
  (dead and drift plants; no profile, model .conic, reason contains "moved the ring" and "from the conic fit"; radius of the conic not pinned: +1.3 % / +1.0 %).
- .../lanes/G/test-b2/EllipseNoisyRingTests.swift = F2's test-b byte for byte (cmp'd in the copy against lanes/F2/test-b; its reason check is "0.25 px floor").
- Generator with the tail term: .../lanes/G/search/main.swift; binaries lanes/G/bin/search-{head,a,c,cbs,s,b2,none}.

## Gate results (each log has .exit; counts by count.py = unique `Test case 'X.y()'` outcomes in the log, repairing names that parallel-clone output split;
## reconciled against `grep -rh 'func test' mac4DSTEMTests | wc -l` in the copy; logs in lanes/G/logs/)
| copy | what | log | exit | passed | failed | skipped | total = func test |
|---|---|---|---|---|---|---|---|
| G-head-c | HEAD + test-c | head-c-unit.log | 65 | 2233 | 2 | 4 | 2239 = 2239 |
| G-a-c | patch a + test-c | a-c-unit.log | 65 | 2234 | 1 | 4 | 2239 = 2239 |
| G-c | patch c + test-c | c-unit.log; c-core.log | 0; 0 | 2235 | 0 | 4 | 2239 = 2239 |
| G-cbs | patch cbs + test-c | cbs-unit.log; cbs-core.log | 0; 0 | 2235 | 0 | 4 | 2239 = 2239 |
| G-s | patch s + test-s | s-unit.log; s-core.log | 0; 0 | 2234 | 0 | 4 | 2238 = 2238 |
| G-head-s | HEAD + test-s | head-s-unit.log | 65 | 2232 | 2 | 4 | 2238 = 2238 |
| G-b2 | patch b2 + test-b2 | b2-unit.log; b2-core.log | 0; 0 | 2233 | 0 | 4 | 2237 = 2237 |
| G-none | patch none, no new test | none-unit.log; none-core.log | 0; 0 | 2232 | 0 | 4 | 2236 = 2236 |
Core (`run-tests.sh core`) last line "core: DSTEMCore + DSTEMSession built" in c, cbs, s, b2, none. Skips (4, identical in every copy):
DiffractionEmbeddingTwoPassTests.testProfileSingleVersusTwoPass, SpectroGoldenTests.testRecordBaseline, SpectroscopyViewModelTests.testRenderRoom,
TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes. Outside EllipseNoisyRingTests, the 2236 name+outcome lines are byte-identical in all eight
copies (logs/*-names-outside.txt cmp'd against head-c's): no patch moves another unit test. Copy contents cmp'd: each EllipseCalibration.swift == patches/<variant>,
each test file == its lane source. Every prediction above held exactly (totals, failing names, skips 4).

### RED runs, assertion text (class-only reruns, NOT quiet, serial, same flags as run-tests.sh unit: lanes/G/classonly.sh = F2's, logs/{head-c,a-c,head-s}-class.log, exit 65)
G-head-c (EllipseNoisyRingTests: 3 run, 6 failures, the tail method green):
- testNoisyGappedRingIsNotDrainedIntoTheBackground: line 120 radius ("0.16669633556751706") > ("0.01") mean radius 58.33 against 70.0; line 122 b/a ("0.12115...") > 0.01; line 124 centre 5.2666 px > 1.0
- testNoisyRingDoesNotDriftOffCentre: line 120 radius 0.41140 > 0.01 (mean radius 41.20 against 70.0); line 122 b/a 0.43565 > 0.01; line 124 centre 39.076 px > 1.0
  (the model assertion passes on both: HEAD returns the profile model; numbers equal lane F's / F2's HEAD values to every printed digit)
G-a-c (3 run, 1 failure): testNoisyRingOnAnInverseSquareTailKeepsItsRadius, line 120: XCTAssertLessThanOrEqual failed: ("0.023411022882970256") is greater than ("0.01") -
  tail ring n192-R65-e10-t112.5-g0-s100-k5-T80: mean radius 66.52171648739306 against 65.0. The dead and drift methods pass under a. This is the mutation test-c claims to catch.
G-head-s (2 run, 8 failures, 4 per method): dead: radius 0.16670 > 0.01 "profile fit accepted ... (I1 0.0, sigmas 1.0264, 0.25)"; XCTAssertNil failed (EllipseProfileParameters(... ringIntensity: 0.0,
  innerSigma: 1.0264, outerSigma: 0.25 ...)) "a profile fit was returned"; XCTAssertEqual ("asymmetricGaussian") is not equal to ("conic"); XCTAssertTrue failed "fallback reason was nil".
  drift: radius 0.41140 > 0.01 (I1 0.662, sigmas 2.886, 3.908); XCTAssertNil failed (ringIntensity 0.662...); not equal to conic; "fallback reason was nil".

## Predictions against outcomes
PG-1 partly (count >= 5 held: 10; noise 0.10-0.15 held; "mostly k 0.4" not held: all ten at k 0.8). PG-2 held at 1e-9 and 1e-6 (all 20), cerr moved in the 3rd figure at 1e-3 on one plant.
PG-3 held (HEAD 0.11 s per fit, c 0.55 s). PG-4, PG-5 held. Gates: every row of the prediction list held exactly. Q5 (tool): held for none, c, b2, s; NOT held for cbs (passes).
Q6 (the fixture clause): held on both red sets (the two noisy methods red on HEAD, the tail method red under a only); unit + core green for none, c, b2, s, cbs, totals = the copies' func test count.

## Cleanup
Removed .build and tmp/* (DerivedData, TemporaryDirectory.*, swiftpm locks) in the eight copies $SP/gates/G-{head-c,a-c,c,cbs,s,head-s,b2,none}; sources and logs kept. No process of mine runs; no heavy.* slot of mine is held.

## Did not run
- scientific / all / benchmark gates; the other tools/ harnesses; only unit, core and ellipse-calibration-test.
- No search with a gap, no 224/256 px search (192 px sufficed), no theta other than 20 and 112.5, no R outside 60-70, no eps 0; the 10 found plants are all tail 0.8, none at 0.4.
- No Gate B / refuter pass on the tests; test-s and test-b2 not mutated beyond "fix absent" (head-s; and F2's b-mut for the b guard); test-c not mutated beyond head-c (fix absent) and a-c (half-max start alone).
- cs, cb variants (no test of their own); the cbs harness pass was not explained (hypothesis in the Tool section is untested).
- b2 and s harness: the 17 PASS lines (13-29) after grains_12_one_annulus did not run (the harness exits at the first FAIL).
- Nothing driven; the repo untouched (read-only: archive copy only).
