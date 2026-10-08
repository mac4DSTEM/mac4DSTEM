# Lane S3 report: the registered one-component sum rule (Gate D item; numbers only, no verdict)

Commit: 526c6d7 "Stop a pile-up column that is identical to a one-component column" on the lane copy's main (base cb0edf0b).
Files: mac4DSTEM/Core/Spectroscopy/Proposer/ElementProposer.swift (sumColumns only, +7 lines);
mac4DSTEMTests/SumEscapeIdenticalTests.swift (new class SumEscapeIdenticalTests, 2 tests, 92 lines).
Registration: docs/archive/v5/sum-escape-identical-preregistration-2026-10-08.md (cb0edf0b). Diagnosis: docs/archive/v5/sum-escape-coincidence-diagnosis-2026-10-08/report.md.
History: first commit 2692d9c had a message sentence I could not support; amended to 526c6d7 (same tree).

## The rule as built
sumColumns skips a pair whose energy is within 1e-9 keV (exactSumToleranceKeV) of a one-component column of a
current or pool group: lines.count == 1 gives lines[0].energy; escapes.count == 1 gives escapes[0].energy.
Uses currentGroups + poolGroups (all, as registered), not only active or claiming groups. Multi-component groups are never compared.

## Tests and mutations (filtered runs, -only-testing:mac4DSTEMTests/SumEscapeIdenticalTests)
- Old code (new tests, no rule): filt-red.log, EXIT=65. testVKaEscape... failed at amplitudes 0, 300, 40000 with
  "the run must score, not throw: rankDeficient". testSrPlusBaSum... passed.
- Fixed code: filt-green.log, EXIT=0. Both tests pass.
- Mutation B (one-component condition ignored: lines.isEmpty / escapes.isEmpty instead of count == 1): filt-mutB.log, EXIT=65.
  testSrPlusBaSumAtAMultiLineGroupsAlphaKeepsItsColumn fails (its Sr+Ba column is dropped); the Case D test still passes.
  File restored and cmp-checked against the good copy.

## Gates (lane copy, shared slot, per RULES2)
- Unit: unit-1.log, GATE_EXIT=0. passed 2371, failed 0, skipped 3; total 2374 = count of "func test" in the copy. Reconciles.
- Core: core-1.log, GATE_EXIT=0.

## P3: lane N probe on the fixed code (throwaway, removed from the lane before commit; not committed)
probe-filt.log EXIT=0, all 5 methods passed. probe-before.txt (29 lines) vs probe-after.txt (29 lines): probe-diff.txt.
- Identical: 23 of 29 lines (cases A, B, C, and controls E1, E2, E3, E3b, plus the D shape line).
- Changed: 6 lines, all Case D (V K-alpha escape, axis top 5.115 keV). Before: THREW rankDeficient at amp 0, 100, 300, 1000, 3000, 40000.
  After: SCORED. Amp 0: V net 84.6, L_C 410.4, L_D 823.5, not proposed. Amp 100: net 182.8, not proposed.
  Amp 300: net 384.6, not proposed. Amp 1000: net 1084.2, proposed. Amp 3000: net 3087.4, proposed. Amp 40000: net 40119.1, proposed.
  All six: sumColumns = [Ir+Ir 3.9598 net 0.0, Tb+Tb 2.4652 net 0.0]; the Tb+Ir column at 3.2125 is gone; passes 2, settled true.
  Amplitudes 1000 and 3000 are not in the registered P1 set; reported for completeness.

## P2: live T-V re-run (read-only on the owner's drive; output in lane only)
- Run: runtv.sh (copy of runtv-template.sh, laneS2 -> laneS3). Slot heavy.1 held, released by the template's background subshell
  once the harness started. Log out/tv.log ends RUN_EXIT=0. Wrote out/tv_out (94 entry json, plus summary.json, plus 94 .u64).
- Scored entries: 94. Failed lines: 0 (grep of tv.log for fail/throw/rankDeficient/error: none).
- Field-by-field vs laneS2/out/tv_out (compare.py, out/compare.txt): common entries 94; identical in candidates, picks, passes,
  settled, sumPeakQuestions, configs, withheld, chi2r: 94. Different: 0. Only in old: 0. Only in new: 0. Newly scoring: 0.
- Changed entries: none.

## Other notes
- The Monitor on tv.log expired once after 30 min with no event (run still going, harness alive); re-armed; RUN_EXIT=0 seen.
- $LANE/dd (filtered-run DerivedData) remains in the lane; $LANE/tmp was cleared after the unit and core gates.
- The lane repo is clean (git status empty) after the commit.

## Needs verification
- Refuter (independent, read-only) to review the diagnosis, the rule, and the numbers above. No verdict here.
- A drive is not in this lane. On the owner's build, Auto ID on a spectrum with axis top about 5.1 keV and V, Tb and Ir detected
  should run instead of failing with rankDeficient; no screen change is expected (commit says "nothing on screen").
