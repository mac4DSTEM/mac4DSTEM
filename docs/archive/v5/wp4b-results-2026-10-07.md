# WP4b — the two held Auto ID rules on sets that test their risk: results (2026-10-07 night)

Registration: `wp4b-autoid-rules-preregistration-2026-10-07.md` (committed 03780df0 before any run). Built and run by lane W (Sonnet, then
Haiku after an app restart; commits 8557aa63 guard option, 368ffde4 tooling, 18b527ad report fix); independent refuter (Opus, read-only,
re-derived every key number from the JSON). Evidence: `wp4b-results-2026-10-07/tables.md` (every table), `lane-report.md`.

## Verdict: nothing ships
- **R1b (beside-K with the evidence guard) stays off. H5 refuted as written**: it drops four TRUE L elements at line-area ratio ≥ 1 in the
  risk simulator — Hf Lα beside Cu Kα (realised net/L_D 1.17 vs 1.50), Ta beside Cu (4.43 vs 4.49, a near-tie that `<` would also drop),
  Pt beside Ga at both doses (1.60 vs 2.17; 6.51 vs 7.32). **Mechanism (refuter):** at equal line area an L family's L_D is larger than a
  nearby K line's (calibration: Pt Lα 30.9 vs Ga Kα 21.9; Ta Lα 28.1 vs Cu Kα 22.7 counts), so "net/L_D at or below the K's" compares
  unequal quantities across families. No reading of the registration saves it (even the significance-ratio reading leaves Hf, 1.07).
- **R2 (L/M needs net/L_D ≥ 3) stays off. H6 refuted as written**: on T-V it loses 4 hits (bar: at most 1) — Pt in 1549 (2.76), Ge 1020
  (2.45), Ni 1100 (2.20), In 1253 (1.36); 7 without de-duplication. **Caveat (refuter):** T-V is the set R2's cut was read from and the
  registration itself cited "4 of 404" there, so this arm was in-sample and fixed in advance; it adds no new evidence. The only off-set
  truth, T-Q, favours R2 (precision 53.9 → 81.3 %) at a cost of 8 hits, all in the difficult and very-difficult classes. Re-testing R2 is
  a new item, not an amendment.
- `ProposalRules.shipped` is unchanged; the net/L_D beside each pick stays the shown quantity; the `unvalidated` badge stays.

## The numbers (re-derived by the refuter; all match)
| set | base (shipped) | R1b | R2 | R1b + R2 |
|---|---|---|---|---|
| T-Q, DTSA-II Qual (31; precision / recall) | 53.9 / 55.1 % | 69.5 / 55.1 % | 81.3 / 51.7 % | 81.9 / 51.7 % |
| T-S pairs (30; recall, no false picks in any set) | 82.2 % | 70.0 % | 74.4 % | 67.8 % |
| demo-edx ladder (8 regions; precision / recall) | 83.3 / 38.5 % | 83.3 / 38.5 % | 88.2 / 38.5 % | 88.2 / 38.5 % |
| T-V, the owner's Velox selections (78 distinct; agreement, not truth) | 34.7 / 45.5 % | 39.2 / 45.5 % | 49.3 / 44.6 % | 49.5 / 44.6 % |

R1b removes 115 false picks (54 on T-Q, 61 on T-V — mostly Hf beside Cu Kα and V beside O Kα) and loses no T-Q or T-V hit: its value is
real on bulk glass and on agreement data, and its risk is real on true pairs. A guard that compares families on equal terms (e.g. a
line-shape or β-line evidence term instead of net/L_D) would be a new registration.

## What a reader must know
1. T-Q is SEM bulk glass, **13 of 31 spectra at 20 kV and 18 at 25 kV** (the registration said 25 kV), 10 eV/ch; no resolution in the
   headers, the harness default 130 eV used; its truth lists Li and B, which the proposer cannot reach (tables give both readings).
2. The risk simulator plants line areas; realised net/L_D differs widely (Cu planted 6.0, realised 2.01 in Ta+Cu r3 high); one seeded
   draw per case. M lines and escapes are not planted (the script says so). No sign the dose was tuned toward an outcome (one calibration
   run, constants k = 1.5 / 6), but `risk_sim.py` was committed after the runs, so git cannot prove its pre-run text.
3. The ghost clause is vacuous: the baseline makes no false L/M pick beside any K ghost (0 of 0). Ag Lα + Ar Kα tests the sum-peak logic
   (both sit beside 2 × Al Kα), not either rule.
4. T-V: 112 files seen, 88 scored (78 distinct), 17 without a stored selection, 1 not a spectrum image, 6 entries (0944, 1121, 1140, 1253)
   failed with `ProposerError` 2 — one copy of 1253 failed while another scored; unexplained. All 88 got a metadata date (WP4's "43 owed
   dates" are covered by this run).
5. The commit-2 gate's first run lost its test host mid-test: `SpectroscopyProposerTests.testKramersContinuumNoFalseMgAndTheDetectionRate`
   reported failed at 0.000 s with no assertion, the next test ran in a new runner; macOS wrote a hang report for that pid (main thread
   busy in `ElementProposer.propose` for 34.9 s at load ≈ 30, still computing). The test is seeded and deterministic; the termination's
   cause is not established. Two later runs were green (2320 / 0 / 3).
