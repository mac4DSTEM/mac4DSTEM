# 060 — Auto ID gains a named rule step; R1's actinide half ships, the rest is held or refuted

**Date:** 2026-10-07 · **Status:** accepted (Gate D: registration → build → measurement → independent refuter) · **Amends:** 054 §6, 058 §2

## Context
The owner: "Auto ID doesn't really work, why can't we do it like Velox?" No Velox algorithm exists to copy; his files carry Velox's
selections. Lane L10 measured today's proposer against them (78 files: precision 34,1 %, recall 45,5 %); the registration
`docs/archive/v5/wp4-autoid-velox-preregistration-2026-10-07.md` named three rules with predictions and refuting observations; lane
L12 built them exactly as registered as a post-selection step and measured (`docs/archive/v5/wp4-autoid-results-2026-10-07.md`).

## Decisions
1. **A rule step exists** (`ProposalRules.apply`, Core): the proposer's raw result stays beside the picks; every pick a rule withholds
   or releases is named with its number in the Found row's notes; the pick's reason names the rule. The `unvalidated` badge stays.
2. **R1's actinide half ships**: never Z ≥ 89 (Velox's own flag; 9 picks on the 78 files, no hit lost). **R1's beside-K half does not**
   (the refuter): the sample never held a true L/M element beside a proposed K, and the line table has pairs where the rule would drop a
   real one with no K fallback — Hf Lα 1,0 FWHM from Cu Kα (a Cu grid), Pt Lα 1,2 from Ga Kα (a FIB lamella; file 1727 drops Pt at 12,5 L_D),
   Ta beside Cu, Pb beside As. It is re-registered only with an evidence guard on a set that holds such a case. Measured whole, R1 gave
   465 picks, no hit lost, precision 34,1 → 39,6 %; predicted and measured equal.
3. **R2 (an L/M pick needs ≥ 3 L_D) is closed by its gate, untestable on this hold-out**: the registered hold-out (June 2026) is 9 files
   of one alloy, one operator, one detector (the registration's "28" was wrong), with a 21 % baseline against which the absolute 45 % bar
   was never fair — the registration broke its own threshold rule. R2 loses no hit anywhere and lifts precision on every set measured (fit
   35,7 → 50,8 %, hold-out 21,1 → 38,7 %); it is not shown wrong, and not shown right on an independent set. Trying it again is a new registration on DTSA-II's Qual set and the simulator (`reference-software-sheet-2026-10-07.md`).
4. **R3 (release a held sum-peak candidate at ≥ 10 L_D) is refuted**: on the dose ladder with truth it released Ar at 19,9 L_D from the
   Al+Al pile-up peak, an element absent from truth. The sum-peak hold stays as it is.
5. **H4** (Mg on the Mg-richest 1 % of pixels): 10 of 19 files, 0 on the whole map — below the prediction, above the refutation line, and
   selection-biased (pixels picked by the Mg window are tested on the same counts), so it supports no mechanism. No UI change.
6. **H1's own evidence is vacuous for its risk**: no file in the sample holds a true L/M element beside a proposed K, and the ladder's R1
   picks equal the baseline in every region. "Not refuted; untested on its risk" is the record, and the reason the beside-K half waits.

## Consequences
The room re-selects with R1's actinide half on every Auto ID run. The measurement tool gained `--replay` (re-select recorded candidates with the current
rules; validated equal to the live run on 39 of 39 files) and `--ladder`; the owner's drive unmounted mid-run, so 43 file dates and 7 H4
files are owed once it is back (commands in the results doc).
