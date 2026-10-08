# Exact duplicate sum-peak columns: fix pre-registration (2026-10-08 night; nothing built yet)

A new item (ADR 050): the tolerance-wide dedup was refuted (`sum-column-dedup-results-2026-10-08.md`). The diagnosis
(`proposer-rankdeficient-diagnosis-2026-10-08.md`) showed the six failing Velox entries (0944 ×2, 1121 ×2, 1140, one copy of 1253) hold two
sum columns at the **same** table energy (Dy+Ti = Cs+Ho = 11.0061 keV; In+Si = Ag+Zr = 5.0267 keV; cos 1 to 16 digits), and every pass
holding such a pair throws `rankDeficient`. Gate D (which elements Auto ID picks is a scientific number).

**Fix (decided, overrule on sight).** In `ElementProposer.sumColumns`, a pair whose sum energy equals that of a sum column already added
in the same pass, to within 1e-9 keV, joins that column (its id and label name both pairs; its elements are the union). 1e-9 keV is
equality to rounding, not a cut: the line table carries four decimals, so only sums equal in the table merge. Pairs further apart than
that stay separate columns exactly as today. Nothing else changes.

**Predictions.** (P1) All six entries score, no error. (P2) Every entry that scored on 2026-10-07 (88, `laneW/out/tv_out`) has
byte-identical candidates and picks: a run that scores never held an exact duplicate in any pass (each such pass throws), so the rule
cannot fire in it. (P3) The synthetic Dy/Ti/Cs/Ho spectrum throws `rankDeficient` without the fix and scores with it.
**Refuting observations.** Any of the six still failing; any of the 88 changing its candidates or picks; P3 passing without the fix.
The six entries' picks against Velox's selections are reported, not gated (no bar; one rerun).
**Gate.** Unit + core; the synthetic test broken once (rule removed → `rankDeficient`); a live T-V re-run read-only on the owner's drive,
compared entry by entry with the 2026-10-07 run; an independent read-only refuter on the logs. The Auto ID `unvalidated` badge stays.

## Result (2026-10-08 night): P1, P2, P3 held; landed (77c12faa)
Lane S2 (Haiku 5.5): the six entries score (94 scored, no failed line); 88 of 88 entries that scored on 2026-10-07 are identical in every
recorded field; the synthetic case throws without the rule and scores with it; each of the three tests red on its own mutation. An
independent refuter (Haiku 5.5, read-only) re-ran the comparison and a full-JSON check: **upheld, with notes** — an exact sum equal to a
non-sum column (another element's line or a Si escape; 13 such table coincidences) is not handled and still fails the run (a new item);
five of the six now end with `settled` false. Picks on the six: 20 hits of 48 against 37 Velox elements (0944: 1 of 6); `unvalidated`
stays. Evidence: `sum-column-exact-dedup-results-2026-10-08/` (lane report, refuter, census of the unhandled case).
