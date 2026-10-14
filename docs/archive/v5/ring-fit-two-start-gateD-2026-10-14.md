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

## Step (ii) — registration (written and committed before any run of the candidates)

**Diagnosis carried** (the step-2 record and step (i)): (1) py4DSTEM's ring-σ start, (ro − ri)/4, ends in a ring-less or
off-centre minimum on noisy flat-background rings, at a higher cost than the true ring (step 1); (2) a start at the ring's
half-maximum width escapes those at a lower cost, but ends in a worse minimum than HEAD's on a 1/r² tail with noise (step 2,
RF2: a's cost above HEAD's in 19 of 20); (3) a fit whose ring σ ends at its 0.25 px floor carries no ring (half of HEAD's
synthetic failures; on real data Au_ref A4 and Ni65Cu35 R3); (4) a fit can leave the ring the conic found (Au_ref W4, +72 %;
the trap set's neighbours).

**The candidates as built** (`step-ii/candidates/`: one `master.swift` with marked blocks, `gen.py` writes each variant;
`core-<v>.diff` against `EllipseCalibration.swift` at `8526d396`, unchanged since `5ddec30d`). Every variant moves
`fitAmorphousRing`'s refinement, robust refit and acceptance checks into one `refine(start)`; `none` (no candidate block)
is that move alone, and on Au_ref's 8 annuli it prints HEAD's numbers digit for digit.
- **c, two starts:** refine from py4DSTEM's start and, when the half-maximum estimator of step 2's (a) returns a width that
  differs, from that width too; each through every acceptance check; keep the passing fit with the lower cost on the same
  pixels (the normalised residual); when neither passes, the first start's error.
- **b2, the floor guard:** step 2's (b) inside `refine`: a ring σ ≤ 0.30 px is refused (`ringWidthAtFloor`).
- **s, the seed check:** a fit whose mean radius left the conic seed's by more than **8 %** is refused (`ringLeftSeed`).
  The threshold was set from step 2's logged rows before any run (`step-ii/seeddist-out.txt`): right fits move at most
  5.4 % (p99.9 5.4 %), and at 8 % 0 of 2806 right and 319 of 479 wrong fits are flagged — in-sample, so S3, S4 and the real
  sources are its out-of-sample test.
- **cb, cs, cbs:** the combinations; the guards act per start, before the cost comparison.

**Sets** (as step 2, same plants): A, B, C (275 each: noisy, clean, printed, refusal tiers), P (Poisson, 480), N (narrow,
280), T (traps, 256), S3 (tails × noise, 120), S4 (tails, 48); one harness for all (step 2 RF2's `rf2`, default-argument
`fitBestAvailable`, the manifest's guess and annulus), variants head, a, b, none, c, b2, s, cb, cs, cbs. Real sources: step
(i)'s five plus Au_ref with the step (i) harness. `tools/ellipse-calibration-test` per variant. "Wrong" > 1 % in (a + b)/2,
"right" ≤ 0.1 %, "right lost" = right under HEAD and not under the variant; b/a error > 0.01 is what the app applies.

**Predictions** (any one failing is recorded, not amended; ADR 050):
- Q0 (the refactor): `none` equals HEAD, and `b2` equals step 2's (b), row for row on every set.
- Q1 (c): over the 2009 plants, wrong ≤ 90 (projection 80; HEAD 414, a 135), right lost ≤ 10 (projection 5, of which 4
  right-by-luck trap fits), newly wrong ≤ 5; on the S3 and S4 1/r² tiers wrong ≤ 3 (a: 25) and right lost ≤ 2; every set's
  wrong count within 5 of the projection's. On the real sources c changes no model and moves no fit by more than 0.02 in b/a.
- Q2 (b2): refuses no right fit on any set; on the real sources it refuses exactly Au_ref A4 and Ni65Cu35 R3.
- Q3 (s): refuses no right fit on any set (0 of the in-sample 2806; ≤ 2 on S3 + S4); flags ≥ 60 % of HEAD's wrong fits; on the
  real sources it refuses Au_ref W4 and A4 and no annulus whose HEAD fit is unflagged.
- Q4 (cbs): wrong ≤ c's; right lost ≤ c's + 2; b/a > 0.01 on fewer plants than any other variant; on the real sources it
  refuses Au_ref A4, W4 and Ni65Cu35 R3 and changes no other annulus by more than 0.02 in b/a.
- Q5 (the tool): `ellipse-calibration-test` passes under none and c; under b2, s and cbs it fails `grains_12_one_annulus`
  (both starts end ring-less or far from the seed, the conic is over its cap, the Fit refuses) — the expectation that ADR
  068 returns to the owner.
- Q6 (fixture, gate copies only, red on HEAD where stated): a test for c (the step-2 dead and drift plants within 1 %, plus a
  plant with a 1/r² tail on which HEAD is right and (a) is not — red under (a) only), red on HEAD on exactly the two noisy
  methods; a test for s (both noisy plants fall back to the conic naming the seed); b2 keeps step 2's test-b. unit + core
  green for none, c, b2, s and cbs, each total = the copy's `func test` count.

**Then:** a fresh refuter; and, because a landed candidate changes the owner's numbers (Au_ref, Ni65Cu35), a card before
anything lands (ADR 068).

## Step (ii) — results (2026-10-14; `step-ii/runs/` — logs, `analyse_ii.py`, `analysis-ii.txt`, `extra-ii.txt`; `step-ii/G/`; `step-ii/real/`)

Every variant ran on all 2009 plant rows through one harness (80 runs, every exit 0; the rows are 1747 distinct plants, since A, B and C share their 131 non-noisy plants); the real sources with step (i)'s harness.
`none` and `b2` equal HEAD and step 2's (b) on every row, so their logs are not repeated here.

| over 2009 rows | HEAD | a | b2 | s | c | cb | cs | cbs |
|---|---|---|---|---|---|---|---|---|
| wrong (> 1 %, any model) | 414 | 135 | 251 | 181 | 80 | 79 | 48 | 50 |
| right (≤ 0.1 %) | 1401 | 1773 | 1468 | 1452 | 1830 | 1814 | 1830 | 1815 |
| right lost against HEAD | — | 62 | 6 | 0 | 5 | 11 | 5 | 11 |
| accepted with b/a off > 0.01 | 319 | 85 | 225 | 132 | 58 | 59 | 40 | 40 |
| refused (the Fit throws) | 19 | 19 | 20 | 32 | 19 | 19 | 28 | 28 |

- **Q0 held:** `none` = HEAD and `b2` = (b), row for row on all 2009 plants and all six real sources.
- **Q1 (c) held:** 80 wrong, 5 right lost (4 the trap set's right-by-luck fits, 1 Poisson to 0.1–1 %), 3 newly wrong; 0 wrong
  and 0 lost on the 96 plants with a 1/r² tail ((a): 25 and 36); identical to the projection on every row of every set. On
  the real sources only sub-pixel moves (≤ 0.13 px, ≤ 4e-4 in b/a), and it kept HEAD's fit where (a) alone moved S4 R3w.
- **Q2 (b2) not held:** it refuses 19 right fits, all in N — rings point-sampled at σ 0.25–0.30 px, which step 2's refuter
  had already found and this registration missed (pixel-integrated narrow rings: none). On the real sources it refuses
  exactly Au_ref A4 and Ni65Cu35 R3, as predicted.
- **Q3 (s) held as worded, and refuted on real data:** 0 right fits refused on any set (S3, S4 included); it changes 268 of
  HEAD's 405 wrong profile fits (66 %); at step (i)'s annuli it refuses exactly Au_ref A4 and W4. But the refuter shifted the
  Au_ref annuli by up to ±2 px (726 annuli, a truth-free check): the conic seed swings 9.1–11.5 px on ring A1 while the
  profile fits agree at 10.24–10.65 px (b/a 0.968–0.978), and s refuses 14 more annuli, 9 of them on fits that agree with
  their neighbours — final refusals, because those conics are over the 0.2 fallback cap. On a separate 50-annulus grid this
  session saw 9 (A1 5 of 16, W3 4 of 25; `step-ii/shift/`), 8 on agreeing fits. A check gated on the conic's own residual
  (≤ 0.2) keeps 255 of 268 synthetic catches and none of those refusals, in a re-reading of the logs only: a new idea.
- **Q4 (cbs) partly:** 50 wrong (≤ c's 80) and refusals of exactly Au_ref A4, W4 and Ni65Cu35 R3 on the real sources, nothing
  else beyond c's sub-pixel moves; but 11 right lost (> c's 5 + 2: the 6 N rings of Q2, the 4 trap fits, 1 Poisson) and b/a
  off > 0.01 on 40 plants, tied with cs rather than fewer.
- **Q5 not held for cbs:** the tool passes under cbs. On `grains_12_one_annulus` the half-maximum start ends ring-less
  (I1 = 0, σ 3.8 / 4.5 px, a = b = 50.2 against the plant's 41.2); its σ are live and the conic seed is itself near 50, so
  neither guard sees it, and b/a is exact on an isotropic pattern. none and c pass; b2 and s fail on that case, as predicted.
- **Q6 held** (lane G, gate copies only): head-c 2233 / 2 / 4 and head-s 2232 / 2 / 4 (exit 65, exactly the new noisy
  methods), a-c 2234 / 1 / 4 (exactly the new 1/r²-tail plant: (a) +2.34 %, HEAD −0.0023 %), c and cbs 2235 / 0 / 4, s
  2234 / 0 / 4, b2 2233 / 0 / 4, none 2232 / 0 / 4; core 0 each; every total = the copy's `func test` count.
- **New refusals:** cbs refuses 9 Poisson plants HEAD answered; all 9 HEAD fits were 10–33 % off in R and 0.17–0.57 in b/a.
- **Cost per click:** two starts take 31 → 51 ms per annulus on the WS2 map and 43 → 48 ms on Au_ref.
- **cb (two starts + the floor guard):** 79 wrong, 11 right lost (the 6 point-sampled N rings, the 4 trap fits, 1 Poisson),
  b/a off on 59, no new refusal anywhere; on the real sources it refuses exactly Au_ref A4 and Ni65Cu35 R3 and moves the WS2
  fits sub-pixel; none of the shifted Au_ref annuli is refused. Gates (gate copy, with lane G's test-c): unit **2235 / 0 / 4 = 2239** = `func test`, all three new methods green;
  core 0; `ellipse-calibration-test` all passed (`grains_12` fits isotropic through the half-maximum start's ring-less fit)
  (`step-ii/CB/`).
- **cs against cbs:** cs has the fewest wrong (48) and refuses no right fit anywhere, but keeps the real Ni65Cu35 R3 dead ring
  (b/a 0.947 against the conic's 0.989); cbs refuses it, at the cost of 6 synthetic sub-pixel point-sampled rings.
- **Residuals no candidate catches:** a ring-less fit with live σ near its seed (`grains_12` under cbs), and a ring σ at its
  ceiling inside the annulus (Au_ref W3, WS2 map R1/R2 — none a b/a outlier).
- **Refuter (RF3, Sonnet, fresh; `step-ii/RF3/report.md`):** its own harness and builds reproduce every set's rows and all 36
  real-source logs byte for byte. c UPHELD WITH CORRECTIONS (lower cost is not closer in 31 of 557 materially different
  pairs; 3 plants HEAD had within 1 % end outside it; on gapped 1/r² tails at ≤ 20 counts c is no better than HEAD, 16 vs
  14 wrong); b2 UPHELD WITH CORRECTIONS (the 19 point-sampled refusals, conic within 1.1 % and 0.005 in b/a; a ring-less fit
  with σ > 0.30 escapes; its message names the 0.25 px floor for a 0.30 px test); s REFUTED as registered (above); cbs UPHELD
  WITH CORRECTIONS only with s gated or dropped (it inherits s's refusals; in 8 Poisson plants a refused start hands the choice
  to a worse second start; a constructed edge-clipped ring is accepted ring-less).

**Outcome.** c and b2 hold their evidence with corrections; s does not survive real data as registered; cb — two starts and
the floor guard, registered as a combination and run on every set — is the candidate that helps on the synthetic sets and on
the owner's patterns without a refusal of a right real fit. Nothing lands before card M3.
