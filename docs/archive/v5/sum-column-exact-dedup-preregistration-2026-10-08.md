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
