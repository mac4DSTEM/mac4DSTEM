# Lane W, WP4b: measurement built as registered, run, tabulated (2026-10-07)

Registration (binding, unchanged): docs/archive/v5/wp4b-autoid-rules-preregistration-2026-10-07.md (03780df0).
Scratch repo: $LANE/mac4DSTEM (base 619b0c6 = 03780df0 copy). The real repo was not touched. No app launched, nothing killed.
Full tables: $LANE/out/wp4b-tables.md (regenerated after the fix in 3d66dd2). Partial tables (T-Q, T-S, demo): $LANE/out/wp4b-partial.md.

## Commits (scratch repo, apply with format-patch / git am; none is on the real main)

| hash | subject | files | gate |
|---|---|---|---|
| c19f300 | Add the WP4b beside-K evidence guard to ProposalRules as an option | Core/Spectroscopy/Proposer/ProposalRules.swift, mac4DSTEMTests/AutoIDRulesWP4bTests.swift | unit-1.log 2320/0/3 = 2323, GATE_EXIT=0; core-1.log GATE_EXIT=0 (from the earlier session; not re-run) |
| 8de58b9 | Build the WP4b measurement tooling as registered: rule sets and harness outputs | tools/autoid-velox-check/main.swift, qual_prep.py, risk_sim.py, wp4b.py | unit-2b.log 2320/0/3 = 2323, GATE_EXIT=0; core-2.log GATE_EXIT=0 (see the flake below) |
| 3d66dd2 | Count the R2 hypothesis's T-S refuting observation at planted net/L_D >= 3 | tools/autoid-velox-check/wp4b.py | not applicable (Python reporting only) |

Shipped and registered behaviour: ProposalRules.shipped and .registered are unchanged; besideKGuard defaults to false everywhere (c19f300 tests).

### Flake in the commit-2 gate (not closed)
The first full unit run for 8de58b9 (unit-2.log) ended GATE_EXIT=65 with one failure: SpectroscopyProposerTests.testKramersContinuumNoFalseMgAndTheDetectionRate, reported at 0.000 s with no assertion text in the log (the xcresult was in the run's deleted temp dir). Re-running the single class (proposer-filt.log, with -resultBundlePath) passed, and a second full run (unit-2b.log, GATE_EXIT=0, 2320 passed, 0 failed, 3 skipped) passed. The cause is NOT established. At the time, machine load average was about 30 (other sessions and the live T-V run). The commit message of 8de58b9 says so. A supervisor should decide whether a re-run is enough to close this; I did not treat it as closed by a green rerun alone.

Gate notes: the Core run and both unit runs were under a heavy slot (slot 1), released after each run. No xcodebuild was started while the drive lock existed (lock seen at 22:33, cleared before my core gate).

## Runs (dates 2026-10-07, logs in $LANE/out/)
- T-Q: qual_prep.py (31 MSA from the unpacked DTSA-II Qual set) then run.sh --ladder; tq.log, ended 22:22. Default resolution 130 eV: the MSA headers state none (only #EDSDET: SIUTW).
- T-S: risk_sim.py (seeded, 200 kV, owner axis, Al matrix; 30 pair cases + 4 ghosts, one seeded draw per case) then run.sh --ladder; ts.log, ended 22:04. Doses from the calibration run ts_calib (ts_calib.log, 22:02).
- Demo ladder: 8 regions, demo.log, ended 22:23.
- T-V: run.sh --out tv_out /Volumes/PL_SSD_2TB/NAS_Backup/01_projects (live, no --h4), pid 68431, 22:26 to about 23:10, exit 0 (tv.log last line). Read-only on the owner's files. The drive stayed mounted throughout.
- wp4b.py --tq tq_out --ts ts_out --demo demo_out --tv tv_out, run 23:11, exit 0.

Reconciliation of T-V: the run's own start line says 112 file(s); scored 88 entries; 17 skipped without a stored selection; 1 refused (SI HAADF 1800 23000 x 20260423.emd, not a Velox EMD spectrum image); 6 entries failed in the app with harness.ProposerError error 2 (0944, 1121, 1140, 1253; not investigated). tv_out holds 88 JSON + summary.json, which matches "scored files 88". wp4b dedups by (basename, totalCounts): 78 distinct, the registration's number. Acquisition dates: the run wrote a date from file metadata for all 88 entries (acquiredSource = metadata). The registration's "43 owed dates" is not reproduced as a count here.

## Tables (precision/recall as wp4b.py prints them; hits are counted per truth element)

T-Q, all 31 spectra, truth as the answers file gives it (includes Li, B, which the proposer cannot reach):
| rule set | picks | hits | false | precision | recall |
|---|---|---|---|---|---|
| base (shipped) | 241 | 130 | 111 | 53.9 % | 55.1 % |
| R1b | 187 | 130 | 57 | 69.5 % | 55.1 % |
| R2 | 150 | 122 | 28 | 81.3 % | 51.7 % |
| R1bR2 | 149 | 122 | 27 | 81.9 % | 51.7 % |
Class easy (5): base 14 hits, R1b 14, R2 14, R1bR2 14. Class moderate (6): 22 / 22 / 22 / 22. Difficult (13): 61 / 61 / 59 / 59. Very difficult (7): 33 / 33 / 27 / 27. Truth without the unreachable Li and B: same hits, recall 56.8 / 56.8 / 53.3 / 53.3.

T-S pairs (30 spectra): base 74 picks, all true, recall 82.2 %; R1b 63, recall 70.0 %; R2 67, recall 74.4 %; R1bR2 61, recall 67.8 %. False picks: 0 in every set. Ratio >= 1 (20 spectra): base recall 81.7 %, R1b 75.0 %, R2 75.0 %, R1bR2 71.7 %. Ratio 0.3 (10): base 83.3 %, R1b 60.0 %, R2 73.3 %, R1bR2 60.0 %.
Full per-case table (planted and realised net/L_D, which element each set kept): wp4b-tables.md, section "T-S: ... Pairs".
Ghosts (4, Cu/Ga/As/Ar on Al at high dose): every set returns Al plus the K element (Ar: Al only). 0 false picks in any set.

Demo ladder (8 regions): base 18 picks, 15 hits, 3 false, precision 83.3 %; R1b same; R2 17 picks, 15 hits, 2 false, 88.2 %; recall 38.5 % for all (truth 39).

T-V (agreement with the owner's Velox selections, not truth; 78 distinct):
| rule set | picks | hits | false | precision | recall |
|---|---|---|---|---|---|
| base | 530 | 184 | 346 | 34.7 % | 45.5 % |
| R1b | 469 | 184 | 285 | 39.2 % | 45.5 % |
| R2 | 365 | 180 | 185 | 49.3 % | 44.6 % |
| R1bR2 | 364 | 180 | 184 | 49.5 % | 44.6 % |

## Each registered refuting observation, with the numbers

### H5 (R1b is safe where the guard says)
Refuting observations, as written: (1) a true element at ratio >= 1 dropped; (2) a hit lost on T-Q or T-V; (3) no false pick removed anywhere.
- (1) MET. Four true L elements at ratio >= 1 dropped by R1b (candidate net/L_D of L vs K; planted in brackets):
  - Hf La + Cu Ka, ratio 1, low dose: Hf 1.17 vs Cu 1.5 (planted 1.61 vs 1.50). Guard drops Hf (1.2 <= 1.5).
  - Ta La + Cu Ka, ratio 1, high dose: Ta 4.43 vs Cu 4.5 (planted 6.00 vs 7.42). A near-tie: the guard decides on 0.07 net/L_D.
  - Pt La + Ga Ka, ratio 1, low dose: Pt 1.60 vs Ga 2.2 (planted 1.50 vs 2.11).
  - Pt La + Ga Ka, ratio 1, high dose: Pt 6.51 vs Ga 7.3 (planted 6.00 vs 8.45).
  Two of the four have planted L net/L_D of 6.0 (Ta high, Pt high), so the drop is not only at low planted levels.
- (2) not met: T-Q hits 130 to 130; T-V hits 184 to 184.
- (3) not met: 54 false T-Q picks and 61 false T-V picks removed (115 in total). On T-S the baseline makes no false pick, so none can be removed there.
- Admitted cost at ratio 0.3 (the registration's stated cost, not a refutation): R1b drops the true L in 7 cases: Hf low (1.30) and high (4.81); Ta low (1.55) and high (3.91); Pt low (1.78) and high (6.93); Pb high (3.63).
- Ghosts: 0 of 0. The baseline makes no false L/M pick beside any K ghost (Al+Cu, Al+Ga, Al+As, Al alone), so R1b has nothing to remove there. The registration's ghost clause cannot be tested with this set.
- Ag La + Ar Ka: no set picks Ag or Ar, the baseline included (see notes), so this pair adds nothing to H5.

### H6 (R2 holds off its fit set)
Refuting observations, as written: (a) T-Q precision does not rise; (b) an easy or moderate T-Q hit is lost; (c) T-V loses more than one hit. Also a T-S clause: no true element with planted net/L_D >= 3 lost.
- (a) not met: T-Q precision 53.9 % to 81.3 % (truth as given).
- (b) not met: easy 14 to 14, moderate 22 to 22. Hits lost by R2 overall: 8, all in difficult or very difficult: Pb 2.80 (K1001), Ta 2.02 (K489), I 2.46 (K1053), Zr 1.04 (K493), Ba 1.23 and Zr 1.10 (K523), Ba 1.93 and Eu 1.08 (K968). Each is R2's "x L_D < 3" bar.
- T-S clause: met. R2 drops 9 true elements in total (R2's own drops, including the R1b+R2 set's R2 drops). All nine have planted L net/L_D between 1.5 and 1.67, so 0 with planted >= 3. Cases: Hf low, Hf r1 low (1.61), Ta r0.3 low, Ta r1 low, Pt r0.3 low, Pt r1 low, Pb r1 low (1.67, candidate 2.9). The Ta r1 low and Pb r1 low entries also appear in R1bR2.
- (c) MET: R2 loses 4 T-V hits (184 to 180): SI HAADF 1549 Pt (candidate 2.76), 1020 Ge (2.45), 1100 Ni (2.20), 1253 In (1.36). The registration says refuted at more than one. T-V is agreement with Velox, not truth: a lost hit means the Velox element was no longer in the app's picks. R1bR2 loses the same 4.

Both H5 and H6 have their first clause met as written. Which rule ships is not decided here; that is for the independent refuter.

## Places a number could mislead
1. T-Q is 25 kV SEM bulk glass at 10 eV per channel, not 200 kV thin film. The resolution used (130 eV) is the harness default, because the headers state none. The truth includes Li and B (7 elements the proposer cannot reach); both versions are in the tables. Classes are small (5, 6, 13, 7 spectra).
2. T-V is agreement with the owner's Velox selections, not truth. Duplicate files exist in different folders; wp4b collapses identical (basename, totalCounts). Six entries (4 names) failed in the app with ProposerError error 2; not investigated.
3. The risk simulator plants line areas, but the realised net/L_D differs from the planted value, sometimes a lot: Pb r1 low planted L 1.67, realised 2.89; Hf r0.3 high planted 6.00, realised 4.81. H6's T-S clause uses the planted level (as registered); the rules act on the realised one. One seeded draw per case, two doses. The dose choice came from a separate calibration run (ts_calib.log), which I did not re-check.
4. Ag Lα + Ar Kα: no rule set (baseline included) picks either element. Ar Kα (2.958 keV) and Ag Lα (2.984 keV) sit beside the 2 x Al Kα sum peak (2.973 keV). Both are flagged sumPeak and sumQuestion by the proposer's own logic, so the pair tests that logic, not R1b or R2. In the Ag+Ar ratio-0.3 low case the realised Ar net/L_D is 6.73 and Ag 1.63, both withheld with the sum-peak question. The Ar ghost (planted 48.8) is picked by no set either. This is not a rule effect, and I have not changed it.
5. Ghosts test nothing about the guard (zero baseline false L picks), as noted under H5.
6. wp4b.py's H6(b) count had a label that promised a planted filter the code did not apply (it printed 20). Fixed in 3d66dd2: the count now filters on planted L net/L_D >= 3 and counts only R2's own drops. The registration's number is 0.
7. The T-V dedup key is (basename, totalCounts): a true duplicate file with a different total would be counted twice. I did not check that case.

## Needs verification (for the supervisor)
- Commit-2 gate flake: confirm the cause or accept the rerun explicitly (see above).
- Refuter: an independent read of wp4b-tables.md against the registration, in particular the H5 near-tie (Ta r1 high) and whether the registration's ghost clause should count as untestable.
