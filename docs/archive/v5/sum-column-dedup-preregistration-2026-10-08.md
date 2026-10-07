# Duplicate sum-peak columns make Auto ID fail: fix pre-registration (2026-10-08; nothing built yet)

**Diagnosis** (Gate D, reproduced): `archive/v5/proposer-rankdeficient-diagnosis-2026-10-08.md`. Six of the owner's Velox entries (0944 ×2,
1121 ×2, 1140, one copy of 1253) fail Auto ID with `ProposerError.rankDeficient`: `ElementProposer.sumColumns` adds one pile-up column per
parent pair and checks it against listed and claiming lines but never against the sum columns it already added, so two pairs whose energies
coincide in the line table (Dy+Ti and Cs+Ho at 11.0061 keV; In+Si and Ag+Zr at 5.0267 keV) give two identical design columns (cos 1 − 3e-16);
the QR's R-diagonal ratio falls to ~1e-16 and the whole Auto ID run fails. In every pass of five files, "two sum columns at one energy" and
"the pass fails" coincide (1598/1598, 242/242, 700/700, 1596/1596; 0/711 on a scored copy).

**Fix (decided, overrule on sight).** A sum column whose energy lies within `sumPeakToleranceKeV` of a sum column already added in the same
pass is not added again; the kept column's label names every pair it stands for ("sum:Dy+Ti / Cs+Ho"), because the design cannot tell
coinciding pairs apart. Nothing else in the proposer changes. Rejected: dropping one pair silently (hides a candidate explanation);
degrading rankDeficient into a partial result (a separate question).

**Predictions.** (P1) All six entries score with no error. (P2) On every other entry of the live T-V run (the 82 scored entries), the
proposer's candidates and picks are byte-identical to the run of 2026-10-07 (`laneW/out/tv_out`), because no other pass holds a duplicate
energy. (P3) A synthetic spectrum with Dy, Ti, Cs and Ho planted throws `rankDeficient` without the fix and scores with it.
**Refuting observations.** Any of the six still failing; any other entry's picks changing; the synthetic case passing without the fix.
**Gate.** Unit + core; the synthetic test broken once (fix removed → rankDeficient); live T-V re-run (read-only on the owner's drive);
an independent refuter compares old and new runs entry by entry. The Auto ID `unvalidated` badge stays.
