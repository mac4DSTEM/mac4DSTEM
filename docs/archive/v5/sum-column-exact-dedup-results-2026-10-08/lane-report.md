# Lane S2 report: exact duplicate sum-peak columns (registered fix, measured; no verdict)

Registration: docs/archive/v5/sum-column-exact-dedup-preregistration-2026-10-08.md (committed de43f673 before the build).
Scratch repo: $LANE/mac4DSTEM, base 31be24b = main de43f673. Gate D applies; this report gives numbers only.

## Commit
- d2b086a "Merge exactly coinciding sum-peak columns in one proposer pass"
  - Core/Spectroscopy/Proposer/ElementProposer.swift (+22/-6): `sumColumns` merges a pair into an existing column only when
    `abs(energy difference) <= exactSumToleranceKeV`, a local `let exactSumToleranceKeV = 1e-9` with the one-line comment
    (equality to rounding; table has four decimals; registration named). Id and label name every pair; union of elements;
    a lone pair keeps its plain id, label and elements (as in the refuted lane, minus the 0.06 tolerance).
  - mac4DSTEMTests/SumColumnDedupTests.swift (new, 3 tests; file name per the lane brief's write set, not the RULES2 pattern):
    testTwoCoincidingSumPairsScoreAndTheKeptColumnNamesBoth (P3), testALonePairKeepsItsPlainLabelAndElements,
    testNearPairsFourHundredEVApartStayTwoColumns (new).
  - Near pair, from the line table: Si_Ka + Ti_Ka = 1.7397 + 4.5109 = 6.2506 keV; Ca_Ka + Ru_La = 3.6917 + 2.5585 = 6.2502 keV; gap 0.0004 keV.

## Gate and mutations (lane copy)
- Filtered, new code: filt-new.log, 3/3 passed, EXIT=0.
- Mutation A (merge disabled: condition `<= -1.0`): filt-mutA.log. testTwoCoincidingSumPairs... FAILED with
  "the run must score, not throw: rankDeficient" (read from the xcresult). Other two passed. EXIT=65. Restored, cmp OK.
- Mutation B (constant set to 0.06): filt-mutB.log. testNearPairsFourHundredEVApartStayTwoColumns FAILED (the two-column
  assertion; message text not extracted from the xcresult). Other two passed. EXIT=65. Restored, cmp OK.
- Full unit: unit-1.log, GATE_EXIT=0. passed 2369, failed 0, skipped 3, total 2372 = `grep -rh "func test" mac4DSTEMTests | wc -l` (2372).
- Core: core-1.log, GATE_EXIT=0 (run-tests.sh core prints no XCTest lines).
- xcodebuild printed "error: the following command failed with exit code 0 but produced no further output" lines on
  the filtered runs; every EXIT was 0 or the registered failure, so these were not read as failures.

## Measurement (read-only on the owner's drive; output in $LANE/out)
- Runner: $LANE/runtv2.sh (heavy slots in locks/heavy.N, waits while locks/drive exists; none existed). Harness built from the
  lane copy (includes d2b086a). RUN_EXIT=0. Log: out/tv.log. Output: out/tv_out (94 scored JSON pairs).
- Harness summary (tv.log): 112 files; 94 scored; 1 refused (SI HAADF 1800 23000 x 20260423.emd, not a Velox EMD spectrum
  image); 17 skipped without a stored selection; velox elements 499, app picks 659, hits 226; precision 34.3 %, recall 45.3 %;
  files with the exact set 0 of 94; with every Velox element found 3.
- compare.py -> out/compare.txt: old entries 88 (laneW/out/tv_out), new 94; old-only 0; new-only 6;
  common 88 entries: identical (candidates, picks, passes, settled, sumPeakQuestions, configs, withheld, chi2r) 88; different 0.
  No changed candidates and no changed picks, so nothing to list.

### The six previously failing entries (new-only), vs Velox truth (hit/velox; extras = picks not in Velox)
| file (json) | Velox elements | app picks | hit | missed | extra | settled | passes |
|---|---|---|---|---|---|---|---|
| SI HAADF 1253.emd (60) | O Si Cu Ag In Sn Pt | Cu Pt Ag Si In Ga O Zr | 6/7 | Sn | Ga, Zr | True | 47 |
| SI HAADF 1140.emd (63) | C O Si Cu Ag In Sn Pt | Cu In Si Ag Br Zr O Pt Sm Eu Th As | 6/8 | C, Sn | Br Zr Sm Eu Th As | False | 47 |
| SI HAADF 0944.emd (82) | N Si Ti Cu Nb Pt | Si Zr Ga S V | 1/6 | N Ti Cu Nb Pt | Zr Ga S V | False | 58 |
| SI HAADF 0944.emd (87, 2nd copy) | N Si Ti Cu Nb Pt | Si Zr Ga S V | 1/6 | N Ti Cu Nb Pt | Zr Ga S V | False | 58 |
| SI HAADF 1121.emd (85) | B N Si Ti Nb | Cu Ti Si Nb Hf Cr Ba Co Zr | 3/5 | B N | Cu Hf Cr Ba Co Zr | False | 56 |
| SI HAADF 1121.emd (86, 2nd copy) | B N Si Ti Nb | Cu Ti Si Nb Hf Cr Ba Co Zr | 3/5 | B N | Cu Hf Cr Ba Co Zr | False | 56 |

All six scored with no failed line. The "settled" flag and pass counts are as the harness wrote them (settled False = the
backward step hit maxPasses = 5 in some settle call, per the proposer's own note). Picks are reported, not gated.

## Predictions and refuting observations (registered)
- P1 (six entries score, no error): the six scored; "failed" lines in tv.log: 0. Held as measured.
- P2 (the 88 entries that scored on 2026-10-07 are byte-identical in candidates and picks): 88 of 88 identical. Held as measured.
- P3 (synthetic Dy/Ti/Cs/Ho throws rankDeficient without the fix and scores with it): filt-new passes; mutation A throws
  rankDeficient. Held as measured.
- Refuting observations registered: any of the six still failing (none); any of the 88 changing (none); P3 passing without
  the fix (did not happen). The independent refuter judges.

## Skipped items
None. Nothing was driven; no app launched; no docs or frozen-shell files touched.

## Needs verification
- Nothing on screen. The Velox numbers above come from the headless harness, not a drive of the app.
- A driving agent, if wanted: open one of the six files in Prepare/Auto ID and confirm the run completes (no error panel) and that
  the sum column at 11.0061 keV, where present, is labelled with both pairs.
