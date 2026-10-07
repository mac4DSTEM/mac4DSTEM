# WP4 — Auto ID brought to Velox's answers: pre-registration (2026-10-07, after lane L10's measurement; nothing built yet)

**Owner's words:** "Auto ID doesn't really work, why can't we do it like Velox?" **What exists:** no Velox code; Velox's manual says "matches peaks to
spectral lines"; the owner's 112 SI files carry Velox's own selections (95 files, 41 distinct lists; `VeloxEMDReader.storedElementSelection()`), which
are his hand picks, not a detector's output. **Measured** (`autoid-velox-check-2026-10-07.md`, 78 distinct scored files, in sample): today's proposer
agrees with his lists at precision 34,1 % / recall 45,5 %; no file matches exactly; L and M picks are 15 % / 11 % precise against K's 48 %; the
largest single loss of recall is the sum-peak hold (42 of his elements held at a median 17 L_D); Mg is missed in 37 of 38 Al-Mg-Si files because the
pooled whole-map spectrum holds at most a trace (raw Mg/Al window ratio median 0,002) — not a proposer fault, a pooling one.

## Hypotheses (each with its refuting observation)
- **H1 (R1 hygiene):** never Z ≥ 89 (Velox's own `includeInAutoPeakId` flag) and drop an L/M pick within 1,5 FWHM of another proposed candidate's Kα.
  Predicted: precision 34,1 → 39,6 %, recall unchanged (45,5 %), on the 78 files. Refuted if any file loses a hit.
- **H2 (R2 corroboration):** an L or M pick needs net / L_D ≥ 3; K keeps the L_D bar. Predicted with H1: 49,6 % / 44,6 %. Refuted if recall drops
  below 43 % or precision stays under 45 % on the hold-out (below).
- **H3 (R3 release):** a sum-peak-held candidate at net / L_D ≥ 10 is released. Predicted with H1 + H2: **51,5 % / 51,2 %**. Refuted on the demo-edx
  dose ladder (T4, truth known, pile-up present) if releasing at ≥ 10 L_D adds any element absent from truth.
- **H4 (Mg):** Auto ID on a REGION (a needle) finds Mg where the whole map does not; predicted: Mg found in ≥ 20 of 26 Al-Mg-Si files when run on the
  Mg-richest 1 % of pixels (a diagnostic, not a UI change). Refuted below 10 of 26.

## Design that keeps the threshold rule
The cuts (3, 10 L_D, 1,5 FWHM) were read off this set. Before any lands: **split the 78 files by acquisition date** (April/May = fit set, June =
hold-out; ≈ 50 / 28), set the cuts on the fit set, report precision/recall on the hold-out **and** on the demo-edx ladder with truth. A cut that does
not hold on both ships as a shown quantity (net / L_D beside each pick is already on screen, ADR 058) and no rule.

## Not in this registration
C below 0,45 keV (never tested); the four `rankDeficient` files (own Gate D); a β-line ratio check (needs the β amplitude freed in the joint fit — a
proposer change; measured useless with window sums); Velox's unknown own algorithm.

## Gate
Gate D (a scientific number moves: which elements Auto ID picks). Independent refuter after the hold-out run; the fixture is the owner's file list
with Velox's selections (`autoid-velox-check` output committed as the evidence folder). The `unvalidated` badge stays until the hold-out passes.
