# A pile-up column identical to a one-peak column: fix pre-registration (2026-10-08 night; nothing built yet)

A new item (ADR 050). Diagnosis, reproduced: `sum-escape-coincidence-diagnosis-2026-10-08/report.md`. A candidate's Si-escape copies are
their own design column; when the group has one line on the axis that column is one Gaussian, and a pile-up pair at exactly its energy
(V Kα escape 3.2125 keV = Tb Mα + Ir Mα) adds an identical column: the run throws `rankDeficient` at every amplitude (5.115 keV axis).
`sumColumns` checks a sum against listed and claiming α energies only, never against escapes. Gate D (Auto ID's picks are scientific).

**Fix (decided, overrule on sight).** In `ElementProposer.sumColumns`, a pair is not added as a column when a current or pool group has a
**one-component** column at the same energy (|ΔE| ≤ 1e-9 keV, equality to rounding as in 77c12faa): a one-line group, or a one-line
escape list. The two columns would be identical, so the design cannot tell them apart; the energy stays the candidate's. Multi-component
columns are never compared (their columns differ from one Gaussian). Nothing else changes; the missing sum-peak question for such a pair
(a UI matter) is not in this item.

**Predictions.** (P1) The planted Case D spectrum scores (no `rankDeficient`) at amplitudes 0, 300 and 40 000. (P2) Every entry of the
2026-10-08 live run (`laneS2/out/tv_out`, 94 scored) is byte-identical in candidates and picks: their axes run to ≈ 20 keV, where no
one-component column coincides exactly with a pair sum (diagnosis census and axis scan), so the rule cannot fire. (P3) Lane N's planted
cases A–C and controls E1–E3b give the same outputs as before.
**Refuting observations.** Case D still throwing; any of the 94 entries changing; any of A–C, E1–E3b changing.
**Gate.** Unit + core; the Case D test red with the rule removed; a live T-V re-run read-only, compared field by field with
`laneS2/out/tv_out`; an independent read-only refuter. The Auto ID `unvalidated` badge stays.
