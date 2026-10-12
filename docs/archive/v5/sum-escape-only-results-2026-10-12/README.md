# A1 escape-only: results (2026-10-12)

Planted Cd+Tl pile-up area (counts) at La Kα on a 35.98 keV axis, Expert fit range to the top; one line per level.
`scan-head.txt` = HEAD (d9d2ebe2's proposer), `scan-esc.txt` = the landed escape-only rule, `scan-line.txt` = the held line branch.
HEAD and escape-only are identical (throw `rankDeficient` at 120–200); the line branch completes there with La net 106–185 (the false-La risk card A1 declined).

Gate (isolated copy of 31c14258 + the two lane files): unit 2450 / 0 / 3 = 2453 = `func test` count (2449 + 4), core 0 (`a1-unit.log`, `a1-core.log`).
Mutations (lane logs): escape exclusion removed → Case D and P2 red (`m2-remove`); pool-wide scope → P2 red (`m2-pool`); line branch re-added →
the La test red (`m2-line`; the earlier `mut-line` ran against the first P3 test, which it did not catch).
Refuter (Haiku 5.5, read-only): UPHELD WITH NOTES — the rule is escape-only at all three call sites; an escape column is proportional to
the pair's Gaussian (same column builder and FWHM law), so the excluded pair was an identical column; no element's own net can rise.
Notes taken: the `escapes.count == 1` guard has no mutation that reaches it; the Sr+Ba control catches none of the three mutations; P3 is
characterisation of HEAD, not evidence the outcome is right (identical columns completed at 0 counts — the throw depends on the solver path);
when V is active a real Tb+Ir pile-up is absorbed by V's escape coefficient (a missed sum finding, never a false element).
P4 (lane N's planted cases) and P5 (the 94-entry live run) were not re-run: their harness and data are not on this Mac.
