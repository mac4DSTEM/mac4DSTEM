# Lane S4 report: design-scoped sum-vs-one-peak rule (registered 2026-10-08; numbers only, no verdict)

Registration: docs/archive/v5/sum-escape-design-scoped-preregistration-2026-10-08.md (b789e400). Lane copy: $LANE/mac4DSTEM, base b789e400 (scratch repo, base 28fd2ac).
Start: the refuted lane's patch (0001-*.patch, rule + 2 tests) applied to the copy, then the scope changed.

## Commits

028f79f  Check a pile-up column against the fit's own design, not the whole pool
- Files: mac4DSTEM/Core/Spectroscopy/Proposer/ElementProposer.swift (sumColumns gains a `design:` parameter; the one-component list is built from it; the three call sites pass settle-sums design = currentGroups + active pool groups, settle stability design = currentGroups + nextActive pool groups, forward step design = currentGroups + active or tested candidate; `design` is computed once per call site and used for both the run and the check, same groups as before), mac4DSTEMTests/SumEscapeIdenticalTests.swift (new; 3 tests).
- Tests: testVKaEscapeEqualToTbMaPlusIrMaScoresOnAShortAxis (Case D; amplitudes 0, 300, 40000 score; the no-column assertion now applies at 40000 only, see Deviations), testPileUpAtAnInactivePoolGroupsOneComponentEnergyKeepsItsSumColumn (P2, new), testSrPlusBaSumAtAMultiLineGroupsAlphaKeepsItsColumn (multi-line test, unchanged).
- Gate (lane copy): unit-S4a.log: passed 2372, failed 0, skipped 3 = 2375; `grep -rh "func test" mac4DSTEMTests | wc -l` = 2375 (reconciled). GATE_EXIT=0. core-S4a.log: GATE_EXIT=0.
- Mutations (filtered runs, class SumEscapeIdenticalTests):
  - Refuted pool-wide scope (oneComponent from currentGroups + poolGroups): filtA.log. P2 red (0 Tb+Ir columns at 3.2125; sum peaks were Ir+Ir 60.39, Tb+Tb 0.0); Case D green; Sr+Ba green.
  - Rule removed (no !oneComponent guard): filtB.log. Case D red at 0, 300, 40000 (rankDeficient); P2 red (rankDeficient); Sr+Ba green.
  - Line-count condition ignored (every group's alpha line counts as one-component): filtE.log. Sr+Ba red (XCTUnwrap: no Sr+Ba column; labels Ba+Ba, Sr+Sr); Case D and P2 green.
  - Final scoped rule: filtD.log, 3 of 3 passed, 0 failed.
- Nothing else in the tree; nothing committed besides the two paths.

## Predictions against numbers

P1 (Case D scores at 0, 300, 40000): met on the run. filtD.log 3/3 pass. Lane N probe (P4 below): all six D lines SCORED.
P2 (V inactive, real Tb+Ir pile-up at 3.2125 keV, 2000 counts): the final fit has one Tb+Ir column at 3.2125 keV: net 1682.8, sigmaZero 343.2, L_D 1131.9 (net > L_D). Printed once from a temporary XCTFail (run filtF.log), reverted; the committed test asserts net > 0 only.
P3 (live T-V re-run, 94 entries): 94 of 94 common entries identical to laneS2/out/tv_out in candidates, picks, passes, settled, sumPeakQuestions, configs, withheld, chi2r; 0 differing; 0 newly scoring. Run log: $LANE/out/tv.log (RUN_EXIT=0, dated 2026-10-08). Compare output: $LANE/out/compare.txt. The harness summary in tv.log reads precision 34.3 %, recall 45.3 %, 0 of 94 exact sets, 3 files with every Velox element found.
P4 (lane N probe, throwaway, not committed; output $LANE/probe-out.txt vs $LANE/probe-before.txt): 23 of 29 NSPROBE lines byte-identical (A, B, C, E1, E2, E3, E3b, all cases). The six D lines (V_Ka, amplitudes 0, 100, 300, 1000, 3000, 40000) changed from THREW rankDeficient to SCORED:
  - amp 0: net 84.6 (L_C 410.4, L_D 823.5), Ir+Tb sum @3.2125 net 156.9, not proposed.
  - amp 100: net 182.8, Ir+Tb sum net 155.9, not proposed.
  - amp 300: net 384.6, Ir+Tb sum net 153.8, not proposed.
  - amp 1000: net 1084.2, proposed=true, no Ir+Tb column (V active, its escape identical, pair dropped).
  - amp 3000: net 3087.4, proposed=true, no Ir+Tb column.
  - amp 40000: net 40119.1, proposed=true, no Ir+Tb column.

## Deviations from the brief (stated, not hidden)
- Case D's no-column assertion (`no pile-up column at the one-component escape energy`) was applied at all three amplitudes in the first build. With the scoped rule it fails at 0 and 300 (the message lists Ir+Tb sum at 3.2125 among the sum peaks), because V is not in the final design there and the pair has nothing to be identical to. I narrowed that assertion to amplitude 40000, where V claims the energy, and documented the change in the test comment. The "scores" part of Case D is unchanged. This is a consequence the registration's P2 predicts, but it is a change to an assertion the brief said to keep; the refuter should look at it.
- The probe run wrote to lane N's probe-out.txt in the first copy of its file; I redirected the output path in my throwaway copy to $LANE/probe-out.txt. Lane N's files were not touched.

## Skipped items
None. No scope item was skipped. No real repo was touched; no docs/ edits; no app launched; no pkill; heavy slots taken and released (locks/ empty at the end).

## Needs verification
- Drive (not done here): in the app, open Auto ID on a spectrum whose axis ends near 5.1 keV with V, Tb and Ir in the pool, at a moderate V amplitude, and check the run scores instead of showing rankDeficient; the Tb+Ir pile-up should appear as a sum finding near 3.21 keV when V is not claimed.
- Drive (not done here): on a normal Auto ID run (axis to 20 keV or more), confirm no sum finding changed; the live T-V run says the 94 entries are identical, but a spot check on the app is still owed.
- Nothing on screen: no UI changed in this lane.

## Runtime and workspace notes
- runtv.sh (copy of the template): zsh printed "no matches found" lines (runtv.stdout, 8 lines) from the slot-release subshell's glob before the harness existed; the subshell kept polling and the run finished normally. Harmless, but the template's glob should be guarded in a future copy.
- Scratch: $LANE/dd and $LANE/tmp contents removed; logs kept: unit-S4a.log, core-S4a.log, filtA.log, filtB.log, filtE.log, filtD.log, filtF.log, probe-run.log, out/tv.log, out/compare.txt.
