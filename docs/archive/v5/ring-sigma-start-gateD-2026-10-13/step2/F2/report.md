# Lane F2 report — fixture tests and per-patch gates (ring-fit Gate D, step 2, 2026-10-14)

(In progress. Predictions are written before the run they concern.)

## Predictions for step 1 (plant re-check, written before the run)

- P1-1: lane F's binaries reproduce F's numbers for both plants on all four variants. DEAD (n192-R70-e10-t0.0-g60-s100-k3):
  head profile dR about -16.7 %, I1 0, sout 0.25; a and ab profile dR about -0.09 %; b status conic (reason names the floor,
  ringWidthAtFloor). DRIFT (n192-R70-e10-t112.5-g0-s100-k2): head profile dR about -41 %, centre about 39 px off; a, ab
  profile dR about -0.03 %; b identical to head (still wrong).
- P1-2: robust.sh (centre guess perturbed by 0, 1e-9, 1e-6, 1e-3 px): the DEAD and DRIFT outcomes do not move between the
  four perturbations for any variant (basins, not rounding accidents); dR for a moves in the 3rd significant figure at most.

(Step 1 ran; results below the next heading.)

## Step 1 result — plant re-check (logs/recheck-one.log, logs/recheck-robust.log; binaries lane F's search3-{head,a,b,ab}, -O)

dR = (a+b)/2 / R - 1, dba = b/a - truth b/a, cerr = centre error in px.

| plant | variant | status | dR | dba | cerr | I1 | sin / sout |
|---|---|---|---|---|---|---|---|
| DEAD n192-R70-e10-t0.0-g60-s100-k3 | head | profile | -16.67 % | -0.1212 | 5.27 | 0 | 1.03 / 0.25 |
| DEAD | a, ab | profile | -0.091 % | +0.0026 | 0.075 | 1.011 | 2.79 / 2.84 |
| DEAD | b | conic (reason: "The ring profile fit lost the ring: its fitted width fell to the 0.25 px floor.") | +1.31 % | -0.0077 | 0.31 | - | - |
| DRIFT n192-R70-e10-t112.5-g0-s100-k2 | head, b | profile | -41.14 % | -0.4356 | 39.08 | 0.662 | 2.89 / 3.91 |
| DRIFT | a, ab | profile | -0.033 % | -1.0e-5 | 0.010 | 1.007 | 2.97 / 3.01 |

Predictions P1-1 held (every number matches lane F's, to the printed digits). P1-2: the centre-guess perturbation (0, 1e-9,
1e-6, 1e-3 px) changes nothing for any variant on the DEAD plant (all four rows identical); on the DRIFT plant a, ab are
identical at all four, head and b move dR from -41.140 % to -41.247 % and cerr from 39.076 to 39.182 px at 1e-3 only (a
neighbouring-basin drift of 0.1 % of R, not a rounding accident). Both plants are basins: no replacement was needed.
Per-fit time at -O about 0.5-0.6 s (render + conic + profile fit), so each test costs about 0.6 s plus the render.
Note b on DEAD: the conic it falls back to reads R +1.31 % (above the 1 % line) and b/a -0.0077; test-b therefore does not
assert the conic's radius.

## Test files

- /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/F2/test-a/EllipseNoisyRingTests.swift
  (class EllipseNoisyRingTests; testNoisyGappedRingIsNotDrainedIntoTheBackground, testNoisyRingDoesNotDriftOffCentre)
- /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/F2/test-b/EllipseNoisyRingTests.swift
  (class EllipseNoisyRingTests; testNoisyGappedRingFallsBackToTheConicNamingTheFloor)

Search-set facts quoted in the doc comments, recounted by me from lane F's head logs (logs/ in lanes/F/logs, search-head-*.log):
2568 ROW lines; 221 profile fits with |dR| > 1 %, all at noise 0.10, by size 192 px: 92, 224 px: 32, 256 px: 97 (none at 128/160);
dead (min ring sigma <= 0.30) 87, drift (both sigmas >= 1) 130, other 4.

## Predictions for the gates (written before any gate run)

Test totals use HEAD's last run (2231 passed / 0 failed / 5 skipped of 2236 `func test`) plus the new methods.
- head-a (HEAD + test-a), unit: RED on exactly testNoisyGappedRingIsNotDrainedIntoTheBackground and
  testNoisyRingDoesNotDriftOffCentre; each fails on mean radius (-16.7 % / -41.1 %), b/a (0.121 / 0.436) and centre
  (5.27 / 39.1 px), but not on the model assertion (HEAD returns the profile model); 2231 passed / 2 failed / 5 skipped (2238).
- head-b (HEAD + test-b), unit: RED on exactly testNoisyGappedRingFallsBackToTheConicNamingTheFloor with 4 failed
  assertions (radius inside the `if let profile`, XCTAssertNil, model == .conic, reason contains); 2231 / 1 / 5 (2237).
- a (patch a + test-a): unit 2233 passed / 0 / 5 skipped, exit 0; core exit 0.
- b (patch b + test-b): unit 2232 / 0 / 5, exit 0 (the unit target holds no grains_12 case); core exit 0.
- ab (patch ab + test-a): unit 2233 / 0 / 5; core exit 0.
- Harness tools/ellipse-calibration-test/run.sh: a, ab pass; b FAILS grains_12_one_annulus (lane T).
- Mutation (b with the guard's 0.25 + 0.05 -> 0.25 - 0.05, i.e. threshold 0.20): the dead plant's sout 0.25 is above 0.20,
  so the profile fit is accepted again and the one new test goes RED (same 4 assertions as head-b).

## Gate results (all logs in $SP/lanes/F2/logs/; each .log has a .log.exit; counts by "passed on '" / "failed on '" / "skipped on '" lines)

Copies: $SP/gates/{head-a,head-b,a,b,ab,b-mut}/mac4DSTEM, built by gate-copy.sh from HEAD (e402373b archive) + the lane's files.
head-a/head-b EllipseCalibration.swift is byte-identical to HEAD's (diff -q silent); a/b/ab carry patches/EllipseCalibration.{a,b,ab}.swift.
Each unit run was `TMPDIR=<copy>/tmp heavy.sh <log> <copy>/tools/run-tests.sh unit` (SWIFT_OPTIMIZATION_LEVEL=-O set by run-tests.sh), run one
at a time (a macTEM `unit-mactemA` lock held the first queued run until it cleared; heavy.sh waited as designed).

| copy | log | exit | passed | failed | skipped | total | `func test` in copy |
|---|---|---|---|---|---|---|---|
| head-a (HEAD + test-a) | head-a-unit.log | 65 | 2232 | 2 | 4 | 2238 | 2238 |
| head-b (HEAD + test-b) | head-b-unit.log | 65 | 2232 | 1 | 4 | 2237 | 2237 |
| a  (patch a + test-a)  | a-unit.log  | 0 | 2234 | 0 | 4 | 2238 | 2238 |
| b  (patch b + test-b)  | b-unit.log  | 0 | 2233 | 0 | 4 | 2237 | 2237 |
| ab (patch ab + test-a) | ab-unit.log | 0 | 2234 | 0 | 4 | 2238 | 2238 |

Core (`tools/run-tests.sh core`, last line "core: DSTEMCore + DSTEMSession built"): a-core.log exit 0, b-core.log exit 0, ab-core.log exit 0.

Predictions against outcomes: RED sets held exactly (head-a: the 2 new methods, 3 failed assertions each; head-b: the 1 new method,
4 failed assertions); a, b, ab green with the new methods passing (names in the logs). The totals differ from my prediction in the SKIP column
only: every copy skipped 4 tests, I predicted 5 (from the last HEAD run, 2231 passed / 0 / 5 skipped of 2236). Total = func test count in
every copy (2238 / 2237), so no test is missing or duplicated (per-copy name lists: logs/{head-a,head-b,a,b,ab}-names.txt, one
"<Class.method()> <passed|failed|skipped>" per line, each name once). The four skips, identical in all five copies:
DiffractionEmbeddingTwoPassTests.testProfileSingleVersusTwoPass, SpectroscopyViewModelTests.testRenderRoom,
TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes, SpectroGoldenTests.testRecordBaseline. Which test was the fifth skip of the
last HEAD run, and why it ran here, I did not establish (no prior HEAD unit log in this scratchpad); the reconcile pass can name it.
Outside the new class the name/outcome lists of head-a vs a, head-b vs b, a vs ab, a vs b are identical (diff of the -names.txt files minus
the EllipseNoisyRingTests lines is empty): no patch moved any other unit test.
The 'error: the following command failed with exit code 0 but produced no further output' lines in the xcodebuild output (5 in head-a, 1 in a,
2 in b) are build-log noise, not failures.

New methods, all at -O: wall time per method in the unit runs 0.73-1.13 s (head-a 0.757 / 0.727, a 0.938 / 0.937, b 1.042,
ab 1.127 / 1.070; head-b 2.218 s while other tests ran in parallel).

### RED runs: assertion text
`run-tests.sh unit` is `-quiet` with parallel clones, so its log lists each failing method (3x for head-a's, 4x for head-b's, one
line per failed assertion) but not the assertion text. To get the text I ran the class alone, NOT quiet, serial, same project/scheme/
Debug/-O/CODE_SIGNING_ALLOWED=NO flags (lanes/F2/classonly.sh, via heavy.sh): logs head-a-class.log (exit 65), head-b-class.log (exit 65).
head-a-class.log, 6 failures in 2 tests:
- testNoisyGappedRingIsNotDrainedIntoTheBackground, line 100: XCTAssertLessThanOrEqual failed ("0.16669633556751706") is greater than ("0.01") - dead ring n192-R70-e10-t0.0-g60-s100-k3: mean radius 58.3312565102738 against 70.0
  line 102: ("0.1211500615657205") is greater than ("0.01") - ... b / a 0.8689489483352696 against 0.9900990099009901
  line 104: ("5.266558131211763") is greater than ("1.0") - ... centre (89.12220951107143, 98.89443290005651) against (94.32430722233897, 98.07296229689548)
- testNoisyRingDoesNotDriftOffCentre, line 100: ("0.4114006036617438") is greater than ("0.01") - drifting ring n192-R70-e10-t112.5-g0-s100-k2: mean radius 41.20195774367793 against 70.0
  line 102: ("0.43564782998704066") is greater than ("0.01") - ... b / a 0.5544511799139494 against 0.9900990099009901
  line 104: ("39.07616690717495") is greater than ("1.0") - ... centre (77.14744307148224, 61.52881713519043) against (97.20747037538976, 95.06301050142305)
  (the model assertion passes on both: HEAD returns the profile model.) These are lane F's HEAD numbers to every printed digit (dR -0.166696 /
  -0.411401, dba 0.12115 / 0.435648, cerr 5.26656 / 39.0762), so the in-test renderer reproduces the search generator.
head-b-class.log, 4 failures in 1 test (testNoisyGappedRingFallsBackToTheConicNamingTheFloor):
- line 103: XCTAssertLessThanOrEqual failed ("0.16669633556751706") is greater than ("0.01") - profile fit accepted with mean radius 58.3312565102738 against 70.0 (I1 0.0, sigmas 1.0264023118228807, 0.25)
- line 106: XCTAssertNil failed: "EllipseProfileParameters(centralIntensity: 0.0, ringIntensity: 0.0, centralSigma: 53.496336271476906, innerSigma: 1.0264023118228807, outerSigma: 0.25, background: 0.05963646214435265)" - a profile fit was returned
- line 107: XCTAssertEqual failed: ("asymmetricGaussian") is not equal to ("conic")
- line 108: XCTAssertTrue failed - fallback reason was nil

### Harness tools/ellipse-calibration-test/run.sh (via heavy.sh, TMPDIR in the copy)
- a-harness.log: exit 0, 29 PASS lines, 0 FAIL, last line "ellipse-calibration-test: all passed".
- ab-harness.log: exit 0, 29 PASS, 0 FAIL, "ellipse-calibration-test: all passed".
- b-harness.log: exit 1. `FAIL: grains_12_one_annulus was refused (ringWidthAtFloor) when it should fit — 36 of 36 bins`. fail() is
  `-> Never` (main.swift line 94), so the harness stops at the first failure: 11 cases passed before it (the 11 PASS lines are the first 11 of a's;
  stderr's FAIL line prints above them in the log), and everything after it (a's PASS lines 13-29: spotty_single_ring, the halo cases, the 48-ring sweep, ...) did NOT run
  under b, so b's behaviour on those is untested here. Matches lane T: under b the grains_12 ring (HEAD accepts a dead-ring fit there) is
  refused by ringWidthAtFloor and the conic residual is over 0.2, so fitBestAvailable throws instead of returning a fit; a and ab fit it
  (a's log: "PASS: grains_12_one_annulus fitted isotropic (a/b 1.0000, 36 of 36 bins)"). I did not re-derive lane T's -63.6 % / 0.388.
  The unit-test target holds no such case, so the b unit run is green: the harness is the only gate that sees b's refusal.

### Mutation beyond HEAD (b only)
Copy gates/b-mut = copy of gates/b with the guard `> 0.25 + 0.05` changed to `> 0.25 - 0.05` (threshold 0.20; the only diff, checked with diff).
Prediction held: the dead plant's sout is exactly 0.25 > 0.20, the profile fit is accepted again. Log b-mut-class.log (class alone, not quiet,
same flags as the head-a/head-b class runs, exit 65): RED, 4 failures, the same four assertions as head-b (radius 0.16669633556751706 > 0.01,
XCTAssertNil with the same EllipseProfileParameters (I1 0, sigmas 1.0264, 0.25), model asymmetricGaussian != conic, reason nil).
head-a and head-b are the "fix absent" mutations (RED above).

## Did not run
- The full `scientific` / `all` gates and the other harnesses; only unit, core and the ellipse-calibration harness.
- b's unit test with the guard mutated on the drifting plant (b has no drift test by design).
- The a/ab unit test mutated (e.g. half-maximum estimator broken): only "fix absent" (head-a) for a and ab. No Gate B / refuter pass on the tests.
- The class-alone runs (head-a/head-b/b-mut) used `-parallel-testing-enabled NO` and no -quiet, a deliberate deviation from run-tests.sh to
  get assertion text; the pass/fail counts above are from run-tests.sh unit itself.
- Nothing at -Onone (the brief's ~45 s/plant); nothing driven; the repo untouched.

## Left behind
Only logs, the lane files, and the copies' source under $SP/gates/{head-a,head-b,a,b,ab,b-mut}; their .build and DerivedData removed
(run-tests.sh removes its own DerivedData; classonly.sh removed its own; I deleted the .build dirs of a, b, ab). No process of mine runs.
