# A pile-up column identical to a one-component ESCAPE column in the same design: fix pre-registration (2026-10-12; nothing built)

A new item (ADR 050) after owner card A1 (2026-10-12, option a, "Escape case only"). Held patch, lane report and refuter:
`sum-escape-design-scoped-results-2026-10-08/` (028f79f). Diagnosis: V Kα escape 3.2125 keV = Tb Mα + Ir Mα on a 5.115 keV axis throws
`rankDeficient`. Gate D.

**Fix (the owner's pick).** The held patch minus its LINE branch. `ElementProposer.sumColumns` takes the non-sum groups of the design it
serves (settle: current groups + active pool groups, in both calls, `sums` and the stability check, each with its own active set;
forward step: those + the tested candidate) and does not add a pair whose energy equals (|ΔE| ≤ 1e-9 keV) a **one-component escape**
column (`escapes.count == 1`) of a group in THAT design. One-line LINE groups are NOT compared. A pool group not in the design is never
compared. Files: `Core/Spectroscopy/Proposer/ElementProposer.swift`, `mac4DSTEMTests/SumEscapeIdenticalTests.swift` (new).

**Measured on HEAD first (P3's premise).** La Kα 33.4419 keV = Cd Kα + Tl Lα needs the Expert fit range (the default stops at 20 keV, where
La Kα is out of range) on an axis topping out in 33.5–37.8 keV (test: 0.02 keV/channel × 1800, top 35.98). The run does NOT throw
`rankDeficient` (the refuter's prediction was from reading): pile-up planted 0 → completes, the Cd+Tl column stays (net 0.0) beside La
(net 54, below L_D); planted 300 / 2 000 → La claims the energy (net 285 / 1 980), is a sum-peak question, not in `proposed`, the pair
is dropped by the existing claiming rule. Escape peaks on or off: same.

**Predictions.** (P1) Case D (V Kα escape = Tb Mα + Ir Mα) scores at amplitudes 0, 300, 40 000. (P2) With V in the pool but inactive and a
real Tb + Ir pile-up planted (≈ 2 000 counts at 3.2125 keV), the final fit keeps one Tb+Ir column with a positive net. (P3) On the La /
Cd / Tl axis above, the three planted levels give exactly the HEAD outcomes: no La in `proposed` at any level, and at 0 the Cd+Tl
column at La's energy is kept (never folded into La); it either completes so or throws `rankDeficient`, never anything else. (P4) Lane N's
planted cases A–C and controls E1–E3b are byte-identical. (P5) The 94-entry live run is identical: the data (`/Volumes`) and the
laneS2 harness are not on this Mac, so it is NOT re-run; the argument is derived: the 028f79f patch (escape + line branches) matched
94 of 94, and the escape-only rule excludes a subset of what that patch excluded, so any difference would have to appear there.
**Refuting observations.** Case D throwing; P2 without its Tb+Ir column; P3 with La proposed, or at 0 the Cd+Tl column gone; A–C/E changing.
**Gate.** Unit + core in an isolated copy; breaks: remove the escape exclusion → Case D red; scope pool-wide → P2 red; re-add the line
branch → P3 red. Independent refuter (supervisor). The Auto ID `unvalidated` badge stays. Live re-run: owed, stated, not faked.
