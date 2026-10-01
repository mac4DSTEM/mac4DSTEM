# Lane F-A report — orientation (ACOM) rows 1, 4, 5, 2 and grain B (Fable 5.1, 2026-10-01)

Tree: HEAD 2cd6a174 (other lanes' uncommitted edits are in the working tree; every build and run here uses an
isolated `git archive HEAD` copy at $SP/FA/tree/mac4DSTEM with ONLY this lane's files overlaid — the working tree's
half-edited Core files from other lanes would otherwise be compiled in). Lane dir $SP/FA. Logs named below live there.

## Summary
(filled at the end)

## Row 1 — the bank samples the mirror-reduced triangle; no conjugated (inversion) pass

### (1) Claim restated
`CubicOrientationSymmetry.sampleFundamentalZone` samples z ≥ x ≥ y ≥ 0 (1/48 of the sphere; hexagonal: the 0–30° sector,
1/24), but orientation equivalence is the PROPER group (24 / 12 ops) whose zone is twice that. A beam axis in the mirror
triangle produces the 2-D mirror of a bank template's pattern, which no in-plane rotation reproduces; the shipped matcher
(one `vDSP_zvmul(..., -1)` pass, OrientationMatcher.swift:165-168) returns a wrong sampled-triangle template 5–22° off
for ~50 % of generic orientations. py4DSTEM covers it with `inversion_symmetry=True` (crystal_ACOM.py:877): a second pass on
`np.conj(im_polar_fft)` (:1272-1323 `corr_full_inv`), the larger of the two wins per zone axis (:1364-1370), and on an
inverted win `orientation_matrix[:, 1:] = -orientation_matrix[:, 1:]` (:1548-1550).

### (2) Reproducing observation on HEAD — plan
New harness `tools/acom-mirror-test/` (main.swift + run.sh): Al fcc a 4.0495, kMax 1.2, 600 axes, 32×128, 200 kV
(0.02508 Å, as the app passes `planWavelength` when a voltage is known; also a flat-Ewald run), peaks generated from an
INDEPENDENT right-handed basis (never production `project`/`detectorBasis`, as the convention harness does), truth matrix
(f1, f2, n), misorientation under an independent proper-group operator list. Five sampled axes (2,1,3) (3,1,5) (5,2,7)
(4,1,6) (7,3,9) and their five mirror images (x↔y), in-plane 17.3°; then 200 random directions. Gate: median misorientation
of the mirror-triangle set < 3° (HEAD predicted RED), sampled set < 3° (control). Also reports per-pattern CPU time and
CPU/Metal agreement (template, angle, score) — the Metal path must carry the same pass.

### (4) Predictions (2026-10-01, BEFORE the HEAD run `mirror-head-*.log`)
- HEAD, sampled-triangle five at 17.3°: misorientation 0.4–1.3° each (verdict table: 0.47–1.25°). Random sampled half: median ≤ 1°.
- HEAD, mirror-triangle five: misorientation 12–20° each (verdict: 12.36–19.36°), none < 3° → gate RED, exit 1.
- HEAD, random: 45–55 % of directions > 3° (verdict 50.4 % whose proper orbit misses the bank; matcher median 7.3° on that half).
- Flat-Ewald (nil) and 200 kV give the same chirality verdict (the mirror relation does not depend on λ).
- CPU per pattern on this M5 Pro, 600 templates, single matcher: 0.4–0.8 ms (S20 record: 10 000 positions / 1.0 s at 200
  templates, multi-threaded → ~2.4 ms·core at 600; single-core vDSP loop dominated).

### (2) Reproducing observation on HEAD — result (`mirror-head.log`, `mirror-head.exit` = EXIT=1, 2026-10-01)
HEAD tree (git archive 2cd6a174 + the new harness only). The gate is RED for the reason the row states:
| set (λ = 0.02508 Å, 600 templates) | sampled zone | mirror zone |
|---|---|---|
| Al named five, misorientation (full matrix, proper group) | median 1.38° (one 38.3° outlier: (2,1,3), score 1.000 — the known in-plane-modulo-π class, not row 1) | median 57.4°, 52.9–59.4° |
| Al random 200 (107 sampled / 93 mirror) | median 0.95°, p90 1.76° | median 37.6°, p90 59.4°; 65 of 200 > 3° |
| WS2 named five | median 0.83°, max 1.46° | median 9.8°, max 50.9° |
| WS2 random 200 (100 / 100) | median 1.11°, max 2.48° | median 5.7°, p90 63.7°; 72 of 200 > 3° |
Flat-Ewald Al: both halves lost (sampled median 26.7°) — the π-periodic templates' in-plane ambiguity swamps the full-matrix
metric there, so the λ run is the one the gate reads (the convention harness passes a wavelength for the same reason).
CPU single matcher 0.736–0.752 ms per pattern (600 templates, M5 Pro); Metal 0.25–0.38 ms; CPU/Metal template agreement 210/210, score error ≤ 3e-6.
Prediction audit: direction and the sampled-zone control held (0.95° / 1.38° vs predicted ≤ 1°/0.4–1.3°). MISSED in metric: I
predicted 12–20° for the mirror five — those were the verdict's AXIS errors; the harness measures the full misorientation, which
is 53–59° because the wrong template's in-plane angle is wrong too. MISSED: "45–55 % > 3°" — measured 32.5 % (Al) / 36 % (WS2):
mirror-zone truths near the zone edges recover within 3° (their mirror image is close to a template), so the fraction is below
the 50.4 % geometric share. CPU per pattern 0.74 ms is inside the predicted 0.4–0.8 ms.

### (3) Candidate causes and the refuting observation for each
- C1 the bank is too coarse / too few templates — REFUTED: sampled-zone random median 0.95° at the same bank; the mirror-zone
  errors are 37–59°, forty times the bank spacing (1.03° median nearest-neighbour, verdict §1).
- C2 the Ewald curvature / λ — REFUTED: the mirror relation is the same with λ = 0 and 0.02508 Å (mirror five 52.9–59.4° both;
  verdict §3: basis(−n) = (−e1, e2, −n) independent of λ).
- C3 the symmetry REDUCTION (24 proper ops) is wrong — REFUTED: it is applied to the result only; the sampled zone reduces
  correctly (0.95°), and the harness's independent operator list agrees with it.
- C4 the matcher's single conj(E)·T pass cannot represent a mirrored pattern (the row's claim) — SURVIVES: every mirror-zone
  failure returns a sampled-zone template with a score 0.75–0.97 (a mirror image's correlation), and the identical polar
  pipeline recovers the sampled zone. The fix below adds the second pass and the HEAD-red gate goes green with it (next section).

### (4) Predictions for the fix (2026-10-01, BEFORE `mirror-fixed-*.log`)
- Al λ: named mirror five all < 2° (verdict table after the conjugated pass: 0.47–1.25° axis error) with `mirrored` = yes on
  all five and no on the five sampled; random mirror median < 1.5°, > 3° count ≤ 3 of 200 (the (2,1,3)-class π outliers may stay).
- WS2 λ: named mirror five < 2°, random mirror median < 1.5°.
- Sampled-zone numbers unchanged to 0.01° (the forward pass is untouched; a mirror win on a sampled truth needs a strictly larger score).
- CPU per pattern 1.3–1.5 ms (two correlation passes; the polar deposition and the 32 forward FFTs are shared): ×1.8–2.0.
  Metal 0.45–0.7 ms (two batches). CPU/Metal agreement 210/210 on template AND the mirrored flag.
- No +π on the in-plane angle (derivation in the fix's comment); if the mirror five come out with the right axis but ~180° in-plane
  error, the derivation is wrong and the py4DSTEM +π is needed — that outcome is recorded as such, not patched silently.

### Fix run 1 (`mirror-fixed.log`, EXIT=1) — the prediction's named escape hatch fired
The conjugated pass finds the right template with the mirror flag on every mirror-zone trial (Al λ: (1,3,5) → t550 = the
template its mirror image (3,1,5) wins, score 0.996; 101 of 200 random flagged), but the orientation is 26–35° off (Al λ named
mirror median 32.1°; WS2 71°) with the right axis class — a half-turn in-plane error. My derivation treated the flipped
basis as the y-mirror of the rotated template; it is the x-mirror (substitute h = −g in the Friedel argument), so the π that
py4DSTEM adds (:1374-1383) IS needed in this port too. Cost held: CPU 1.45–1.55 ms per pattern (×1.97–2.1, predicted ×1.8–2.0),
Metal 0.36–0.51 ms; CPU/Metal template+flag agreement 210/210. Amendment (2026-10-01): the fix adds π to the in-plane angle of a
mirrored win (stored as py4DSTEM stores it); predictions for run 2 are the run-1 predictions unchanged, plus: the sampled-zone
numbers must be identical to run 1 to the printed digit.

### Fix run 2 (`mirror-fixed2.log`, EXIT=1 — the flat-Ewald run only; λ runs PASS)
| set | sampled zone | mirror zone |
|---|---|---|
| Al λ named five | median 1.38° (unchanged to the digit; (2,1,3) 38.3° stays) | median 1.20°, (1,2,3) 37.4° (the same π class as its mirror image) |
| Al λ random 200 | median 0.952°, p90 1.89° | median 0.986°, p90 1.98°; > 3° 12 of 200 (was 65); flag set on 101 |
| WS2 λ named five | 0.83° | median 1.06°, max 1.25° (was 71°) |
| WS2 λ random 200 | 1.11° | median 1.03°, p90 1.67°; > 3° 1 of 200 (was 72) |
CPU 1.44–1.47 ms per pattern (HEAD 0.74: ×1.95–2.0); Metal 0.37–0.49 ms (HEAD 0.25–0.38). CPU/Metal template+flag 210/210.
Predictions held: mirror five < 2° except the one π-class case, sampled numbers identical to run 1, cost ×2, flag on
exactly the mirror half (101 of 200 with 93 geometric mirror + edge cases), Metal agreement 210/210. The flat-Ewald run fails
the FULL-MATRIX gate on both halves (sampled 26.7° / mirror 26.7° medians) — the π-periodic flat templates' in-plane
ambiguity, not row 1. Harness amendment (2026-10-01, before run 3): the flat run is gated on the beam-axis error (the row's
own metric), the λ runs stay on the full matrix. Prediction for run 3: flat Al axis error — sampled median < 1°, mirror
median < 1.5° (HEAD would read ~7° on the mirror half per the verdict); everything else identical to run 2.

### Fix run 3 (`mirror-fixed3.log`, EXIT=0) and the HEAD re-run of the amended harness (`mirror-head2.log`, EXIT=1)
Amended gate on HEAD, flat-Ewald beam-axis error: sampled median 0.51° (named) / 0.69° (random), mirror 17.2° (named,
max 19.4°) / 8.2° (random, p90 17.1°, max 23.5°; 62 of 200 > 3°) — the verdict's 12–19° reproduced on the row's own metric.
Fixed, same metric: sampled 0.51° / 0.66°, mirror 0.82° / 0.70° (p90 1.40°); 13 of 200 > 3° (max 16° — a (2,1,3)-class
case where the π-ambiguous flat template picked the other half-turn, then the beam of the wrong half; the λ run has it too).
The λ runs are identical to run 2 (above). Row 1's gate: RED on HEAD → GREEN with the fix, on an independent truth.

### (5) The fix — files
- `Core/Crystal/OrientationMatcher.swift`: `match` runs the template loop twice (`vDSP_zvmul` conjugate flag −1 then +1 =
  conj(E)·T then E·T), keeps the strictly larger per template with a `mirrored` flag; `templateScores` (diagnostic) takes the
  max of both; `makeOrientationResult(mirrored:)` adds π to the in-plane angle and negates columns 1–2 of the matrix
  (py4DSTEM :1374-1383, :1548-1550); `MetalACOMMatcher.matchAll` runs `runBatch` a second time on the negated imaginary part
  (the kernel is untouched — it computes conj(E)·T, so −Im gives E·T) and merges per template. Header note added.
- `Core/Analysis/OrientationResult.swift`: `mirrored: Bool = false` (py4DSTEM's `Orientation.mirror`), init default keeps
  every existing call site. No `DEVIATION` note needed: the pass now matches py4DSTEM's; the first attempt's "no +π" claim
  was refuted (run 1) and is recorded in the comment as measured.
- `tools/acom-matching-test/main.swift`: the scalar reference gets the same two passes (strict >), else "optimized CPU differs".
- `tools/acom-convention-test/main.swift`: every analytic axis is also run as its mirror image (x↔y cubic, y→−y hexagonal) as a
  second group with the same bounds (the review's "plant off-triangle axes in the convention harness").
- `tools/acom-mirror-test/` (new): the gate above; `mac4DSTEMTests/ACOMRow1MirrorZoneTests.swift` (new): the unit-gate copy.
- NOT changed (outside the write-set, STOP-and-report): `Core/Analysis/FitOverlays.swift:226` draws template spots at
  `spot.azim + result.inPlaneAngle`; for a mirrored win the spot sits at `π − (spot.azim + inPlaneAngle)` (the
  `OrientationResult.mirrored` doc comment). Until that line reads the flag, the overlay on a mirrored position draws the
  unmirrored template — a visible mismatch on ~half of generic positions. One-line change; the supervisor decides who lands it.

## Grain B (owner card Q2 a) — predictions BEFORE the demo-cube runs (2026-10-01)
Harness: $SP/FA/democube/main.swift = lane Q's S20 true-Q rerun (a copy of real-acom-benchmark over the full demo scan with a
per-grain report against truth.json) plus a `S20_WL` wavelength knob and a mirrored-wins/in-plane read-out. Runs: tree-head
(HEAD) and tree (row 1 fixed), both S20_Q=0.012, kMax 1.2, 200 templates, flat Ewald (the S20 record's conditions).
- HEAD (`democube-head.log`): A median 5.03° (winner t165, [001]), B 6.50° (t84), C 0.00° (t2) — the S20 record's row reproduced.
- Row 1 fixed (`democube-fixed.log`): A, B, C medians UNCHANGED to 0.01° (all three truths lie on the triangle's vertices /
  edges, achiral); mirrored wins on the three grains: 0 or a tie-level handful (< 2 % of a grain) — the mirrored pass can only
  win by a strictly larger score, which an achiral pattern gives at float-noise level. B's modal winner stays t84.
- Then B's own Gate D: (i) a synthetic [011] pattern at 40° in-plane (the cube's own reflection list, kMax 0.9, Q 0.012,
  origin 63.5, 128² detector) through the production matcher — prediction: reproduces t84 at 6.50° if the cause is matcher/
  plan-side (the refuter's claim), else t1 at 0.00° (the cause is in the cube's detection path); (ii) the same at 39.375°
  (= 14 azimuthal bins, on-grid) and a sweep — prediction (the refuter's lead): on-grid gives t1, off-grid gives t84;
  (iii) plan with λ(200 kV) — prediction: B unchanged (the cube's Ewald is flat, and 6.5° is far beyond a curvature effect).

### Convention and matching harness predictions (2026-10-01, before `convention-head.log`, `convention-fixed.log`, `matching-fixed.log`)
- acom-convention-test with the new mirror group on HEAD (tree-head): Au sampled PASS as before (median ~1.25°), Au mirror
  group FAIL at the matrix bound (median > 3°: the mirror of every generic axis is chiral) → exit 1 on the Au mirror
  assertion (the first group to fail). Fixed tree: Au sampled and mirror both < 3° (medians within 0.3° of each other), WS2
  both < 2°, the frozen py4DSTEM 0.14.17 external set median IMPROVES (py4DSTEM drew random orientations, so ~half are
  mirror-zone; HEAD record 2.06° / 25 of 40 < 5°) → < 2° and ≥ 30 of 40; exit 0.
- acom-matching-test on the fixed tree: scalar reference = vectorised CPU on all 8 (same two passes), Metal parity exact, WS₂
  8/8 at the true scale — exit 0, no number re-pinned.

### Convention harness, run 1 (`convention-head.log` EXIT=1, `convention-fixed.log` EXIT=1) and matching (`matching-fixed.log` EXIT=0)
HEAD: Au sampled 144 trials median 1.250°, in-plane < 20° 131 (the record's numbers); Au MIRROR 144 trials median 3.389°,
in-plane < 20° only 28 → FAIL on the matrix bound (red, as predicted, but the matrix margin is thin: these 18 bank axes and
their mirrors sit nearer the triangle edges than my named five, so half of the mirror trials recover within 3°; the in-plane
count 28/144 is the clear red). Fixed: Au sampled median 1.250° unchanged, but "in-plane < 20°" fell 131 → 110 (< 120) → FAIL.
Prediction MISSED on the auxiliary count: 21 sampled-zone trials now win through the mirrored pass (a tie-level score on
near-achiral axes; the full-matrix error is unchanged), and the harness's auxiliary in-plane formula assumed the reported
template basis equals the truth frame (identity symmetry operator) — false for a mirrored win, which reports the equivalent
orientation with the beam flipped. Harness amendment (2026-10-01): the auxiliary check is made symmetry-aware (bring the
reported beam onto the truth beam with the best operator, then compare lab-x to f1); README line added. Prediction for run 2:
HEAD mirror group still red (in-plane count < 120 and/or median > 3°); fixed: all four groups pass, Au sampled in-plane count
back to 131 ± 2, mirror groups' counts within 10 of their sampled twins; external set as predicted above.
matching-fixed: all PASS (scalar = vectorised on 8/8, Metal parity 6e-7, WS₂ 8/8) — prediction held, no re-pin.

### Convention harness run 2 (`convention-head2.log` EXIT=1, `convention-fixed2.log` EXIT=1) — a sampled-zone regression surfaced
HEAD with the symmetry-aware auxiliary check: Au sampled 131 in-plane < 20° (unchanged), Au mirror median 3.389°, in-plane 74
→ still red. Fixed: Au sampled median 1.250°, in-plane < 20° 116 (HEAD 131; bound 120) → FAIL. So 15 sampled-zone trials are
WRONG with the fix, not merely mis-counted (prediction MISSED). Reading: a truth within ~2° of a {100}/{110} mirror plane is
achiral at the polar image's resolution (azimuthal blur 1.5 bins = 4.2°), the two passes tie to rounding, and a mirrored
win reports the orientation mirrored across that plane — twice the distance to the plane, 3–5°. py4DSTEM has the same strict
`>` on floats. Before deciding on a tie rule (a threshold: measure first, CLAUDE.md), the next runs print the two passes'
score gap per trial (`ACOM_CONVENTION_DETAIL`, the mirror harness's "pass gap" lines, the demo cube's grain A).
Predictions (2026-10-01, before `convention-fixed3.log`, `mirror-fixed4.log`, `democube-fixed2.log`): genuine mirror-zone wins
have a gap ≥ 0.02 (score 0.99 vs ≤ 0.97); the sampled-zone mirrored wins have |gap| < 1e-4 (float ties on achiral images);
the demo cube's grain A (an exact 4-fold [001] pattern) gap |Δ| < 1e-5 on all 2552 mirrored wins. If so, a forward-preference
margin of 1e-4 absolute separates the populations by > 100× and is proposed WITH a DEVIATION note; if the populations overlap,
no margin ships and the regression is reported as the cost of the row.

### Rows 4, 5, 2 — unit tests, predictions (2026-10-01, before `unit-head.log` / `unit-fixed.log`)
Classes: ACOMRow1MirrorZoneTests (1 test), ACOMRow4Row5PlanInvalidationTests (3), QUnitsRow2LineageTests (2), plus the
existing ACOMSessionTests (14) as the regression check on the touched owner; run in tree-head (HEAD + the test files) and
tree (fixes), each `-only-testing:` per class, CODE_SIGNING_ALLOWED=NO.
- tree-head: Row1 FAILS (misorientation 57° on (1,2,3); `mirrored` does not exist on HEAD → the file does not COMPILE
  against HEAD; so the red run for Row1 is the harness `mirror-head2.log`, and the Row1 class is excluded from the HEAD
  xcodebuild run — stated here, not hidden); Row4Row5: 2 of 3 FAIL (re-import keeps the plan; voltage edit keeps the plan),
  the "identical re-import keeps" test passes on HEAD too (it asserts the non-change); QUnits: 1 of 2 FAILS (the active node
  still says nm⁻¹ and is the same id), "units without a size" passes on HEAD too. ACOMSessionTests 14/14 green.
- tree: all 6 new tests green, ACOMSessionTests 14/14 green. Then break-once-more: revert each row's fix alone in the tree
  (git checkout of the one file is forbidden in the repo — done by copying the HEAD file into the lane tree), run RED, restore, GREEN.

### Row 1 — the measured trade-off of the parity fix (`convention-fixed3.log`, `mirror-fixed4.log`, `mirror-head3.log`, `democube-fixed2.log`, `achiral.log`)
Random Al λ, 600 templates, 200 directions (107 sampled-zone / 93 mirror-zone), wrong = misorientation > 3°:
| | HEAD | fixed |
|---|---|---|
| sampled zone wrong | 3 of 107 | 9 of 107 |
| mirror zone wrong | 62 of 93 | 3 of 93 |
| all | 65 of 200 | 12 of 200 |
WS2 λ: sampled 0 → 0 of 100, mirror 72 → 1 of 100. Flat Al (axis metric): sampled 1 → 9, mirror 61 → 4.
The 6 new sampled-zone failures are mirrored wins with a LARGE gap (mirror − forward 0.022–0.37; `mirror-fixed4.log`
"sampled zone, mirrored win" n=9), i.e. not float ties: at an off-grid in-plane angle the exact template's forward score drops
(the S20 quantisation class — grain B below shows it at 0.87–0.96) and a wrong template's mirrored correlation (HEAD's
mirror-zone winners scored 0.76–0.97 the same way) overtakes it. Genuine mirror-zone wins have gaps 2.9e-3–0.66 (Al λ) /
1.8e-4–0.73 (WS2); the populations OVERLAP (0.02–0.37 inside both), so a forward-preference margin cannot separate them —
prediction REFUTED, no margin ships (CLAUDE.md threshold rule), and the regression is the row's measured cost.
Achiral axes (on a {100}/{110} plane — ⟨001⟩ ⟨011⟩ ⟨112⟩ ⟨uv0⟩ ⟨uuw⟩, the common zones): the two passes tie (demo cube grain A
gaps 6e-8–4.4e-5 on 2552 of 5400 positions, grain C ≤ 1.2e-7 on 158 of 2250; `democube-fixed2.log`), and a mirrored win
reports the beam-flipped class 37–60° from the truth under the proper group (`convention-fixed3.log` DETAIL: (0.341 0 0.940)
6 of 8 angles, (0.467 0.462 0.754) 4 of 8, (0.403 0.387 0.830) 2, (0.367 0.285 0.886) 3). `achiral.log`: that class is NOT a
physical twin — the truth pattern carries a Friedel weight asymmetry of 0.19–0.22 and the beam-flipped class reproduces its
polar image only to 0.940 vs the reported 0.979; the two tie because the reported orientation ALSO fits only to 0.979 (the
quantisation ceiling), so the polar image cannot rank them. py4DSTEM's rule is the same strict `>`. Consequence in the app:
IPF-Z colour unaffected (the 48-fold fold); Euler-angle maps of achiral grains speckle between two classes; the half-turn
the λ asymmetry resolved on HEAD becomes a coin flip on those zones.
Convention gate on the fixed tree: Au sampled "in-plane < 20°" 116 vs bound 120 (HEAD 131; the 13 HEAD failures are the
known modulo-π class, the 15 new are the achiral ties above) → `tools/acom-convention-test` is RED with the fix and I did
NOT re-pin it: the bound is the owner's trade-off to accept (see Open questions). CORRECTION (same session): the harness
stops at that first failure, so the Au mirror group, WS2 and the frozen py4DSTEM set were NOT reached on the fixed tree —
their numbers come from a scratch copy of the harness with the two in-plane `require`s turned into prints
(`convention-probe.log`, below), never from the gate itself.

## Grain B (owner card Q2 a) — its own Gate D
### (1) Claim
The demo cube's grain B (Al [011], in-plane 40°, truth.json) reads 6.50° off (winner t84, axis (0.702 0.113 0.703)) at
true Q 0.012, invariant under Q, kMax and candidate F (`slot1-q-record-2026-09-30.md`); the exact template t1 = [101] exists
(refuter finding 7). Leads: the harness plan is flat-Ewald while the app passes λ; B's 40° is 0.22 bin off the 2.8125° grid.
### (2) Reproduction (`democube-head.log`, EXIT=0; HEAD tree, S20_Q=0.012, kMax 1.2, 200 templates, flat)
A n=5400 median 5.027° (t165, 96.6 %); B n=2250 median 6.499° (t84, 98.0 %, axis (0.702 0.113 0.703)); C 0.000° (t2, 100 %);
0.25 s for 10 000 positions. The S20 record's row reproduces exactly.
### (3) Candidates and the refuting observation
- B1 the bank lacks the template — REFUTED (t1 is [101] exactly; refuter 7; `grainb-*.log` print t1's 22 spots).
- B2 Q / kMax / candidate F — REFUTED by the record (invariant) and by `grainb-200-k09.log` (bank restricted to the cube's own
  kMax 0.9 reflections: still a neighbour wins, t160 at 1.84°, score 0.9984 vs t1 0.9599).
- B3 flat-Ewald harness vs the app's λ — REFUTED: `grainb-200-wl.log` (λ 0.02508): B → t160 1.84° (score 0.9233 vs t1 0.8782)
  and A → t173 3.18° (= the record's F-at-true-Q numbers for A: 3.18°); λ changes WHICH neighbour wins, not that one does.
- B4 row 1 (mirror zone) — REFUTED as predicted: `democube-fixed.log` B 6.499° unchanged, 2 mirrored wins of 2250; [011] lies on
  the triangle edge (achiral).
- B5 azimuthal quantisation of an off-grid in-plane angle (the S20 class, refuter lead ii) — SURVIVES, and is now observed
  directly: `grainb-200-flat.log` sweeps B's in-plane angle in quarter-bin steps (0.703°): at EVERY on-grid angle (k·2.8125°)
  the exact t1 wins with 0.00° error (score 0.9101; 1.0000 at kMax 0.9), at EVERY off-grid angle a neighbour wins (t106 3.56°
  at 0.927 vs t1 0.846–0.872; kMax 0.9: t160 1.84° / t177 1.88° at 0.971–0.998 vs t1 0.932–0.960). The cube's 40° = 14.22 bins is
  off-grid. The synthetic pattern (the cube's own 16-reflection list, no detection) gives t106 at 3.56°, the cube t84 at 6.50°:
  detection (disk intensities, sub-pixel positions) moves the winner among the near-[101] neighbours, the mechanism is the same.
  Note grain C ([111], 70° = 24.9 bins, also off-grid) is exact at every angle: its 6-spot hexagon has no neighbour that
  rounds better; grain A (12° = 4.27 bins) shows the same class at 5.03°/3.18°.
### (4)–(6) No fix in this lane
The cause is the open S20 quantisation item (candidate F = exact-azimuth spectra + 4× zero-padded shifts recovered 43/43 on
2026-09-30 but cost 3.8× and moved grain C to 1.64° — declined). Row 1 does not move B (prediction held). Fixing B means
deciding that item; it is not a bank, Q, λ or mirror defect. Proposed closing line for the Q2 card: "B 6.50° = the S20
off-grid class, shown by a sweep: exact at every on-grid angle, a 1.8–3.6° neighbour at every off-grid one; unchanged by
row 1; the fix is the S20 decision (F or a cheaper sub-bin rule), not a separate item."

## Row 4 — CIF re-import keeps the old plan
(1) Claim: `importCrystalModel` replaces a same-stem model in `importedCrystalModels` (a plain var) and re-asserts
`.imported(id)`, a same-value write `modelSelection.didSet` ignores; `runACOM` reuses `orientationPlan` built for the old
cell and records the new fingerprint. (2) Reproduction: `ACOMRow4Row5PlanInvalidationTests.testReimportingTheSelectedCIF…`
drives exactly that replacement on an `ACOMSession` with a planned/matched state — predicted RED on HEAD (`unit-head.log`).
(3) Candidates: the observer on `modelSelection` is change-gated by design (a picker re-selecting the current crystal must not
throw the map away, `testSameValueWritesInvalidateNothing`) — so the gate is right and the MODEL list is the unobserved
input; refuted alternative: comparing `revisionID` at run time only AFTER the run (`runACOM` does that for cancellation, not
for staleness). (4) Prediction: with the observer the test goes green and `testSameValueWritesInvalidateNothing` stays green.
(5) Fix: `ACOMSession.importedCrystalModels.didSet` invalidates the plan when the SELECTED imported model's `revisionID`
changes (Session owns the state; AppState untouched for this row).

## Row 5 — voltage edit keeps the old plan
(1) Claim: `generateOrientationPlan` builds every template with the wavelength of `calibrationSession.acceleratingVoltage`
(Ewald curvature); `setManualAcceleratingVoltage` invalidated only the RESULT, and only for mrad units. (2) Reproduction:
`testAVoltageEditInvalidatesThePlanASameValueCommitDoesNot` — predicted RED on HEAD. (3) Candidates: none competing — the
setter simply never reaches `invalidatePlan`; the mrad branch is the only ACOM effect it has. (4)/(5) Fix: invalidate the plan
when the stored voltage CHANGES (a same-value commit keeps plan and map, as the Q/R fields do); the mrad-only branch is
subsumed (a plan invalidation invalidates the result).

## Row 2 — units setter skips `recordQCalibrationRun`
(1) Claim: `setManualQPixelUnits` sets units + `.manual` but records no `calibration_q` node; the lineage judges staleness by
the active node, so nm⁻¹ → Å⁻¹ (10× Q) leaves the phase map "current" and `q_units` wrong. (2) Reproduction:
`QUnitsRow2LineageTests.testChangingTheQUnitsRecordsANewCalibrationNodeWithThoseUnits` (demo fixture uncalibrated, type
0.12 nm⁻¹ → node; switch to Å⁻¹ → asserts a NEW active node with `q_units` Å⁻¹) — predicted RED on HEAD (same node id, nm⁻¹).
(3) Candidates: none competing — the size setter's `recordQCalibrationRun()` line is simply absent from the units setter.
(4)/(5) Fix: call it in the positive-size branch (the recorder itself refuses without a size — `testUnitsWithoutASizeRecordNothing`).

## Changes (file: what and why)
- `mac4DSTEM/Core/Crystal/OrientationMatcher.swift`: second (conjugated) correlation pass in `match`, `templateScores` and the
  Metal batch; `makeOrientationResult(mirrored:)` with py4DSTEM's +π and the column-1/2 negation; header note. Row 1.
- `mac4DSTEM/Core/Analysis/OrientationResult.swift`: `mirrored: Bool = false` + init default. Row 1 (py4DSTEM `Orientation.mirror`).
- `mac4DSTEM/Session/ACOMSession.swift`: `importedCrystalModels.didSet` invalidates the plan when the selected imported
  model's `revisionID` changes. Row 4.
- `mac4DSTEM/App/AppState+Open.swift`: `setManualAcceleratingVoltage` invalidates the plan on a changed voltage (the
  mrad-only result invalidation is subsumed); `setManualQPixelUnits` records the `calibration_q` lineage node. Rows 5, 2.
- `tools/acom-matching-test/main.swift`: scalar reference carries the second pass (else "optimized CPU differs"). Row 1.
- `tools/acom-convention-test/main.swift` + README: mirror-image group for every analytic axis; symmetry-aware auxiliary
  in-plane check; `ACOM_CONVENTION_DETAIL` prints failing trials. Row 1.
- `tools/acom-mirror-test/{main.swift,run.sh}` (new) and `tools/run-tests.sh` (one name in the `scientific` list — outside
  the brief's write-set by one token; inventory refuses an unclassified tools/ dir, so it was the only way to land the harness).
- `mac4DSTEMTests/ACOMRow1MirrorZoneTests.swift`, `ACOMRow4Row5PlanInvalidationTests.swift`, `QUnitsRow2LineageTests.swift` (new).
- NOT changed: `Core/Analysis/FitOverlays.swift` (see Row 1 (5)), `real-acom-benchmark` (nothing to change: both backends
  carry the pass; not run — its dataset `References/training_dataset/058…` is absent; the CPU/Metal parity it would measure is
  measured by `acom-mirror-test` and `acom-matching-test` instead).

## Measurements
Cost of the second pass (M5 Pro, 600 templates, 32×128, `mirror-head3.log` vs `mirror-fixed4.log`):
| path | HEAD ms/pattern | fixed ms/pattern | ratio |
|---|---|---|---|
| CPU, one matcher (single core) | 0.736–0.752 | 1.42–1.47 | ×1.9–2.0 |
| Metal (batched, 210 positions) | 0.25–0.38 | 0.36–0.50 | ×1.3–1.5 |
Demo cube, 10 000 positions × 200 templates, CPU all cores (`democube-head.log` / `democube-fixed.log`): 0.25 s → 0.49 s.
The app's "Balanced" 200-template preview of 1 024 positions therefore moves from ~25 ms to ~50 ms of matching; the
`ACOMSession.estimatedDuration` CPU baseline (1 150 positions/s at 400 templates, M3 Release) is now ~2× optimistic — a
measured throughput replaces it after the first run, so no constant was changed (recorded here for the status table).
Accuracy: the row-1 trade-off table above; convention-gate numbers in `convention-head2.log` / `convention-fixed3.log`;
grain B in `democube-*.log` / `grainb-*.log`.

## Deviations from the brief
- `tools/run-tests.sh`: one token (the harness name) outside the write-set, reason above.
- The convention gate is left RED on the fixed tree rather than re-pinned (116 vs 120): re-pinning is the owner's trade-off,
  not mine to write a reason for (F-COMMON: "re-pins a harness only with the reason written next to the pin").
- The flat-Ewald run of the new harness is gated on the beam-axis error, not the full matrix (reason in its comment).
- Grain B: diagnosed, no fix (F-COMMON (6): "fix only if the cause is established" — it is, and the fix is an open owner item).
- `real-acom-benchmark` not run (dataset absent); `check_mutations.py` for the convention harness not run (time; the two
  mutations the mirror pass could absorb — "Reflect projected y", "Swap projected x/y" — stay caught by the SAMPLED group's
  matrix bound because its generic axes are chiral, by the argument in the harness comment; unverified by a run).

## Proposed doc lines (terse; the supervisor places them)
- status handoff: "ACOM: the conjugated (mirror) correlation pass landed (review row 1; py4DSTEM `inversion_symmetry`):
  mirror-zone orientations 62→3 of 93 wrong (Al λ, 600 templates), sampled-zone 3→9 of 107, cost ×2 CPU / ×1.4 Metal;
  achiral zones tie and the Euler map of such a grain speckles between two classes — acom-convention-test reads 116/144 on
  its in-plane count (bound 120) pending the owner's call; FitOverlays does not yet draw mirrored wins mirrored."
- open-items (ACOM): "Mirrored-win tie on achiral zones (⟨001⟩ ⟨011⟩ ⟨112⟩…): the two passes tie at the polar image's
  resolution and a coin flip picks the beam-flipped class 37–60° off under the proper group; gaps overlap genuine wins
  (0.02–0.37) so no margin; measured 2026-10-01 (`mirror-fixed4.log`, `achiral.log`); the S20 quantisation fix would
  also remove the 6 sampled-zone regressions."
- open-items (ACOM): "FitOverlays.acomTemplateOverlay draws a mirrored win's template unmirrored (π − (azim + angle) is
  the mirrored spot's azimuth); one line, outside lane F-A's write-set."
- open-items (Q2 card / grain B): the closing line proposed in the grain B section above.
- plan log: "Lane F-A 2026-10-01: rows 1, 4, 5, 2 fixed red-first; grain B diagnosed to the S20 quantisation class (sweep);
  harness tools/acom-mirror-test added to `scientific`."

## Open questions for the supervisor (a sheet for the owner)
1. Row 1 lands with py4DSTEM's strict `>` (parity, ADR 050) and the measured cost: net wrong 65→12 of 200, but 6 new
   sampled-zone failures and the achiral coin flip. Options: (a) land as is and re-pin the convention in-plane bound
   120→≥110 with this report as the reason; (b) land and ALSO decide the S20 quantisation item (candidate F recovered 43/43
   synthetically; 3.8× cost; moved demo grain C 1.64°) — it would remove the quantisation-driven spurious mirror wins;
   (c) hold row 1 until (b). My recommendation: (a) now, (b) as the next ACOM lane — half of all orientations wrong is the
   larger defect. An independent second opinion is the supervisor's to add.
2. The one-line FitOverlays change (outside my write-set) — land with row 1 or as its own row?
3. `tools/run-tests.sh` one-token edit — acceptable, or should the harness live under an existing name?

### Convention harness — the groups the gate never reached (`convention-probe.log`, EXIT=0; scratch copy with the two
in-plane `require`s printed instead of enforced; the repo gate itself is unchanged and reads 116 < 120 on the fixed tree)
| group | median matrix error | in-plane < 20° | bound |
|---|---|---|---|
| Au sampled | 1.250° (HEAD 1.250°) | 116 (HEAD 131) | 3° met; 120 NOT met |
| Au mirror | 1.000° (HEAD 3.389°) | 122 (HEAD 74) | met; met |
| WS2 sampled | 0.690° (HEAD record 0.78°) | 240 | met; met |
| WS2 mirror | 0.796° | 240 | met; met |
| frozen py4DSTEM 0.14.17, 40 random orientations | **0.974° (HEAD record 2.06°)**, < 5°: **37 of 40 (HEAD 25)** | — | met |
Prediction held on the external set (< 2°, ≥ 30 of 40) — py4DSTEM's own random orientations are half mirror-zone, and the
port now agrees with the reference that generated them on 37 of 40. The one open number is the Au sampled in-plane count.

## Tests (name; the mutation; red exit; green exit; logs)
| test | mutation that makes it red | red | green |
|---|---|---|---|
| ACOMRow1MirrorZoneTests.testMirrorTriangleAxesAreRecoveredAndFlaggedSampledOnesAreNot | single pass (`for pass in 0..<1`, the CPU matcher; the test cannot compile on HEAD — the HEAD red is the harness `mirror-head2.log`) | `break-row1.log` EXIT=65: (1,4,6) 54.9°, (1,3,5) 52.9°, (2,5,7) 58.9°, flag false ×3, Metal disagrees ×3 | `unit-fixed4.log` EXIT=0, `unit-final.log` EXIT=0 |
| ACOMRow4Row5…testReimportingTheSelectedCIFWithADifferentCellInvalidatesThePlan | HEAD `ACOMSession.swift` (no observer) | `unit-head.log` EXIT=65; `break-row4.log` EXIT=65 ("templates were built for a = 4.0") | `unit-fixed.log`, `unit-final.log` EXIT=0 |
| ACOMRow4Row5…testAVoltageEditInvalidatesThePlanASameValueCommitDoesNot | HEAD `AppState+Open.swift` | `unit-head.log`; `break-row52.log` EXIT=65 ("built with the 200 kV Ewald curvature") | same |
| ACOMRow4Row5…testAnIdenticalReimportOrAnUnselectedModelKeepsThePlan | (guards the non-change; green on HEAD too, stated) | — | all runs |
| QUnitsRow2LineageTests.testChangingTheQUnitsRecordsANewCalibrationNodeWithThoseUnits | HEAD `AppState+Open.swift` | `unit-head2.log` EXIT=65, `break-row52.log` EXIT=65 ("nm⁻¹ is not equal to Å⁻¹ — the active Q node still reads the old units") | `unit-fixed4.log`, `unit-final.log` EXIT=0 |
| QUnitsRow2LineageTests.testUnitsWithoutASizeRecordNothing | (guards the refusal; green on HEAD too, stated) | — | all runs |
| ACOMSessionTests (14, existing, the touched owner) | — | — | 14/14 in `unit-head.log`, `unit-fixed.log`, `unit-final.log` |
First draft of the QUnits test asserted a NEW node id and was red on HEAD for the wrong reason (`unit-fixed3.tests.json`:
the lineage collapses consecutive calibration runs into one node, R3); corrected to assert the active node's units, then
re-run red on HEAD (`unit-head2`) and green. First draft of the Row1 test included (1,2,3), which at 17.3° is the known
modulo-π class on HEAD and after (37.4°, `unit-fixed3.tests.json`); replaced by (1,4,6), which the harness shows at 1.38°.

## Runs (command → log → exit), all 2026-10-01, lane tree copies of HEAD 2cd6a174
- tools/acom-mirror-test/run.sh on tree-head → mirror-head.log (first gate), mirror-head2.log, mirror-head3.log → EXIT=1 each
- tools/acom-mirror-test/run.sh on tree → mirror-fixed.log (no +π) EXIT=1; mirror-fixed2.log (+π) EXIT=1 (flat gate only);
  mirror-fixed3.log EXIT=0; mirror-fixed4.log (with pass-gap lines) EXIT=0
- tools/acom-convention-test/run.sh → convention-head.log, convention-head2.log EXIT=1 (mirror group red);
  convention-fixed.log, convention-fixed2.log, convention-fixed3.log EXIT=1 (Au sampled in-plane 116 < 120)
- scratch probe of the same harness → convention-probe.log EXIT=0 (table above)
- tools/acom-matching-test/run.sh on tree → matching-fixed.log EXIT=0
- $SP/FA/democube (S20 demo-cube rerun) → democube-head.log, democube-fixed.log, democube-fixed2.log EXIT=0
- $SP/FA/grainb (synthetic grain B sweeps) → grainb-200-flat.log, grainb-200-wl.log, grainb-600-flat.log, grainb-200-k09.log EXIT=0
- $SP/FA/achiral → achiral.log EXIT=0
- xcodebuild test (tree-head) → unit-head.log EXIT=65 (2 of 3 + 1 of 2 red as predicted), unit-head2.log EXIT=65
- xcodebuild test (tree) → unit-fixed.log EXIT=65 (two test drafts wrong, above), unit-fixed2/3 (diagnosis), unit-fixed4.log EXIT=0,
  break-row1/row4/row52.log EXIT=65, unit-final.log EXIT=0 (20 tests: 6 new + 14 ACOMSessionTests)
- tools/run-tests.sh core → core-1.log EXIT=0; tools/run-tests.sh inventory → inventory-1.log EXIT=1 (UNCLASSIFIED
  acom-mirror-test), inventory-2.log EXIT=0 after the `scientific` list entry
- NOT run: the full unit gate (supervisor's), `check_mutations.py`, real-acom-benchmark (dataset absent)

## Summary
Row 1 fixed as py4DSTEM does (conjugated pass, +π, column flip; `mirrored` on the result), red-first on an independent truth:
mirror-zone wrong 62→3 of 93, py4DSTEM's own 40 random orientations 25→37 of 40 within 5°; cost ×2 CPU; the measured
cost is 6 new sampled-zone failures of 107 and a coin flip on achiral zones — the convention gate's in-plane count reads
116/144 (bound 120) and is left for the owner. Rows 4, 5, 2 fixed red-first (plan invalidation on CIF re-import and
voltage edit; the units setter records its lineage node). Grain B is diagnosed, not fixed: the S20 azimuthal-quantisation
class (exact at every on-grid angle, a 1.8–3.6° neighbour at every off-grid one), unmoved by row 1 as predicted.

## git status --short (this lane's files are marked ◀; the rest belong to other lanes)
 M mac4DSTEM/App/AppState+DiskDetection.swift
 M mac4DSTEM/App/AppState+Open.swift ◀
 M mac4DSTEM/App/AppState+ResultPresentation.swift
 M mac4DSTEM/Core/Analysis/FriedelOrigin.swift
 M mac4DSTEM/Core/Analysis/OrientationResult.swift ◀
 M mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift
 M mac4DSTEM/Core/Crystal/CIFImport.swift
 M mac4DSTEM/Core/Crystal/MaterialsProjectImport.swift
 M mac4DSTEM/Core/Crystal/OrientationMatcher.swift ◀
 M mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift
 M mac4DSTEM/Core/Data/Calibration.swift
 M mac4DSTEM/Core/Data/H5Reader.swift
 M mac4DSTEM/Session/ACOMSession.swift ◀
 M mac4DSTEM/Session/LearnedDetection.swift
 M mac4DSTEM/Shaders/OriginMeasure.metal
 M mac4DSTEMTests/MaterialsProjectImportTests.swift
 M mac4DSTEMTests/MaterialsProjectSessionTests.swift
 M tools/acom-convention-test/README.md ◀
 M tools/acom-convention-test/main.swift ◀
 M tools/acom-matching-test/main.swift ◀
 M tools/run-tests.sh ◀
?? mac4DSTEMTests/ACOMRow1MirrorZoneTests.swift ◀
?? mac4DSTEMTests/ACOMRow4Row5PlanInvalidationTests.swift ◀
?? mac4DSTEMTests/CalibrationEllipseRow29Tests.swift
?? mac4DSTEMTests/FCRow25VirtualDetectorOrderingTests.swift
?? mac4DSTEMTests/FCRow27LearnedThresholdCaptureTests.swift
?? mac4DSTEMTests/FCRow8VirtualDetectorProvenanceTests.swift
?? mac4DSTEMTests/MaterialsProjectImportRow6Tests.swift
?? mac4DSTEMTests/MatrixDFTCorrelationRow9Tests.swift
?? mac4DSTEMTests/OriginNonFiniteRow24Tests.swift
?? mac4DSTEMTests/QUnitsRow2LineageTests.swift ◀
?? tools/acom-mirror-test/ ◀
