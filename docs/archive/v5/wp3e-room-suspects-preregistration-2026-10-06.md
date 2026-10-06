# Gate D2 — Auto ID on real Al alloys: sum-peak labels, an unflagged χ²ᵣ, manufactured detections — pre-registration DRAFT (2026-10-06)

Read-only designer session on main 6cd7252a; no code run. **V** = read from a file this session (code, logs, drive record);
**I** = inferred from V by arithmetic or code reading, not yet observed. Logs: the previous session's `realAlMgSi/logs/quant-1339.log`
(whole map, default list O/Mg/Al/Si, file axis) and this scratchpad's `gateD/logs/item3-prop-*.log`. Owner data stays unquoted
beyond pooled numbers. The `gateD/harness` `prop <spec> <tag> <listcsv>` command runs `ElementProposer` headless on a dumped pool.

## 0. What the evidence already says
- V0.1 Auto ID on 1339 whole: proposed Cu (net 245 882, L_D 10 945, misfit ×19.9), Sn (603/238), Ho (4 513/2 073), Mn (7 554/4 115);
  sum-peak questions Zr, Ar, Hf, U, Co, Fe; "possible" Tm Mα net 2.0 M, Er Mα 472 k, Eu, Se …; sum columns Co+Fe, Fe+Ho, Ho+Mn, O+U;
  24 passes, settled. χ²ᵣ (Pearson) of the same pool's quantify: 1 319 (whole), 411, 165 (quant-1339.log lines 5–33, 42–100).
- V0.2 1456 (another owner SI): 53 passes, NOT settled, 8 proposed (Ge, In, Ti, Ni, Ce, Zr, Yb, Bi) with misfit ×25–×191; AlCoCu
  (a published Al spectrum, 6 s): Ho, Lu, Yb proposed at misfit ×16–×25; FePt (synthetic, χ²ᵣ ≈ 1): Cu and Zr at ×1.3–×3.2.
- V0.3 Code: σ0 is the LS sandwich with Var(y) = model (Poisson only; `FitNullVariance`), times the flank factor √mean Z² over
  1.5–6.5 FWHM bins on both flanks (`flankMisfit`). No term anywhere carries the global misfit (χ²ᵣ) into L_D. Sum parents are
  `listed + found`, where `found` excludes only candidates sitting on a sum of LISTED parents (`settle()`, lines 297–302): a
  candidate that is itself a sum-peak question of a found parent, or any ≥ L_D found candidate, becomes a parent.
- V0.4 Room: `AutoIDPresentation` labels a suspect by the candidate's line ("Ar Kα?"); the sum label lives only in `question`.
  χ²ᵣ is on screen only as the tail of the grey one-line caption "LS · Kramers×B(9,5) · χ²ᵣ 3318.00" (`QuantifyPresentation` 220,
  `QuantPanelView.methodDisclosure`, lineLimit 1, truncation tail) — the number that says the model is wrong is the last token of a truncating line.
- V0.5 A2 landed `UnlistedLineChecker.neighbour` (±2 FWHM of a listed α line → "unexplained excess beside Al Kα", never an element);
  Auto ID does not call it (open-items: `suggestedRole` one-source-of-truth owed).
- I0.6 Energies: Zr Kα 15.775 = Hf Lα + Hf Lα (2 × 7.899 = 15.798, Δ 23 eV ≤ 60 eV tolerance); Hf Lα 7.899 = Al Kα + Fe Kα (7.887, Δ 12 eV);
  Ar Kα 2.957 = Al + Al (2.974, Δ 17 eV); Tm Mα 1.462 is 25 eV below Al Kα; Lu Mα 1.581 = Al Kα + 94 eV (the WP3d +82…+90 eV excess).

## Item 1 — "Ar Kα?" / "Zr Kα?" suspect markers
Observation (plain words): the spectrum shows an element's name with a question mark where the proposer's own finding was "a pile-up
peak or this element"; on the real file one marker (Zr) names a sum of two elements nobody listed or believes in.
Mechanisms: M1a (label) the marker leads with the candidate instead of the sum (V0.4) — presentation. M1b (chain) phantom parents:
Fe (a sum question) → Hf on Al+Fe → Hf+Hf = Zr (I0.6 with V0.3). M1c the Ar question on the real file is a genuine Al+Al pile-up
(8.4 M counts in the pool) — correct behaviour, only the wording is wrong. M1d Ar is real (Ar-ion milling implants Ar) — not excluded.
Refuting observation (headless, `prop` on the 1339 whole pool + one print of each candidate's conflicts and the final `parents`):
M1b is proven if Zr's conflict reads "Hf+Hf sum" and Hf is a parent while Hf is a sum-peak question; refuted if Zr's parents are
listed elements. Prediction: Hf+Hf and Fe+Ho appear as parents (sum columns Fe+Ho, Ho+Mn, O+U already V0.1 — Ho, U are parents today).
Fix (smallest): (a) presentation, no Gate D — the marker reads "Al+Al sum? (or Ar Kα)" and the inspector line leads with the sum; a
sum question is never drawn as an element label. (b) Core, one rule: a parent is a listed element or a candidate in `proposed`
(≥ L_D and no sum conflict); sum-peak questions and "possible" candidates never parent. This changes which sum columns exist, so
nets can move by the column's share — Gate D applies, but a reproducing print proves the mechanism, so the experiment IS the
diagnosis. Tests: T1.1 (`SpectroscopyAutoIDTests`) a sum-question suspect's label contains the sum label first; mutation: revert
label → red. T1.2 (`SpectroscopyProposerTests`) on the sim region with Ar at Al+Al: Ar is not in `parents` (expose `parents` on
`ProposalResult`), no "Ar+Al" or "Ar+Ar" sum column; mutation: let questions parent → red. Numbers that must not move:
`testSumPeaksAreNamedExactlyWhereTruthExceedsTheDetectionLimit` counts (all six sum energies are of listed/true parents).
Effort ½ day; risk low (Ar/Al sum behaviour at 300 counts/px is pinned by the existing test).

## Item 2 — χ²ᵣ 3318 (54.8 after unlisted lines) is not flagged
Observation: the at% table and σ look authoritative while the model misses the spectrum by 50–3000× the counting variance.
Mechanisms: M2a presentation — the number exists and is hidden (V0.4). M2b there is no model-misfit statement at all in Core
(no warning on χ²ᵣ: `EDSFit` warns on escape ratio, negative model, solver exit, weak-line bias only — V, lines 302–320).
NO Gate D: nothing scientific moves; the quantity ships (threshold rule: no "bad above X" bar; χ²ᵣ's expectation of 1 is a
property of the statistic, not a measured cliff, and is stated, not coloured). Fix: the quant panel header shows "χ²ᵣ 54.8 (Pearson)"
beside at%, always, and the σ column's help/caption reads "σ: counting statistics at χ²ᵣ = 1; this fit is at 54.8" (one Core
`footerLines` entry so Export carries it). A2's caveat line gains the same clause. Test: `SpectroscopyQuantifyTests` — the
presentation line contains the quality label and the σ caption names the value; mutation: drop the clause → red. Effort 2 h; risk nil.
Decision: build directly, before items 1b and 3. The owner may overrule the wording.

## Item 3 — implausible elements (Eu, Hf, Co, Ho on 1339; Tm on synthetic)
Observation: Auto ID offers rare earths and transition metals on an Al-Mg-Si alloy; each sits at 1.1–2.2 × L_D (V0.1) — never a
strong, isolated peak.
Mechanisms (competing): M3a L_D is Poisson-only (V0.3): at χ²ᵣ 165–1319 the per-channel systematic residual is 13–36× the counting
σ; the flank factor (×5–×119) catches only what lies 1.5–6.5 FWHM out, and a column centred ON a misfit feature (Al tail, Cu Kα axis
offset 10–15 eV — WP3d V7, continuum 1.2–1.7× over 1.65–2.4 keV) is scored against a σ0 that excludes exactly that feature.
M3b shape errors are the signal: Lu/Tm/Er at Al Kα ± 100 eV, Hf at the Cu Kα flank — real residual, wrong name (A2's finding).
M3c look-elsewhere: 0.055 chance proposals per spectrum at 114 groups (V, notes) — too small by 100× to make 4–8; rejected as the
main cause but it IS the floor once M3a/M3b are removed. M3d greedy forward step (24 rounds, `banned` only after a prune) adds
columns until the residual is used up; on 1456 it did not settle (V0.2) — a symptom of M3a, not a separate cause.
Refuting observations (headless `prop`, 9 owner pools + AlCoCu + FePt + the synthetic AlMgSi region pools; add a harness flag
`--sigma0-scale {flank|chi|max}` and a `--print-conflicts`, both in the scratchpad harness, not the repo):
R3.1 Partition today's proposals by `neighbour()` (A2): count how many `proposed` sit within ±2 FWHM of a listed α line or the split.
   Prediction: Lu, Tm, Er, Hf-when-Cu-listed are "beside"; Eu, Ho, Co, Mn, Sn are NOT (refuter §4(4) read 1/14 beside on 1909) —
   so A2's label alone does not clear the list (V-consistent; I until run).
R3.2 Replace the flank factor by max(flank, √χ²ᵣ_Pearson of the settled fit) — the standard over-dispersion scaling, a quantity of THIS
   spectrum (threshold rule: it is measured, not chosen). Prediction on 1339 whole (I from V0.1, √1319 = 36.3): Cu survives (245 882
   vs L_D ≈ 10 945/19.9 × 36 ≈ 20 k), Ho (4 513 vs ≈ 12 k), Mn (7 554 vs ≈ 20 k), Sn (603 vs ≈ 5 k) do not; Tm/Er stay "possible"
   or drop. On FePt and the synthetic pools (χ²ᵣ ≈ 1–3) the candidate list is unchanged ± the look-elsewhere floor. If Cu also drops,
   M3a is refuted as THE lever and the per-feature misfit (M3b, a local χ² under the column) is the next registration.
R3.3 Null discipline: an element vanishing under R3.2 proves only that its net is within the model's own scatter — NOT that it is absent;
   AlCoCu (Ho/Lu/Yb at ×16–×25) is the control where no Al-alloy elements exist: prediction, all three fall below L_D under R3.2.
R3.4 Synthetic truth: `truth_edx.json` lists Al, Mg, Si, Cu, O, Ga only; Tm on the synthetic (drive 1) must be "beside Al Kα" under R3.1
   (Tm Mα −25 eV) — if it is not, the synthetic has its own misfit (the Kβ/Kα depletion, open-items) and R3.2 should still remove it.
Fix (smallest, in this order): F3.1 reuse A2 — Auto ID runs `neighbour()` on every `proposed` candidate; a beside candidate is shown as
   "unexplained excess beside Al Kα (proposer's label Lu Mα)" with no Accept button (one source of truth; `suggestedRole` retired). No new
   bar; presentation of an existing rule — no Gate D. F3.2 σ0 scaling by max(flank, √χ²ᵣ) in `ElementProposer.stat` — lands ONLY if R3.2's
   predictions hold on all 9 pools + AlCoCu + FePt + synthetic; the notes name the factor used per candidate (already `misfit`). F3.3
   every suggestion shows net / L_D and χ²ᵣ of the fit it came from (ships the quantity whatever F3.2 does).
Tests: T3.1 `SpectroscopyAutoIDTests`: a candidate at Al Kα + 94 eV with Al listed becomes a beside note, not an `ElementSuggestion`;
   mutation: ±2 → ±1 FWHM → red (same mutation A2 used). T3.2 `SpectroscopyProposerTests`: on the lane-S simulator fit the pool with a
   deliberately wrong continuum (polynomial order 2 instead of Kramers×Bernstein) so χ²ᵣ ≫ 1 with truth planted; assert the number of
   non-truth `proposed` ≤ 1 (the look-elsewhere floor) under F3.2 and record the count without it in the test note; mutation: scaling
   off → red. T3.3 the existing `testFalsePositiveRateAtTheCriticalLevelIsAboutAlpha` must stay green (χ²ᵣ ≈ 1 there: factor ≈ 1).
   Break each before trusting it. Numbers that must not move: every net/σ in the fit tests (F3.2 touches `stat`, never the fit).
Effort: F3.1 + F3.3 ½ day; harness + R3.1–R3.4 ½ day (23–437 s per real pool × 11 pools, run in one background log); F3.2 ½ day.
Risk: F3.2 raises L_D on every real pool, so a real weak element (Mg at 0.3 %) could fall below L_D — measure Mg's L_D before/after on
the 1909 matrix pool and report it; if Mg is lost, F3.2 is a toggle the notes explain, not a default (decision for the owner's sheet).

## Gate D triage and the delegate's decisions (owner overrules on sight)
| # | Needs Gate D | Why | Build now |
|---|---|---|---|
| 1a label | no | presentation | yes |
| 1b parents | yes, but the print IS the proof | changes sum columns → nets | after the print |
| 2 | no | shows an existing number | yes, first |
| 3 F3.1/F3.3 | no | A2's rule and the quantity | yes |
| 3 F3.2 | yes | moves every L_D on real data | only if R3.2 holds |
Order: 2 → 1a → F3.1/F3.3 → harness run (R3.1–R3.4, item 1b print) → F3.2 and 1b, each with its own refuter. Independent refuter reads
this file and the harness log, not the diff. Unvalidated badge stays on every Auto ID result (self-reports validation "none").
