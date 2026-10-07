# 062 — WP4b: both held Auto ID rules refuted on their risk sets; nothing ships

**Date:** 2026-10-07 night · **Status:** accepted (Gate D: registration → build → measurement → independent refuter) · **Amends:** 060 §2–3

## Context
ADR 060 held R1's beside-K half (its sample never held a true L/M element beside a proposed K) and closed R2 on a non-independent hold-out.
WP4b registered both again before any run (03780df0) on three sets: DTSA-II's Qual set (truth), a seeded risk simulator with true L/M + K
pairs (truth by construction) and the owner's Velox selections (agreement).

## Decisions
1. **The beside-K drop with the evidence guard does not ship**: it drops true Hf beside Cu and Pt beside Ga at equal line area, because an
   L family's detection limit is larger than a nearby K line's, so the guard's net/L_D comparison is unequal across families.
2. **R2 does not ship**: its registered refutation (more than one Velox hit lost) was met, in-sample; DTSA-II's independent set favours it.
   A new registration on independent TEM truth would be a new item.
3. `ProposalRules.shipped` unchanged (Z ≥ 89 never); the guard stays as an option for the measurement tool, off everywhere.

## Consequences
Correction to ADR 060 §3: "R2 loses no hit anywhere" was wrong — on the 78 files R2 alone gives 180 hits against the baseline's 184
(`wp4-autoid-results-2026-10-07.md`, the same 4 hits WP4b lost). Nothing new ships; ADR 060's Z ≥ 89 rule stays.
`docs/archive/v5/wp4b-results-2026-10-07.md` holds every number and caveat. Auto ID keeps its `unvalidated` badge and shows net/L_D beside
each pick. A better beside-K test (β-line or line-shape evidence) and R2 on 200 kV truth are the next registrations if the owner wants them.
