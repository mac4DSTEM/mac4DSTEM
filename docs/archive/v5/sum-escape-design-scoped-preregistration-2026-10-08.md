# A pile-up column identical to a one-peak column in the same design: fix pre-registration (2026-10-08 early morning; nothing built)

A new item (ADR 050): the pool-wide rule was refuted on scope (`sum-escape-identical-preregistration-2026-10-08.md` § Result). Diagnosis:
`sum-escape-coincidence-diagnosis-2026-10-08/report.md` (V Kα escape 3.2125 keV = Tb Mα + Ir Mα on a 5.115 keV axis throws
`rankDeficient`). Gate D.

**Fix (decided, overrule on sight).** `ElementProposer.sumColumns` takes the non-sum groups of the design it serves — settle: the current
groups and the active pool groups (both calls, `sums` and the stability check, each with its own active set); forward step: those plus
the tested candidate — and does not add a pair whose energy equals (|ΔE| ≤ 1e-9 keV) a **one-component** column of a group in THAT
design (a one-line group, or a one-line escape list). A pool group not in the design is never compared. Nothing else changes.

**Predictions.** (P1) Case D scores at amplitudes 0, 300 and 40 000. (P2) With V in the pool but inactive (amplitude 0) and a real Tb + Ir
pile-up planted (≈ 2 000 counts at 3.2125 keV), the final fit keeps a Tb+Ir sum column with a positive net (the refuter's test; it fails
on the refuted rule). (P3) The 94 entries of the 2026-10-08 live run (`laneS2/out/tv_out`) are byte-identical in every recorded field:
their axes top out at 19.99–79.97 keV, where no one-component column coincides exactly with a pair sum. (P4) Lane N's planted cases A–C
and controls E1–E3b are byte-identical to before.
**Refuting observations.** Case D throwing; the P2 test without its Tb+Ir sum column; any of the 94 entries or A–C/E changing.
**Gate.** Unit + core; Case D red with the rule removed; the P2 test red on the refuted pool-wide rule; live T-V re-run read-only; an
independent read-only refuter. The Auto ID `unvalidated` badge stays.

## Result (2026-10-08, early morning): P1–P4 held; refuter upheld with a material note; HELD for the owner (card A1)
Lane S4 (Haiku 5.5, 028f79f in a scratch copy): Case D scores at every amplitude; the planted real Tb+Ir pile-up beside an inactive V
keeps its column (net 1 682.8; red on the pool-wide scope); 94 of 94 live entries identical in every field; lane N's other planted
cases byte-identical; unit 2372 / 0 / 3 = 2375 = `func test` count, core 0. The independent refuter (Haiku 5.5) upheld the gate and
found P3's premise false: La Kα 33.4419 keV = Cd Kα + Tl Lα exactly, and La's K group is one Gaussian when the axis tops out between
≈ 33.5 and 37.8 keV (the owner's tops avoid that window, so P3's outcome stands). There, the rule's line branch drops a real Cd+Tl
pile-up into La's column (a false-La risk) where the run used to fail; the escape branch cannot raise an element's own net. The line
branch has no test. Not landed: the choice is the owner's (card A1, `owner-decisions-2026-10-08-autoid-escape.json`); the held patch,
lane report and refuter are in `sum-escape-design-scoped-results-2026-10-08/`.
