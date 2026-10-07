# WP4b — the two held Auto ID rules on sets that test their risk: pre-registration (2026-10-07 night; nothing run yet)

A new item, not WP4 amended (CLAUDE.md: a failed reproduction gate closes an item). WP4 (ADR 060) shipped R1's actinide half,
held R1's beside-K half (its sample never held a true L/M element beside a proposed K) and closed R2 untested on an independent set.
The owner's word (2026-10-07, after the push): "do WP4b". Gate D: which elements Auto ID picks is a scientific number.

## The two rules, fixed before any run (no cut is tuned in this item)
- **R1b, beside-K with an evidence guard.** An L or M pick within 1,5 FWHM of another PROPOSED candidate's Kα is dropped **only when its
  net / L_D is at or below that K candidate's net / L_D** (the refuter's guard, ADR 060 §2). Otherwise it stays.
- **R2, L/M corroboration, unchanged.** An L or M pick needs net / L_D ≥ 3; K keeps the proposer's L_D bar.
- The baseline is what ships today (`ProposalRules.shipped`: Z ≥ 89 never). Every set is scored for baseline, R1b, R2, R1b + R2.

## The three truth sets (a rule must hold on all three; reference-software sheet 2026-10-07, row 1)
- **T-Q, DTSA-II's `QualSpectra.zip`** (NIST, public domain; 31 EMSA spectra of glass standards with `Qual answers.txt`, graded
  easy → very difficult; 25 kV SEM bulk, 10 eV/ch). Algorithm truth; its domain is not 200 kV thin film, said beside every number.
- **T-S, a seeded risk simulator** (new, `tools/autoid-velox-check/risk_sim.py`, truth by construction, 200 kV, the owner's axis):
  (i) **true pairs** — a true L/M element beside a true K element, at planted L/M : K line-area ratios 0,3, 1 and 3, two doses each:
  Hf Lα + Cu Kα, Ta Lα + Cu Kα, Pt Lα + Ga Kα, Pb Lα + As Kα, Ag Lα + Ar Kα, each on an Al matrix; (ii) **ghosts** — only the K element
  planted (Cu, Ga, As, Ar on Al) at the higher dose, so any L/M pick beside it is false. Plus the existing demo-edx dose ladder (8 regions).
- **T-V, the owner's Velox selections** (agreement, not truth; 78 distinct files; the drive is back, so run live, which also writes the
  43 owed acquisition dates).

## Hypotheses, predictions and the observation that refutes each
- **H5 (R1b is safe where the guard says it is).** On T-S pairs at ratio ≥ 1 R1b drops no true element; at ratio 0,3 it may drop the L/M
  element (the guard's admitted cost, reported per pair). On T-S ghosts it removes every false L/M pick the baseline makes beside the K.
  On T-Q and T-V it loses no hit against baseline. **Refuted** if any true element at ratio ≥ 1 is dropped, if any hit is lost on T-Q or
  T-V, or if it removes no false pick anywhere (then it has no value and stays off).
- **H6 (R2 holds off its fit set).** On T-Q R2 loses no hit in the easy and moderate classes and precision rises against baseline; on
  T-S no true element with planted net / L_D ≥ 3 is lost; on T-V recall falls by at most one hit (WP4's in-sample loss was 4 of 404).
  **Refuted** if T-Q precision does not rise, if an easy/moderate T-Q hit is lost, or if T-V loses more than one hit.
- No predicted number for precision: the baselines on T-Q and T-S are unmeasured; a direction against the measured baseline is the claim
  (the threshold rule: a bar is a property of its dataset, so none is set before the distribution is seen).

## Ship rule
A rule ships (`ProposalRules.shipped` flag on) only when it is not refuted on T-Q, T-S and T-V **and** an independent refuter (read-only,
another model) agrees from the logs. Otherwise it stays off and the net / L_D beside each pick remains the shown quantity. The
`unvalidated` badge stays either way: none of the three sets is 200 kV thin-film truth on real data.

## Not in this item
New cuts; H3/R3 (refuted, ADR 060); H4 (selection-biased); C below 0,45 keV; anything in the proposer itself.
