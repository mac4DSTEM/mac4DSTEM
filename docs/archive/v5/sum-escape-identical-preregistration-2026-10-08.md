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

## Result (2026-10-08, early morning): numbers held, rule refuted on scope; not landed, item closed
Lane S3 (Haiku 5.5) built the rule as registered: Case D scores at every amplitude, the 94 live entries are identical in every field,
lane N's other planted cases are byte-identical. The independent refuter (Haiku 5.5, read-only) upheld the numbers and **refuted the
rule**: it compares against every current and pool group, but a pass's design holds only the active groups (settle) or the tested
candidate (forward step), so with the candidate inactive a real pile-up at that energy is dropped with no identical column to justify it
(seen in the probe: V absent, the Tb+Ir column at 3.2125 keV is gone). The registration's own text asked for that scope; its predictions
could not see it (the JSON stores sum-peak questions, not sum nets). Nothing landed; the unlanded patch, lane report and refuter are in
`sum-escape-identical-results-2026-10-08/`. A next registration restricts the check to the pass's design and adds a test with the
candidate inactive and a real pile-up planted (predicted to keep its sum column). The axes of the owner's files run 19.99–79.97 keV.
