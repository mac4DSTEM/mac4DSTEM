# Refuter report: lane S3, one-component sum rule (commit 526c6d7, base cb0edf0b)

Verdict: REFUTED as built (scope of the rule). Numbers P1, P2, P3 UPHELD.

1. Rule definition holds where the registration's argument applies. EDSModel.build clips group lines and escapes to the axis
   (defaultLines + linesInRange, EDSModel.swift:81-83; escapes :84-92). At axis top 5.115 V K-beta (5.4273) is absent, so V has
   lines = [V_Ka]. At 5.495 (control E3) it has two lines, the rule is off, and the Ir+Tb column stays (net 65.1). LinearDesign builds
   one escape column per group (LinearDesign.swift:90-94), so escapes.count == 1 is the right one-Gaussian test.
2. BREACH: the rule checks currentGroups + poolGroups, not the groups in the pass's design. A settle pass has active groups only
   (ElementProposer.swift:301); the forward test has active + the tested candidate (:352). An inactive pool candidate has no column at
   its energy in that pass, so the pile-up is the only column there and is not a duplicate. The rule drops it anyway.
   Observed: probe-after.txt amp 0 (V not proposed; V pruned in settle per the diagnosis) gives final sumColumns = [Ir+Ir 3.9598,
   Tb+Tb 2.4652]; Tb+Ir at 3.2125 is gone. The sum findings come from the final fit (:392-397). So a real Tb+Ir pile-up at 3.2125
   with V absent gets no column and no sum finding. Pre-fix that case threw, so there is no earlier output to compare.
   The registration's argument ("the two columns would be identical") does not cover it. Its P1-P3 and refuting observations
   do not test it. The lane's "Nothing else changes" premise is wrong for inactive candidates.
3. Effect (code-derived, not run): with V inactive, the pile-up is unmodelled in the final fit (chi2r rises, no sum finding). With V
   active, V's escape column absorbs it silently. V's net is its alpha area only, so V is not phantom-proposed, but the sum
   explanation is gone. This is the "silently gone" outcome the brief asked about.
4. Test gap: no test has an inactive candidate, and neither mutation run catches it. Needed: plant a Tb+Ir pile-up (about 2000
   counts) at 3.2125 on the 5.115 axis with V absent, and assert a Tb+Ir sum finding. Predicted red on this code. Fix: pass the
   pass's design set (active + tested candidate) into sumColumns, then re-run the probe, the 94-entry compare and the new test.
   The scope choice goes to the owner as a sheet (ADR 050).
5. P2: compare.py re-run exits 0, and its output is identical to out/compare.txt (diff empty). Non-vacuous: 94 common entries,
   6862 candidates, 94 with picks. My full-JSON deep equality over all 21 keys: 94/94 identical. The 94 .u64 spectra are
   byte-identical, and the 189 file names match. Limit: the JSON stores sumPeakQuestions, not sum nets, so finding 2 is invisible to it.
   Premise error: the 94 axis tops are 19.99 to 79.97 keV, not about 20, and none lies in [5.0, 5.5). The conclusion still holds: the
   census's 13 coincidences have 6 or more family lines on 0-14.99 keV, and counts only grow with the axis top. Restate the
   premise as at least 15 keV.
6. P1/P3 (probe-diff.txt re-checked): only the six Case D lines change (THREW rankDeficient to SCORED). The 23 other lines (A-C,
   E1-E3b, the D shape line) are byte-identical. The green test covers amplitudes 0, 300 and 40000.
7. Tests: filt-red EXIT 65, with testVKaEscape... failed (three "Failing tests" entries, one per amplitude) and testSrPlusBa passed.
   The assertion text is not in the log (xcresult only), so "rankDeficient at 0/300/40000" is the lane's word. filt-green EXIT 0, both
   pass. filt-mutB EXIT 65: the multi-line test fails and Case D passes, so the mutation is caught by the multi-line test.
8. Unit: unit-1.log has 2371 passed, 0 failed, 3 skipped = 2374. grep -rh "func test" over mac4DSTEMTests = 2374 (lane tree too).
   GATE_EXIT=0. unit-1.log has no NonSumCoincidenceProbe hits, and the probe is absent from the lane tree. Tree of 2692d9c =
   526c6d7 (amend changed the message only). Base ElementProposer.swift blob = main cb0edf0b. core-1.log GATE_EXIT=0.
9. Minor: one-component counts use the axis, but the design uses the fit window (fitFrom 0.2; fitTo from defaultFitTo). A component
   above fitTo but inside the axis is counted, so the rule can stay off where the design is effectively one column. No reachable case
   found (tails keep the column non-zero). Flag only.
