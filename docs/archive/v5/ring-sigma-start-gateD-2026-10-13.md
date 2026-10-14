# The profile ring fit's start traps noisy rings — Gate D (2026-10-13)

Reported by macTEM (`../macTEM/docs/archive/mac4dstem-ring-start-report-2026-10-13.md`, its Gate D and refuter in
`ring-fit-noisy-gate-d-2026-10-13/`; its copy of `EllipseCalibration.swift` is this repo's at `5ba712a0`). Registered
here before any run on this tree; the Results section is added after. Nothing lands from this record without the owner:
a change here moves the ellipse the app applies (card M2).

**Trigger.** Gate D: a reported defect, cause not yet established on this tree, in the function behind the Fit button
(`fitBestAvailable` → `CalibrationSession.applyEllipseFit`; b/a and θ are applied to every Bragg vector).

**Diagnosis (macTEM's, to be refuted here).** `fitAmorphousRing` starts both ring sigmas at `max(1, ringWidth / 4)`
(10–17 px for a ±20 px annulus around a 3 px ring). On noisy rings the 11-parameter LM from there falls into a dead-ring
basin: I1 → 0, the ring sigmas at their 0.25 px bound, a wide central Gaussian and the constant carrying the annulus mean,
so a, b, θ and the centre carry no ring information. The residual cap does not refuse it, because noise inflates the
normalised residual of any model (a ring-less constant scores 0.17–0.26 against the 0.22 cap).

**Refuting observations** (any one refutes; a failed reproduction closes the item, ADR 050):
- R0: on macTEM's 144 noisy plants and its fresh set (SEED0 77031), this tree's `fitBestAvailable` (default arguments,
  macTEM's centre guess and annulus) accepts no profile fit that is off by more than 1 % in (a + b)/2.
- R1: the accepted wrong fits cost no more than the true ring's model on the same pixels (then they are the model's
  optimum, and no start can fix them).
- R2: a ring-sigma start read from the seed (below) rescues fewer than 90 % of them, or turns a right fit wrong.

**Predictions:**
- P1: ≥ 10 accepted profile fits off by > 1 % in (a + b)/2 on the 144 (macTEM: 16 through its own wrapper, which also
  refuses a/b − 1 > 0.093); on most, I1 below a tenth of its start or a ring sigma within 0.05 px of 0.25. Their b/a and
  θ errors are reported too, since those are what the app applies.
- P2: each costs ≥ 1.2× the true ring's model on the same pixels.
- P3, candidate (a), the ring sigmas started from a width measured on the seed ellipse's radial profile (half maximum,
  no truth): 0 such fits on both sets; no fit within 0.1 % before is outside it after; on macTEM's 84 clean plants and
  `tools/ellipse-calibration-test`'s 48-ring sweep and existing cases, no model choice is lost and every profile fit kept
  both ways moves by ≤ 0.01 % of R in (a + b)/2 and ≤ 1e-3 rad in θ.
- P4, candidate (b), a profile fit with a ring sigma ending within 0.05 px of its bound is refused (the fit falls back to
  the conic): it catches ≥ 10 of the P1 fits and refuses no fit that was within 0.1 %.
- P5, real data: on the mean pattern of `Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5` (polycrystalline Au
  rings), HEAD and candidate (a) choose the same model on each ring annulus tried and agree to 0.01 px and 1e-3 rad.

**What would be built.** Candidates (a) and (b) as held patches with a fixture (a noisy plant red on HEAD), gated, not
applied. The owner chooses on card M2: (a), (b), both, or neither.

## Step 2 amendment (2026-10-14, written and committed before any step-2 run)

- **The candidates as built**, held in `ring-sigma-start-gateD-2026-10-13/` (`core-a.diff`, `core-b.diff`, `core-ab.diff`,
  each against `EllipseCalibration.swift` at `5ddec30d`; none applied). (a): both ring sigmas start at the half-maximum width
  of the annulus's radial profile about the conic seed: 1 px bins of the seed's elliptical radius scaled to (a + b)/2, a
  3-bin mean, the half maximum between the profile's minimum and peak, crossings interpolated linearly, σ = FWHM / 2.3548,
  at least 1 px; py4DSTEM's (ro − ri)/4 stands when the peak has no crossing on both sides inside the annulus. The sigma
  step scales stay (ro − ri)/4. macTEM's tested estimator measured the circular radius about the seed centre in whole bins,
  so its 16 of 16 is not evidence for this one; P3 is. (b): a profile fit whose smaller ring sigma ends ≤ 0.30 px throws
  `ringWidthAtFloor` after the existing checks, and `fitBestAvailable` falls back to the conic (or throws when the conic's
  residual is over 0.2). Lower bound only.
- **P6, both (a + b):** 0 accepted profile fits off by > 1 % on either noisy set; no fit within 0.1 % before is refused
  or outside it after; on the clean sets and the 48-ring sweep, as P3.
- **Sets:** set A = macTEM `refuter/plants_a.py`, set B = `plants_b.py` (SEED0 77031, the "fresh set"), macTEM `6c1f4d4`,
  all 275 cases each: noisy and clean decide P3, P4 and P6 as registered; the printed and refusal tiers are printed, not
  decided. "Wrong" = off by > 1 % in (a + b)/2 (step 1); "right" = within 0.1 %.
- **P5's annuli**, read off the mean pattern's radial profile before any fit (64 × 64, a beam stop and its wire; rings near
  9.5, 16.5, 25 and 33.5 px about the centre guess (28.47, 34.43), the centroid of the brightest 1 % of pixels): [5, 13],
  [13, 21], [21, 30], [30, 38], and each widened by 1 px on both sides.
- **The fixture:** seeded noisy plants rendered in the test (no data file) on which HEAD accepts a profile fit off by more
  than 1 %; the test asserts the Fit returns no profile fit that far off. One plant of the dead-ring kind (expected green
  under (a) and (b)) and, if one exists at a unit-test size, one of the drifting kind (expected green under (a) only).

## Results — step 1 (2026-10-13, M5 Pro; the session ended before steps 2–5)

A Sonnet lane ran this tree's `fitBestAvailable` (HEAD `ce245821`, default arguments, macTEM's centre guess and annulus) on
macTEM's refuter plant sets (`refuter/plants_a.py`, `plants_b.py` at macTEM `6c1f4d4`; 144 noisy plants each, 3 and 10 %
noise). The harness and the analysis are in `ring-sigma-start-gateD-2026-10-13/` (`scan-main.swift`, `build.sh`, `an.py`);
its output, `head-noisy-summary.txt`. "Wrong" = an accepted profile fit off by more than 1 % in (a + b)/2.

- **R0 not refuted, P1 held:** 35 of 144 (set A) and 32 of 144 (set B) accepted profile fits are wrong — macTEM counted 16 on
  set A because its wrapper refused 19 more for a/b − 1 > 0.093 (16 + 19 = 35); this app has no such refusal. Off by up to 48 % in R, 0.51 in b/a (what the
  app applies), 1.56 rad in θ, 40 px in the centre. The conic seed was within 1.3 % on every one.
- **R1 not refuted, P2 held:** every wrong fit costs 1.30–3.42× the true ring's model on the same pixels (35 of 35, 32 of 32).
- **Not as diagnosed:** only 17 of 35 and 18 of 32 are the dead ring (I1 below a tenth of its start, or a ring sigma ≤ 0.30
  px). The rest keep ring sigmas of 2–7 px and drift 10–40 px off centre, mostly 10 %-noise rings with a 60° gap. So
  candidate (b) alone cannot catch about half; whether (a) rescues them is P3, not yet run.
- Clean plants (84): 59 profile, 25 conic fallbacks (residual 0.235–0.336), as lane E measured on 2026-10-12.
- Not run: R2, P3, P4, P5 (candidates, Au_ref), the held patches, the fixture, the refuter. The next session resumes at step 2.

## Results — step 2 (2026-10-14, M5 Pro; sessions `e5b5e609` and, after its usage limit, `91438f32`)

Lanes M (sets A, B), T (`tools/ellipse-calibration-test`), P5 (Au_ref) and F (fixture search) ran under the first session;
the fixture tests and per-patch gates (F2) and a fresh refuter (RF2, independent of F2; the first refuter was cut off with raw
logs only) under the second. Every lane's report, scripts and raw logs are in `ring-sigma-start-gateD-2026-10-13/step2/`; the
plants regenerate from their seeds. "Wrong" = an accepted fit off by > 1 % in (a + b)/2, "right" = within 0.1 %.

- **R2 not refuted on the registered sets:** (a) rescues 35 of 35 (A) and 32 of 32 (B), all to within 0.1 %, and turns no
  right fit wrong; b/a error on the noisy tier from up to 0.51 to ≤ 0.0035 (`M/logs/{head,a}_{A,B}.log`, `M/compare-out.txt`).
  Out of sample (RF2, set C, SEED0 52817): 29 of 29, 0 right lost.
- **P3 (a): noisy clauses held; the clean clause did not.** On the 84 clean plants 25 change model (all conic → profile,
  none lost) and the 59 kept profile fits move up to **0.131 % of R and 0.128 rad** (registered: ≤ 0.01 %, ≤ 1e-3 rad); on the
  48-ring sweep 5 of 32 kept fits move > 0.01 % (max 0.120 %), and HEAD's conic fallback on 16 gapped sweep rings becomes a
  profile fit. Every mover ends at a lower cost (clean gapped plants ×0.90–0.91; sweep residual 0.1506 → 0.1356): HEAD's
  fits there were local minima, and the registered premise — a fit kept both ways is the same fit — was false. The lower
  optimum of a gap-less model on a gapped ring lies farther from the plant in θ (0.001–0.027 → 0.011–0.155 rad at 1 %
  ellipticity) and centre (0.02 → 0.12 px); b/a error ≤ 0.0033. Not amended (ADR 050).
- **P3's "no right fit outside 0.1 % after" fails out of sample (RF2):** on a 1/r² background tail (0.4–0.8 × the ring at
  its radius) with Gaussian noise of 5–30 % of the ring, HEAD is right on 94 of 96 plants and (a) loses 36 of those 94; 25
  of the 96 end > 1 % off (HEAD 0), b/a off up to 0.71 (`RF2/logs/S3_*.log`, `S4_*.log`; recounted by this session's own
  parser). On the Poisson set 20 of 44 right r2 plants are lost the same way, each at a higher cost than HEAD's fit (19 of
  20): (a) misses an optimum HEAD finds. On a steep tail the half-maximum has no crossing and (a) is inert (= HEAD); at a
  neighbour ring 0.8× as bright at 1.1–1.155 R it ends +0.6 to +7 % off where HEAD is at the optimum.
- **P4 (b) held on the registered sets, not out of sample:** refuses 15 of 35 and 16 of 32 wrong fits — exactly those with
  a ring sigma ≤ 0.30 px — and 0 right; set C only 7 of 29 (< 10). 0 right fits refused on any pixel-integrated set (A, B,
  C, Poisson, traps, one-sided edges, tails); 19 refused on point-sampled sub-pixel rings (σ 0.25–0.30; conic within 1 % on
  17). It leaves the drifting kind (20 of 35, 16 of 32, 22 of 29) and the ceiling failures on Au_ref. On the tool it refuses
  `grains_12_one_annulus` (HEAD there: a dead ring 63.6 % small in R), the conic is over its cap, the Fit throws, and **the
  unmodified tool FAILs under (b)** (`F2/logs/b-harness.log`); its "fit, isotropic" expectation would have to change.
- **P6 (ab):** 0 wrong and 0 right lost on A and B; equal to (a) on all 550 plants and 123 tool records. Out of sample it has
  the fewest wrong Poisson fits (47; HEAD 148, a 66, b 105) but loses 18 right ones, and on the r2 tails b's conic
  fallbacks are themselves biased (7 of 24 with b/a off > 0.01; HEAD 0). The clean clause fails as P3's.
- **P5 held as registered, weakly informative:** same model on all 8 Au_ref annuli, worst difference 1.0e-5 px and 1.7e-6
  rad, but (a)'s estimator fired on 2 of the 7 annuli that reached the profile stage. HEAD's real fits show the defect:
  A4 [30, 38] is a dead ring (I1 0, σ 0.25 px) that (b) refuses; W4 puts the ring at a = 57.6 px, outside its annulus,
  with a σ at its ceiling, and W3 a σ at its ceiling — neither candidate catches those (`P5/report.md`).
- **The defect's condition (RF2, not registered):** HEAD's wrong fits on flat-background noisy rings depend on the caller's
  centre guess: 12, 20, 29, 21 of 144 at 0, 0.75, 1.6 and 3 px from the true centre, 0 at 7.8 and 15.6 px; (a) is right at
  every offset. The app's guess is the measured beam centre, an accurate one. Mechanism not established.
- **Fixture (F2):** `EllipseNoisyRingTests`, two 192 × 192 plants found by lane F's 2568-plant search (HEAD wrong on 221,
  all at noise 0.10; dead 87, drift 130): a dead ring (HEAD −16.7 %) and a drifting one (HEAD −41 %, 39 px off); both are
  basins (unchanged under 1e-9 and 1e-6 px moves of the guess). Test-a (2 methods: profile, ≤ 1 % R, ≤ 0.01 b/a, ≤ 1 px)
  for (a) and (ab); test-b (1 method: the dead ring falls back to the conic naming the floor) for (b). Gate copies named
  mac4DSTEM, one run at a time: head-a **2232 / 2 / 4** and head-b **2232 / 1 / 4** (exit 65, red on exactly the new
  methods), a **2234 / 0 / 4**, b **2233 / 0 / 4**, ab **2234 / 0 / 4** (exit 0), each total = the copy's `func test`
  count (2236 + new; reconciled by name, `F2/reconcile.md`); core exit 0 for each; b's guard mutated to 0.20 px: red.
  The tests stay here, never in `mac4DSTEMTests`: they are red on HEAD. Four skips, not the 2026-10-13 run's five:
  `testClickingARecentOnAnUnmountedVolumeKeepsTheEntry` ran (it skips only without such an entry in the owner's recents).
- **Refuter (RF2) verdicts:** (a), (b) and (ab) each UPHELD WITH CORRECTIONS (`RF2/report.md`). Every count in the first
  refuter's logs reproduced by its own parser and 344 + 1472 re-run rows (0 mismatches); its corrections: the trap set's
  "a loses 4 right" were right-by-luck at HEAD (residual 0.12 vs 0.07 at the optimum (a) reaches), and 16 of HEAD's 44 trap
  failures (a neighbour 1.5× brighter) are unfair targets.
- **A lead for a new registration (projection, not a measurement):** in every loss above, the worse fit has the higher
  cost. Keeping the lower-cost of HEAD's and (a)'s profile fits, from the logged rows of all 2009 plants: 80 wrong (HEAD
  414, a 135), 0 lost on the tails, 3 new wrong, 5 right lost of which 4 are the right-by-luck trap fits
  (`projection/twostart.py`, `twostart-out.txt`); 8 of the 441 rings where the starts disagree go the other way
  (`costorder.py`). The card's second opinion added a seed-consistency check: refusing a profile fit whose radius left the
  conic seed by > 5 % flags 333 of 379 wrong HEAD fits and 4 of 1155 right ones (`seedcheck.py`, reproduced; in-sample).

**Outcome.** The diagnosis holds for flat backgrounds (the start traps the fit; a start at the ring's width escapes, at a
lower cost), but no held candidate meets its registration: (a) and (ab) fail the clean clause and lose right fits on a
1/r² tail, and (b) catches fewer than 10 out of sample and turns the tool red. Nothing lands. The choice is the owner's,
card M2 (`owner-decisions-2026-10-14-ring-sigma-m2.json`, sheet https://claude.ai/artifact/Qz9Ve9QxuzEFjQw7CTN7cQ;
recommended d: register two starts + the floor guard + the seed check, measured on his own cubes first).
