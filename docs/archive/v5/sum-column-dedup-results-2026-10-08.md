# Duplicate sum-peak columns: the registered fix is refuted, the item closes (2026-10-08)

Registration: `sum-column-dedup-preregistration-2026-10-08.md` (diagnosis: `proposer-rankdeficient-diagnosis-2026-10-08.md`).
Built by lane S (Sonnet 5.5) in a scratch copy of `188e56a0`; nothing landed on `main`. Gate D, so the failed prediction closes the item
(ADR 050); nothing was tuned after the run.

## What was built
`ElementProposer.sumColumns`: a pair whose energy lies within `sumPeakToleranceKeV` (0.06 keV) of a sum column already added in the pass
joins that column (id "sum:Cs+Ho / Dy+Ti", elements the union). Two tests (`SumColumnDedupTests`): the Dy/Ti/Cs/Ho case throws
`rankDeficient` on the old code and scores with the fix (red with the dedup removed); a lone pair is unchanged. Lane gate: unit
2338 / 0 / 3 = 2341 = `func test` count, core 0 (`laneS/unit-1.log`, `core-1.log`).

## Result on the owner's Velox files (live, read-only)
- **P1 held.** The six failing entries score (94 scored against 88, no failed line); all six run to the pass cap (44–59 passes).
- **P3 held.** The synthetic case throws without the fix and scores with it.
- **P2 refuted.** Of the 88 entries that scored on 2026-10-07, 13 are identical and 75 change their candidates; the picks change in 27
  (`sum-column-dedup-results-2026-10-08/picks_diff.txt`). (The registration said 82 scored entries; the 10-07 run scored 88 because
  duplicate paths count separately.)
- **Not drift.** The unmodified harness re-run on five entries (1221, 1436, 1029, 1330, 1020) reproduced the 10-07 results exactly.
- **Mechanism of the change.** A diagnostic build logging every merge: candidates changed if and only if an entry had at least one merge
  (75 of 75 changed entries merged; 0 of 13 identical ones). 81 of 94 entries merged at least once, 2 390 distinct merge events (median
  14 per entry, max 148); the absorbed column's gap has median 0.0275 keV, p90 0.0527; 17 event types are exact (< 0.001 keV).

## The census (why near merges are common)
`sum-column-dedup-results-2026-10-08/sum_collisions.py <repo root>`: with each element's Kα/Lα/Mα as a parent (an approximation of the
proposer's parents), 91 elements give 145 parent energies and 9 656 pair sums below 20 keV; 217 sums coincide exactly between different
element pairs (e.g. Al Kα + Si Kα = Lu Mα + Hf Mα, 3.2262 keV) and 325 680 pairs of sums lie within 0.06 keV (229 among common
Al-alloy/TEM elements). Output: `census-result.txt`.

## What follows
The registered rule merges near coincidences, which are everywhere. The diagnosis showed the failure needs an **exact** duplicate
(cos 1 to 16 digits; every pass holding one throws), so every entry that scores today never held one in any pass. A rule limited to
exact duplicates should leave every scoring entry byte-identical. That is a new item with its own registration
(`sum-column-exact-dedup-preregistration-2026-10-08.md`). Whether near-coincident columns alone can make a design singular was not tested.
