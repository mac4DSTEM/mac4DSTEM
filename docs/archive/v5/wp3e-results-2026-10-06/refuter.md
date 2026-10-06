# WP3e Gate D2 — independent refuter (Fable 5.1, 2026-10-06). Read-only. V = verified from a file; I = inferred.

## 1. Harness fidelity — V
- harness Core == repo Core at fd80f6a4 except ElementProposer.swift (the switches) — PooledQuantification differs only because
  main moved on to ef64c372 (R7); the harness copy is byte-identical to fd80f6a4. The proposer diff is: `sigma0Mode` (0 = `f = fl`,
  the repo path unchanged), modes 1/2/4, a parent trace, `finalParents`, `lastChi`. Mode 4 ("max2", the settled-fit √χ²ᵣ held fixed)
  is unregistered and labelled so; it is the literal reading of the pre-reg's "of the settled fit", and max/max2 agree within ~3 %
  on 14/16 pools. Baseline (mode 0) reproduces the previous session's AlCoCu and FePt candidates digit for digit. No bug found that
  manufactures a result; √χ²ᵣ is floored at 1 (correct: over-dispersion scaling never shrinks σ0).
- Caveat the report states and I confirm: the 1339 baseline list differs from the pre-reg's V0.1 (file axis + WP3c 20 keV range), so
  item-1b/3 comparisons are within this run only.

## 2. Scoring honesty — V
- 1b: the registered proof condition is met exactly (Zr's conflict "Hf+Hf sum"; Hf a parent while Hf is the Al+Fe question; chain to
  Ba at 1.03 L_D). The join ORDER differs from the registered narrative (Zr joined before Hf existed) and the report says so: the
  mechanism is the final-state parent set, which is what fix (b) addresses. HELD is honest.
- R3.1 HELD (9/98 beside; Eu/Ho/Co/Mn never beside), R3.2 PARTLY HELD with the aim unmet (Eu, Hf 6/6; Eu newly added by the greedy
  path; non-monotone), R3.3 FAILED (AlCoCu identical under max), R3.4 Tm not reproduced → INCONCLUSIVE, Mg risk not realised.
  No softening; the unregistered `chi` mode is reported as diagnostic and harmful. Nothing is inferred from the AlCoCu null.
- One addition for the record: the Mg arm's stronger finding (Mg unlisted is undetectable: net 0 at the bound, L_D 256 k, factor ×72)
  is a proposer limitation on real Al pools, independent of F3.2 — it belongs in open-items.

## 3. Decisions (owner's delegate; overrule on sight)
D1 Fix (b) "a parent is a listed element or a `proposed` candidate (≥ L_D, no sum conflict against the current parents); sum-peak
   questions and 'possible' candidates never parent" — LANDS, after one pre-landing print (below). Reason: the mechanism is proven
   by a reproducing print (Gate D's own exemption); today's rule lets a 1.03 L_D proposal manufacture a four-link chain and a
   question that names a sum of two non-elements. The Zr outcome (I: question → plain proposal, net 5 727, ~15 × L_D, χ²ᵣ 430 shown)
   is BETTER for the user: a 15 × L_D line that nothing listed explains is a finding to look at; "Hf+Hf? (or Zr Kα)" hides it
   behind a parent nobody believes. The unvalidated badge and the stats line carry the doubt; the reader judges.
D2 F3.2 (σ0 × max(flank, √χ²ᵣ)) — does NOT land, neither default nor toggle. The registered success condition (an implausible list
   cleared on all pools + AlCoCu) failed; it adds candidates through the greedy path; 1456 never settles. A toggle is filler.
   The next registration is the pre-reg's M3b: a local under-the-column misfit statistic for survivors (Eu, Hf) — not now.
D3 Presentation instead of a bar: proposals (and questions) sorted by net/L_D descending, each with its stats line (R7 already
   shows net, × L_D, χ²ᵣ). NO "low-confidence" group: any cut is a threshold measured on no dataset. The look-elsewhere note and
   the unvalidated badge stay. That is the whole change.
D4 R8 (the split edge's own element excluded from `neighbour`'s edge branch) — right fix; its test must plant an EMPTY list with an
   Al candidate (the fresh-open case) and assert Al is proposed, not "beside the split".

## 4. Spec for the Sonnet builder (D1 + D3)
Core — mac4DSTEM/Core/Spectroscopy/Proposer/ElementProposer.swift, `settle()` (lines ~293–308): `nextParents` = listed ∪ candidates
  that are `isProposed` and have no sum conflict against `LineConflicts.sumEnergies(parents: current parents)`; the existing loop
  iterates to the fixed point (keep its stability test). Expose `parents: [SumParent]` on `ProposalResult`. `banned`/forward step
  untouched. Header DEVIATION-style note: why questions never parent (the 1339 chain, pooled numbers only).
Pre-landing print (harness exists: `realdiag prop … --print-conflicts`, mode 0): the 9 owner pools + synthetic whole/Al-phase with
  (b) vs without; commit the table (pooled numbers) under docs/archive/v5/. Landing condition: on the synthetic pools the proposed
  set and every sum column of listed/true parents are unchanged; on real pools the only changes are questions → proposals or →
  nothing and the disappearance of found-only sum columns. Anything else = stop, new registration.
Tests — mac4DSTEMTests/SpectroscopyProposerTests.swift:
  T1.2 on the S2c region (Ar at Al+Al): `parents` contains no Ar; no sum column id contains "Ar". Mutation: let questions parent → red.
  T1.3 chain fixture (simulator): plant X (clear, ≥ L_D) and Y at 2·E(X) above L_D with no listed parent for it: Y is a sum-peak
    question (X+X), Y ∉ `parents`, no "Y+…" sum column; then plant Z at E(Y)+E(X): Z is PROPOSED (not a question), because Y never
    parents. Mutation: parents = listed ∪ all found → Z becomes a question → red. Break both before trusting them.
  Must not move: `testSumPeaksAreNamedExactlyWhereTruthExceedsTheDetectionLimit` counts (all six sums have listed/true parents),
  `testFalsePositiveRateAtTheCriticalLevelIsAboutAlpha`, every net/σ in the fit tests (no file under Fit/ in the diff).
UI — AutoIDPresentation.outcome: stable sort of suggestions, excesses and suspects by `significance` descending; test in
  SpectroscopyAutoIDTests: two candidates at 3.0× and 1.2× → order; mutation: drop the sort → red. Wording only elsewhere.
Docs, same commit: open-items — WP3e row: 1a/F3.1/F3.3 landed (R7), (b) landed with the print, F3.2 refuted as a default (one
  line each, the numbers above); add "Mg unlisted is undetectable by the proposer on real Al pools (L_D 256 k, ×72)"; status.md row.
