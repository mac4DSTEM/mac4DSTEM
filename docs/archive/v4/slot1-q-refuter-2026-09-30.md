# Slot 1 lane Q — independent refuter (Fable 5.1, read-only, 2026-09-30 night)

# Lane Q refuter — Fable 5.1, independent, read-only (2026-09-30, ~23:40)

Reviewed the DIAGNOSIS and the MEASUREMENTS: BRIEF.md, report.md, the six-file diff, the two test files,
tools/q-shell-probe, probe-*.log / probe-results.tsv, win*.log, s20/*.swift + s20-*.log, mut-run*.log/.err,
test-final.log / tests-final.json, s20-refuter §4–5, s14d § "Proposal, not a patch" + its cube table, the
threshold-history block, ADR 050's two cards, open-items §§ ACOM / Origin-fit. No repo file changed; one
read-only python replica of the bank sampler (below). Repo tree = working tree at 02174c9c + lanes' edits.

## Verdicts
| item | verdict |
|---|---|
| (a) ring mis-assignment on the app's own path | **HOLDS** |
| (b) S20 rerun | **HOLDS WITH CORRECTIONS** — reproduction and "F's regression was the probe's Q" hold; "the demo cube is not truth-bearing" is **REFUTED as a conclusion** (finding 7) |
| (c) `windowSensitivityPixels` | **HOLDS WITH CORRECTIONS** (9, 11, 12) |
| (d) the badge | **HOLDS WITH CORRECTIONS** (15, 16) |
| (e) the card's numbers | **HOLDS WITH CORRECTIONS** (17) |
| (f) the (d) diagnosis | **HOLDS WITH CORRECTIONS** (18) |

## (a) Findings
1. Same estimator, same arguments. `tools/q-shell-probe/main.swift:118–130` builds the DISTINCT |g| list from
   `crystal.reflections(kMax: 2.5)` and passes `shells[1]` exactly as `App/AppState+ACOM.swift:84–96`; the origin
   is `Calibration.referenceOrigin` → `.fittedMaps` on both (the probe passes `apertureCentre: nil`, the app the
   aperture — irrelevant once `meanOrigin` exists, `Core/Data/Calibration.swift:791`); vectors go through
   `BraggVectors.calibrated(with:referenceOrigin:)` on both. Detection is the app's DEFAULT path (synthetic kernel at
   the fitted radius `App/AppState+DiskDetection.swift:45`, `detectorAdapted` params `App/AppState+Open.swift:644`),
   not necessarily the owner's drive settings — the report should say "default settings". `probeRadiusPixels` is
   never read in the estimator body (`QCalibration.swift:161–269`), so its value is moot on both paths.
2. Arithmetic re-derived. 1 − √3/2 = 13.40 %. Q_est/Q_truth = (g111/g200)/(1+δ), δ = r1·Q_truth/g200 − 1 read
   from each log's "median r1 … is shell (-2 0 0) at truth Q (x % off)": demo +0.06 % → −13.45 ✓; Thronsen −0.2 %
   → −13.22 ✓; raw −0.8 % → −12.70 ✓; binned −1.0 % → −12.52 ✓. r2/r1 1.4129 / 1.4146 = √2 to 0.1 % (220/200);
   raw 1.367 and binned 1.374 sit 3 % under √2 because r2 is 4.1 / 3.8 % under (220) (probe-raw060.log,
   probe-binned060.log); the ellipse run restores it (1.428, r2 0.0 % off, probe-raw060-ellipse.log).
3. Majorities: the demo's per-grain rows are READ from truth.json's `grain_label_map` at truth Q (probe-demo.log:
   A 5400 → (200) 0.1 %, B → (111) 0.0 %, C → (220) 0.0 %). Thronsen / raw / binned "(200) 70–84 %" are INFERRED —
   nearest shell at the supplied truth Q (main.swift:178–195). For the owner's cube that "truth" is the 09-29
   lattice fit (`almgsi-raw-stride3-registration-2026-09-29.md:34` 0.006577; `:42` 0.006850 per ellipse-corrected
   px), which itself placed the {200} ring at 75.1 px (`:38`) independently of the (111) assumption — so the
   inference is anchored. The report's "1.0846 is the ELLIPSE axis ratio" is confirmed (`:35`).
4. The raw cube's 28–30 % near-(111) positions persist WITH the ellipse (71.7 / 28.3 %), so ellipse smear is
   excluded by observation; "unresolved" is the honest state. His cube reads 1.367 raw / 1.428 ellipse / 1.374
   binned — "≈ 1.41" in ADR 050's own words (card line 51), so the card's "then the ring-assignment fix" clause is
   now live for the supervisor.

## (b) Findings
5. Reproduction HOLDS: s20-base-calibrated.log A 5.027 / B 6.499 / C 0.000 (t2); s20-patched-calibrated-k12.log
   C 1.637 (t198) = `s20-acom-offgrid-results-2026-09-30.md:71` (A 5.03, B 6.50, C 0.00 → 1.64, t2 → t198). The
   record's kMax 0.9 patched-at-calibrated row (`:72`) was not re-run; the k1.2 pair suffices.
6. "F's regression was the probe's Q" HOLDS: s20-patched-trueQ-k12.log and -k09.log keep C at t2 0.000° — the
   S20 refuter's pre-registered outcome (a) (§5.2). F is not neutral at true Q: A 5.027 → 3.176 (t165 → t173,
   77.5 % of the grain). Cost 0.25 → 0.94–0.96 s = 3.8× (MATCH lines); the record said 4.5×.
7. "The demo cube is NOT truth-bearing for ACOM" — REFUTED as a conclusion. `ACOMCrystalSymmetry.sampleFundamentalZone`
   (`Core/Analysis/OrientationResult.swift`) seeds the bank with the three vertices [001], [101], [111]; grain B's
   truth [011] (truth.json) reduces under `reduceDirection` (z ≥ x ≥ y ≥ 0) to (0.707, 0, 0.707) = **t1 exactly**.
   A read-only python replica of the sampler at count 200 reproduces every axis the harness printed (t84 at 6.50°
   from [101]; t165 5.03° and t173 3.18° from [001]; t198 1.64° from [111]) and shows the nearest non-vertex
   templates to [101] are t160 (1.84°) and t177 (1.88°). So B's winner t84 is neither the exact template nor a
   nearest neighbour, the bank is not short, and the 6.499° is invariant under Q (0.010386 / 0.012), kMax
   (1.2 / 0.9) and F (all six s20-*.log): a property of the matcher/plan, not of the cube. The S20 refuter's §5.1
   bar ("if B stays, the cube is not truth-bearing") read a null as a mechanism (CLAUDE.md: never infer a mechanism
   from a null result); lane Q applied it literally. Leads, not diagnoses: the harness's plan is flat-Ewald
   (s20/main.swift:76 and real-acom-benchmark:96 pass no wavelength) while the app's passes `planWavelength`
   (`App/AppState+ACOM.swift:168–175`), so the harness's B may not even be the app's number; and B's in-plane 40°
   is 0.22 bin off the 2.8125° azimuthal grid — the S20 off-grid mechanism. The closing line must read: "B 6.50°
   invariant under Q, kMax and F; the exact template t1 exists; undiagnosed, matcher-side — its own Gate D."

## (c) Findings
8. Measures what its name says: the same kernel as the shipped tile path (`MetalEngine.measureOrigins`,
   `Shaders/OriginMeasure.metal:103` `win = max(r·rscale, r + 1.5)`; `VirtualDetector.swift:482–506`), rscale
   1.2 vs 2.5 (`OriginCalibration.swift:653–654`), the coarse seed recomputed inside the kernel independent of
   rscale so both readings share it, strided ≤ 200 (`windowSensitivitySampleIndices`, ceil step), median of
   Euclidean |Δ|. reported == direct on all 14 win logs.
9. Cannot move the shipped origin: `fitted` (`OriginCalibration.swift:614–617`) precedes the call (`:623–628`),
   whose result only fills the fifth tuple element; the one app caller (`App/AppState+Calibration.swift:90`) reads
   by label and ignores it; the other 28 call sites are tools/tests. CORRECTION: `shippedWindowScale` is
   hard-coded 1.2 and ignores `tiledRun`'s `rscale` parameter — no caller passes another value today, but one that
   did would get a "shipped" reading that is not its own. Pass `rscale` through.
10. Fixtures discriminate for the claimed reason: ringed r 6.49 → win(1.2) = 7.99 px cuts the ring at ρ 8.5 ± 1.5,
   win(2.5) = 16.2 encloses it; compact r 2.92 → both windows enclose the erfc disk. But 36 near-identical
   patterns cannot see sampling or aggregation. Changes that keep all 11 new tests green with the quantity wrong:
   (i) `Array(0..<min(200, total))` in place of the strided sample — a scan corner, not a sample (the index test
   pins the pure function, not its use, `OriginWindowSensitivityTests.swift:57–67`); (ii) `distances.max()` or
   `.first` for `median`; (iii) `wideWindowScale = 2.0` (S14-D's 3.87 px at k 2 keeps the ringed test green);
   (iv) a CPU re-implementation instead of the shared kernel. (i)–(ii) need a fixture whose shape varies by position.
11. The surfacing line is wrong on the app's own demo. S14-D's cube table
   (`s14d-origin-refine-gateD-2026-09-30.md:50`) reads the in-app `--demo-fixture` (12² × 64², r 6.93 — a compact
   probe with sample scatter, no ring) at **3.36 px** between the shipped window and k 2.5; open-items:77 already
   carries its 1.70 px at k 2. Au_ref (a halo, not a ring, S14-D:8) reads 5.31 (win-auref.log). The lane's compact
   set (win-*.log) omits the app fixture, so "compact maximum 0.07" and the proposed 1-px line are unmeasured on
   the one cube every launch opens: the line would fire on the demo. Either the line says only what it measured
   ("moves X px with the window") with no ringed-probe reading, or it is not proposed until the demo fixture is
   measured on this path.
12. Cost/memory. 0.004–0.053 s except the gzip row-chunked demo cube 0.83 s (win2-demo.log; the < 0.1 s budget
   missed 8× there, disclosed). Not disclosed: `gathered` is ≤ 200 × qy × qx floats with no byte bound
   (`OriginCalibration.swift:684–689`) — 52 MB at 256², 0.8 GB at 1024², 3.4 GB at 2048² — one Metal buffer on
   every origin calibration, with nothing surfaced yet. Bound the sample by bytes (limit = min(200, budget /
   patternBytes)) before it meets a 2k detector.
13. Test discipline. Mutation runs bundled edits (run A three, B/D/E two; mutrun.py, mut-run*.log), so "each red on
   exactly the predicted tests" is by inference from which test each edit alone can reach — sound here (only the
   `.measuredInApp` guard protects the manual/sidecar/import cases), but one edit per run is the rule's letter. Final
   run 30/30 = 4 + 7 + 7 + 12 over four classes (tests-final.json), not the unit gate. inventory-2.log carries no
   exit line of its own; the report's EXIT=0 cannot be read from the log.

## (d) Findings
14. No threshold entered: `uncheckedNote` (`QCalibration.swift:55–58`) fires on `.notSelfChecked` alone;
   `selfCheckSummary` (`QCalibrationRun.swift:63–65`) and the status line (`AppState+ACOM.swift:131`) share it; the
   measured branch keeps its numbers (badge test 36–43 pins it at 0.1 %, 22 %, 50 %).
15. The caveat can never describe another value: shown only under `provenance.qScale == .measuredInApp &&
   caveat.pixelSize == size` (`Calibration.swift:397–400`); `.measuredInApp` with that Double is set only by
   `calibrateQFromCrystal`, which always overwrites the caveat (`AppState+ACOM.swift:118–120`). Clear resets
   provenance (`CalibrationSession.swift:151`); sidecar restore stamps `.sessionSidecar` (`AppState+Open.swift:1072`);
   re-reference passes provenance through (`CalibrationReReference.swift:348`) and a rescaled size fails the
   equality. The path that exists is a LOST caveat, not a stale one: rewind (`AppState+Lineage.swift:425–428`)
   restores size + `.measuredInApp` from a `calibration_q` node whose parameters carry no shell check
   (`recordQCalibrationRun`: q_pixel_size, q_units, source) — calibrate (unchecked, caveat C) → calibrate again
   (measured, caveat nil) → rewind to the first: "Measured", no caveat, the unchecked scale in force. The same loss
   on every sidecar restore and re-reference. Record `uncheckedNote` in the `calibration_q` parameters and restore
   it on rewind, or document the loss on the row.
16. The owner's decision is not what shipped. ADR 050's card (`050-…md:51`): "badge 'unchecked' when the ratio
   DISAGREES; … then the ring-assignment fix if his cube reads ≈ 1.41". What ships says "unchecked" only when NO
   ratio was measured (one shell). On his cube the ratio IS measured (1.37–1.43) and the Q row will read "Measured"
   with no caveat; the numbers sit on Prepare's shell-check row and the status line only. The supervisor's
   2H < M/2 rule and CLAUDE.md's threshold rule justify drawing no line; the report must say plainly that the
   owner's "disagrees" half did not ship and why, and the card must go to him as the sheet he asked for.

## (e) Findings
17. H = 4.07 % is the brief's number, not a measurement on this path: the S13 Gate B refuter's 1-px synthetic
   origin displacement on sim_Au (`QCalibration.swift:13–17`), from the tree note (1) of the same block calls not
   reproducible; today's measured healthy value is 2.44 % (n = 1, against a reference Q the report itself calls
   +2.4 % biased), and the 1.14814 the estimator's comment quotes (`:179–180`) is not what the app's path reads now
   (1.1265) — the healthy side is path-sensitive. WS₂'s 13.3 % IS the estimator's own failure class — the innermost
   allowed shell (0002) is not excited in the [0001] zone, exactly as {111} is absent in Al [001] — and
   `Crystal.reflections(kMax:)` (`Crystal.swift:122`) has no (00l) filter, so on today's path it belongs in M.
   The correction: the rule's verdict is one number away on BOTH sides — with H = 2.44 (measured) 2H = 4.88 <
   M/2 = 6.67 and a line ships at 4.9 %; with the (00l) filter landed WS₂ reads (10-10)/(11-20) = 1.732 vs 1.7333
   (0.07 %) and moves to the healthy side, M = 18.39, 2H = 8.14 < 9.20 and a line ships at 8.1 %. The card does
   not show this. It is the true reason no line ships now: n = 1 healthy, and the verdict flips on a recorded
   number from a superseded tree and on an open item — not "8.14 ≥ 6.67".

## (f) Findings
18. The √2 trap is real in the abstract ((200):(220) = (220):(400) = √2; also (111):(222) = (200):(400) = 2) but it
   is a property of a matcher without a prior: on the demo (128², Q 0.012) (400) sits at 82 px > the 64-px
   half-width — off the detector — which is why the offline N = 6 flip appears on Thronsen (r1 25.9 px, (400)
   inside) and not on the demo. Cheaper rules the diagnosis missed, named not designed: (i) the innermost detected
   ring is the innermost ring OF THE ZONE the ratio identifies — [001] (200):(220) = √2; [011] (111):(200) = 1.155;
   [111] (220):(422) = √3; [112] (111):(220) = 1.633 — a per-zone first-two-ring table, N bounded by the zone's own
   list, so (220,400) is never a candidate pair; (ii) the azimuthal count/angle of the innermost cluster the
   estimator already measures (`sameShellPeaksPerPosition`: 4 at 90° in [001], 4 at 70.5° in [011], 6 at 60° in
   [111]) identifies the zone per position with no ratio at all; (iii) a ±30 % prior on Q from the file or the probe
   breaks a +41 % √2 error. The intensity rank is NOT a rule to pick (kinematic ≠ dynamical; thickness). Under (i)
   sim_Au's 1.5-point margin becomes a per-zone tolerance and WS₂ stays a (00l)-filter item, not a matcher one.

## What must change before this lands
A. (b)'s headline and the open-items closing lines: "B 6.50° invariant, exact template t1 exists, undiagnosed
   matcher-side — own Gate D", never "not truth-bearing". Lane Q wrote none of the three closing lines it owed
   (open-items:60–62 Candidate F, :63–64 known-crystal Q, :77–78 coarse-seed "Next") — `git diff docs/open-items.md`
   has no lane-Q line; closeout owes them.
B. The surfacing line: no 1-px reading until the app's `--demo-fixture` is measured on this path (S14-D: 3.36 px).
C. `windowSensitivityPixels`: take `rscale` from `tiledRun`; bound `gathered` by bytes.
D. The decision card: add the two flips (H = 2.44 → line at 4.9 %; WS₂ after the (00l) filter → line at 8.1 %),
   and state that ADR 050's "unchecked when the ratio disagrees" did not ship and why.
E. The lost-caveat path (rewind / sidecar / re-reference): record `uncheckedNote` in `calibration_q`, or document.
F. Optional: one mutation per run; note the fixtures cannot see sampling or aggregation.
Everything else in (a)–(f) HOLDS as measured; the four Q errors, the √2 ratios and the S20 rows reproduce from the logs.
