# Refuter report: lane S4, design-scoped sum-vs-one-peak rule (commit 028f79f, base b789e400)

Read-only, independent. No build, no app run, no /Volumes access. Scratch scripts: refuter_compare / refuter_fulljson.py / refuter_scan*.py in the scratchpad.

Verdict: UPHELD WITH NOTES.
The registered gate holds: scope as registered, P1 to P4 met, the refuting observations did not occur, mutations red where claimed. Two things need the owner before this lands: (a) the registration's P3 premise is false (a one-line-alpha coincidence exists inside the 19.99 to 79.97 keV range, La Ka = Cd Ka + Tl La at 33.4419 keV), and (b) that alpha branch is untested. Decision sheet item, not a code fix.

1. Scope: UPHELD. Three call sites only (lane HEAD lines 309, 332-334, 363); no other sumColumns caller in mac4DSTEM or mac4DSTEMTests (the other grep hit is a doc comment in SumColumnDedupTests.swift:4).
   - settle sums: design = currentGroups + active pool groups; run(design + sums) and sumColumns(design:) share it.
   - settle stability: design = currentGroups + nextActive pool groups; this is the next pass's own run design, so the check matches what that pass would fit.
   - forward step: design = currentGroups + active + candidate; claimers = claiming(active) union {candidate}; run and check share it.
   - Main's ElementProposer.swift blob is 1ce2227, the lane base, so the patch applies cleanly to main.
2. Case D deviation: consistent with P1 (scores only). Amp 0 and 300 keep the Ir+Tb column (net 156.9 and 153.8, not proposed); V is pruned (net 384.6 < L_C 410.4). That is the intended behaviour. Case D plants no Tb+Ir pile-up, so the 157-count column there fits residual, the same as any non-coincident sum column (pre-existing behaviour, not an artifact of the fix).
   - Narrowing the column-absence assertion to 40000 is a change, not in the registration. filtC.log (not named in the report) is red at two amplitudes with the all-amplitude assertion, which matches that.
   - Weakness: amp 1000 and 3000 are also V-active (probe: proposed=true, no Ir+Tb column) and could carry the assertion. Gate on "V in final design", not on an amplitude.
   - Registered consequence, owner-facing: with V detected, a real Tb+Ir pile-up at 3.2125 is absorbed by V's escape column with no sum finding.
3. P2 test: UPHELD. Plants 2000 counts Gaussian at 3.2125 with the law FWHM, Tb and Ir at 40000 each, V in pool at 0; asserts one column at the Tb+Ir energy, elements {Tb, Ir}, net > 0.
   - filtA (pool-wide scope): P2 red, Case D and Sr+Ba green. filtB (rule removed): Case D (three entries) and P2 red, Sr+Ba green.
   - Weakness: net > 0 only. filtF measured net 1682.8 against L_D 1131.9; not asserted (matches the registration's wording).
4. Comparator: UPHELD. Re-ran compare.py with python3 -I: exit 0, output identical to out/compare.txt (diff empty). compare.py checks ten keys; my full check covered all 21 keys of the 94 common entries: 94/94 deep-equal, 189 files byte-identical, filenames identical, no only-old or only-new files.
5. Probe: UPHELD. probe-before.txt vs probe-out.txt: only lines 24 to 29 differ, the six D lines (THREW rankDeficient to SCORED). The 23 other NSPROBE lines are byte-identical.
6. Gates: UPHELD.
   - unit-S4a.log: 2372 passed, 0 failed, 3 skipped = 2375 (counted from the per-test lines), GATE_EXIT=0. grep "func test" in the lane tree = 2375; main tree = 2372; 2372 + 3 new tests = 2375. Reconciled.
   - core-S4a.log: GATE_EXIT=0.
   - filtD (final): 3/3 pass, EXIT=0.
   - filtC, filtF: EXIT=65, the expected red runs (filtF is a temporary XCTFail that prints the net).
7. Unforeseen, material: the alpha branch of the one-component rule reaches a reachable coincidence. Not refuted by the registered gate, but the registration's P3 premise is wrong.
   - Found by a Python scan of the line table (XRayLineData.swift). Scan validated: it reproduces the known V-escape case exactly (x = 3.2125, T in [4.952, 5.427)).
   - Exact coincidences with one-line targets over 0.5 to 80 keV: two. (a) V Ka escape 3.2125 = Tb Ma + Ir Ma (the known case). (b) La Ka 33.4419 = Cd Ka 23.1737 + Tl La 10.2682; La Kb at 37.8012 is the next line, so La's K group is one Gaussian for T in [~33.5, 37.80).
   - La, Cd and Tl are in the real defaultPool (defaultExcluded and refusal do not list them).
   - P3 premise ("no one-component column coincides with a pair sum on the 19.99 to 79.97 axes") is false for T in [33.44, 37.80). The 94 identity still holds because no owner axis top lies within 0.5 keV of that window (top = offset + scale*(channels-1): min 19.993, max 79.971).
   - Consequence where it fires: a real Cd+Tl pile-up is dropped and its counts are fitted by La's alpha column, inflating La's net (false-La risk). Pre-fix this threw rankDeficient when La is active and not claiming; post-fix it is silent. The existing claimed rule already attributes pile-ups to claiming candidates, so the policy has precedent, but the new rule reaches non-claiming active candidates.
   - No test covers the alpha term. Only the escape branch is exercised (Case D). Dropping the alpha term should survive the current suite (predicted by reading, not run: no build allowed).
   - Required before landing: an owner decision (sheet). Either accept the alpha branch with the La/Cd+Tl limitation stated, or restrict the rule to escapes. If accepted, add a La/Cd+Tl test (predicted: column dropped, net attributed to La) and its mutation.
8. Latent, inert today: ReferenceShapes.lineAmplitude folds f*profile into a group's column (LinearDesign.swift:81-83), so a one-line group with a tie is no longer one Gaussian. The rule ignores ties and would drop a non-identical pile-up. Shapes ship empty ("reference shapes: none"), so nothing is reachable now. Guard it when a shape is first tied.
9. Minor, flagged before (refuter 1, item 9): one-component uses the axis window, the design uses the fit window. Flag only.
10. Not run, by design: no build, no app, no drive. Live-run numbers are from tv.log (RUN_EXIT=0, dated 2026-10-08), which matches laneS2 (precision 34.3 %, recall 45.3 %, 0 of 94 exact, 3 files with every Velox element).
