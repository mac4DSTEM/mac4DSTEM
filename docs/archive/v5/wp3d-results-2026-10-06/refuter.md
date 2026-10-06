# WP3d Gate D — independent refuter (Fable 5.1, 2026-10-06). Read-only; nothing in the repo touched.
Sources read: pre-reg (70d7b8f1), $W/report.md, harness/diag/main.swift, item1/step.py, item2/*.py, logs/item1-step.log,
item2-summary.log, item3-ratios.log, the old session's resid_whole.txt (1909) and quant-*.log, and the repo's
LinearDesign/EDSFit/Continuum/LeastSquaresFit/PoissonMLFit/UnlistedLineCheck/LineConflicts + SpectroscopyUnlistedLineTests.
"V" = verified by me from a file; "I" = inferred.

## 1. Scoring honesty
- V: P1.1, P1.2, P2.1 (Al arm), P3.3 are scored FAILED against the registered wording; P2.2, P2.4, H2d scored on the
  registered bars; unregistered variants (V5f, V10–V12, the 2.5 eV grid, the +30 eV scan start, step.py's three extra
  windows) are labelled "added"/"not pre-registered". No goalpost moved. The P2.1 note that the registered 0.5–0.6 %
  compared a window excess to a whole-column area is arithmetic I checked (55 % of an 82 eV FWHM Gaussian at +85 eV
  falls in 1.565–1.64 keV); it explains the miss, it does not rescue it.
- One overstatement: "P1.3 … HELD" for the 1339-matrix arm. The step is 12.6 ± 3.7 % on the registered window but 8.1 ± 3.7
  (2.2 σ) with Si Kα excluded and 17.9 ± 7.0 with a slope term, against a Kramers form at χ²r 2.4–4.8 (V, item1-step.log).
  A 2.2–3.4 σ effect whose size halves with the window, on one pool, with the pure-Al arm unrun, is INCONCLUSIVE, not held.
- V: the 1909 whole residual across the Al Kα core is oscillatory (−21 k at 1.432, +23 k at 1.471, −27 k at 1.511, +24/+67/+47 k
  at 1.551–1.590 keV), not the antisymmetric pattern a centroid shift gives, so the untested axis-shift arm cannot be the
  maker of the +85 eV column (I). V3's "asymmetric" wording in the pre-reg stands.

## 2. Harness fidelity (V unless marked)
- `diff -rq harness/mac4DSTEM/Core repo/Core` is empty; the LS entry `solve(nonNegative:y:rowWeights:)` and the ML entry are
  the repo's. The design is `LinearDesign.build(... .continuum(form))` with the same non-negative columns the app's
  `EDSFit.fit` solves (continuum columns are `nonNegative: true` by default, so `filter{!signed}` keeps them and `free` is
  empty). `design.offset` is zero without a `.countsAboveEdge` shape, so the harness's un-subtracted `y` equals the app's
  `target`. The axis is refined once per (pool, list) and held; width from the same refinement. Faithful.
- The +30 eV scan start for Si/Cu is cosmetic: the registered Si/Cu arms were judged at the fixed +100 eV column (0 %).
  The Al scan includes Δ = 0 (a duplicate column); under NNLS it cannot lower the RSS, and it did not win.
- step.py fits the DATA column of resid_*.txt (header "E data model4 bg4 modelExt"), not a residual. Its σ is scaled by
  √χ²r. Fine; the form's misfit is the caveat above, not a bug.
- Nothing manufactures the headline results: the 0.54–0.59 % window excess is baseline V0 (no column), reproduced on the
  current Core; the 1.1–1.4 % column at +82…+90 eV is read from NNLS areas (item2-summary.log, e.g. 1909 matrix 66 580 =
  1.074 %), consistent with the window arithmetic.

## 3. Null inference
- The AlCoCu non-detection is reported with the differences listed and "no mechanism inferred" — correct. It is used only
  to say the column is not a method default, which is the right use of a null (a scope limit, not a cause).
- Slip to fix in the docs: P3.3's verdict is right but its stated cause is wrong. The per-element L/K "spread" is mostly the
  sibling sitting at the NNLS bound under overlap (Cu Lα 0.93 keV = 0 ± 1899 on 1456 beside 1.9 M Ni Lα and 6.1 M Ge Lα;
  Fe Lα 0 at bound in six LPBF pools) — a measurement failure of the sibling, not an 18-fold ratio. That is a stronger
  reason to drop B1 (the sibling net is unmeasurable where it is needed), not a weaker one.

## 4. Does the evidence support each candidate fix?
(1) Al K high-side column: supported on these three files (9/9 pools, 1.1–1.4 % at +82…+90 eV, absent on Si/Cu at +100 eV,
    unchanged by split position; Kβ position within 0.3–2.1 % RSS) — but it is a property of this detector/these files
    (absent on AlCoCu), with no pure-Al reference. Not a default; not even an unvalidated toggle (below).
(2) LS→ML: it is a different estimator that moves the same lever (+0.15 on matrix data/model, 0.60→0.77) and leaves
    16–25 % of the deficit; not a fix; its own registration, after (1) is measured. Supported as "not now".
(3) Si step: one pool, 2.2–3.4 σ, sign-ambiguous under a free segment (V4 fits an UP jump). Not supported for landing.
    I: 1909/1840 are too LOW at 2.17–2.40 keV (data/model 1.07–1.20 after V4) and too high at 1.85–1.975: the 1.6–2.4 keV
    misfit is a shape over ~0.8 keV, which an order-5 segment spanning 1.56–20 keV cannot follow. A detector efficiency
    knee (window + dead layer, `ContinuumForm.efficiency` is nil by default) fits that description as well as H1b —
    hypothesis for the next registration, not a finding.
(4) B2 + B3: B2 was never run (P3.1 INCONCLUSIVE). My post hoc read of quant-1909.log, default list O/Mg/Al/Si, matrix:
    of 14 candidates only Lu Mα is "beside a listed line"; Ho/Cs/Sm/Br/Ba/Eu/Sb/Se/Pr/Sn Lα and real Cu/Ar are not. So
    B2+B3 as registered removes the false NAME (Lu/Tm/Er) but at% stays withheld on every pool (V). The lane's claim that
    this makes the room usable is not supported; the blocker is F1's > σ bar, not the labels.
    V: on the real pools every candidate set crosses "> σ" — 1909 network (extended list) moves O by +468 on σ 412 (1.1 σ),
    1909 matrix moves Mg by 25 σ. The bar was measured on synthetic pools (0.3–0.9 σ harmless, 27–33 σ missing) and does
    not separate on real ones: by the threshold rule it is a property of that dataset, and the quantity ships.

## 5. Decision sheet — what lands NOW (owner away; overrule on sight)
P1 Quantify withholds at% on every Al-alloy pool. Options:
  A1 B2+B3 as registered (label beside-line candidates, they never withhold). 0.5 day, low risk, does NOT unblock (above).
  A2 A1 + ship the quantity: at% shown, never blanked by F1; the F1 line and a caveat on the at% rows say what is unlisted
     and the largest move. 0.5 day. Risk: an at% wrong by omission (a real unlisted Cu at 139 k) is on screen — labelled.
  A3 Leave as is until pure Al. 0 effort; the v5.0 room stays blocked on the owner's own data; nothing learned.
  DECISION: A2. Reason: the rule "a threshold is a property of the dataset it was measured on … or ship the quantity" is met
  by §4(4). The blanking was my own recommendation this morning on synthetic evidence; the real evidence reverses it.
  This is the one line the owner is most likely to overrule; the revert is one function (`withholding`).
P2 Al K column — DECISION: does not land. An off-by-default unvalidated toggle is surface with no validation path (no filler;
  ADR 049 "finish or remove"). The spec is ready; it lands in one lane the day a pure-Al spectrum arrives.
P3 LS→ML default — DECISION: not now; own registration after P2 is measured (pre-reg order kept).
P4 Si step — DECISION: nothing lands; the open item's "no Si K edge" wording is corrected (below).

## 6. Spec for the Sonnet builder (A2 = B2 + B3 + ship the quantity). No file under Fit/ or ElementProposer.swift changes.
Core — `mac4DSTEM/Core/Spectroscopy/Quant/UnlistedLineCheck.swift`:
- `Candidate` gains `besideLine: String?` ("Al Kα", "Cu Kα", or "the continuum split at 1.560 keV") and
  `fractionOfNeighbour: Double?` (candidate net / neighbour group net).
- New pure function `UnlistedLineChecker.neighbour(energyKeV:, listedGroups: [EDSLineModel.Group], resolutionMnKaEV:,
  edges: [Double]) -> (line: String, net: Double)?`: the nearest line of any listed group within ±2·FWHM(E)
  (`XRayLines.fwhm(resolutionMnKaEV:atEnergy:)` at the candidate energy), else a split edge within ±1·FWHM, else nil.
  Listed groups = `EDSLineModel.build` on `q.fitSettings` (same list, axis, width); nets from `q.rows`/fit values; edges from
  `case .continuum(let form)` of `q.fitSettings.background`. ±2 / ±1 FWHM are stated in the file header as a geometry
  convention, not a measured bar; no count threshold anywhere.
- `check(...)`: candidates with `besideLine != nil` do not enter the refit (they are not elements). `names` prints a
  beside candidate as "unexplained excess beside Al Kα: 44 913 counts, 0.7 % of Al Kα" — never the element symbol
  ("Lu" may appear in `summary` only as "proposer's label Lu Mα"). `line`/`summary` keep their shape otherwise.
- `withholding(_:_:)`: never calls `blankAbundance`; sets `out.abundanceCaveat` (new `String?` on `PooledQuantification`)
  = "assumes the listed elements only; unlisted: Cu (net 139 411), Ar …; largest move 25 σ (Mg)" when candidates exist,
  nil when none. `abundanceRefusal` stays for the pending state and for failures. `holding(_:)`: at% shown at once with the
  caveat "unlisted-line check running" (a number never vanishes; a caveat is replaced). Export `#` line carries the caveat.
- Room (`UnlistedLineNote` and the Add/Dismiss buttons, grep for it): a beside candidate has no "Add" action; the note text
  is the Core line. Wording only in the room files; no structure change (ADR 056 rebuild in flight — touch nothing else).
Tests — `mac4DSTEMTests/SpectroscopyUnlistedLineTests.swift`:
- T1 `neighbour`: 1.581 keV with Al listed (130 eV Mn) → "Al Kα" (1.15 FWHM); 2.957 keV (Ar) → nil; 7.899 keV → "Cu Kα" with
  Cu listed, nil without. Mutation: ±2 FWHM → ±1 FWHM turns the Lu case nil (red). Break it before trusting it.
- T2 consequence: seed 0 of P5 (the chance Lu Mα on the split) → named as "unexplained excess beside …", `withholds` false,
  no "Lu" in `names`. Plant Lu_Ma at 1 % of Al Kα on the P4 generator (large enough that a refit WITH it moves Al by > σ):
  still `withholds` false. Mutation: let beside candidates into the refit → red on the planted case.
- T3 ship-the-quantity: P4 (Ge/Cu/Ga real, far from listed lines) now keeps at% non-nil and `abundanceCaveat` names them
  and the largest move; `moves` identical to today's P4 values (assert the same elements and the same before/after nets as
  the current test notes). Mutation: blank at% again → red.
Numbers that must not move: every net, σ, move and L_D in the existing P4/P5/P5b tests; all of SpectroscopyProposerTests,
SpectroscopyFitRangeTests, SpectroscopyAutoIDTests unchanged (no fit code touched, so no fitted number can move — the
commit's diffstat proves it: no path under Core/Spectroscopy/Fit or Proposer/ElementProposer.swift).
Docs, same commit (net negative lines): open-items — replace "The continuum has no Si K edge" with: the fitted continuum
is 1.2–1.7× the data over 1.65–2.4 keV; ~55–65 % of the matrix deficit is unweighted LS absorbing the Al Kα high-side misfit
(ML, a 1.55–1.66 mask and a tied column are one lever); a 1.839 keV step is 8–18 % on one pool (2.2–3.4 σ), unmeasured on
pure Al; the Al Kα excess is a +82…+90 eV feature of 1.1–1.4 % of Al Kα in 9/9 pools, absent on Si/Cu and on one other Al
spectrum; B1 is dropped (sibling nets at the NNLS bound). Keep the pure-Al request. Add one line: the unlisted check costs
23–437 s per real pool (a usability defect, its own item). status.md: WP3d row = experiments done, A2 landed, P2–P4 owed.
