# 066 — v5.0 ships without a microscope validation; B* moves after v5.0; straight to SpectroKit after the 4D Quantify rows

**Date:** 2026-10-13 · **Status:** accepted (owner) · **Amends:** 061 §1 (B* in v5.0), 064 §3.4 (validation before the release), 065 §1 (H, I, K, excess)

## Context
The owner wants SpectroKit sooner. He stated that v5.0 will have no microscope day and no pure-Al thin-foil sample, and, asked
whether B*'s groundwork (per-phase score, separability matrix) stays in v5.0, chose to move it after v5.0 (the recommendation).

## Decisions
1. **No microscope validation in v5.0.** The joint GMS run and the pure-Al foil (WP3 Q1–Q3) are not a v5.0 release gate. EDX
   quantification therefore ships as it is: every product that self-reports `validation:"none"` stays badged unvalidated, and no
   release note or doc calls EDX quantification validated (CLAUDE.md, "Unvalidated stays labelled"). Validation on real data is
   re-registered after v5.0, against whichever build then exists (the SpectroKit tag).
2. **B* after v5.0.** The per-phase score retention, the separability matrix and the B* table (ADR 061 §1) are built later, on the
   SpectroKit tag. D (joint clustering) goes with it.
3. **H, I, K and "excess over the matrix" are not built for v5.0**: their inputs do not exist (ADR 065 §1 said they drop out of
   v5.0 if they cannot be had; without a microscope day the probe current and dose for K cannot).
4. **Order:** the 4D Quantify rows in Results (card P4 b) → the feature-complete freeze → the SpectroKit slot (ADR 064 §3.2–3.3 and
   its 2026-10-13 amendment) → the release on the SpectroKit build.

## Consequences
v5.0 = the EDX suite as built and driven (readers, fit, k/ζ, absorption, Auto ID, Export, the room, E1 pooling, the 4D Quantify
rows), all quantification badged unvalidated. ROADMAP's v5.0 and SpectroKit lines and the status handoff are updated in the same commit.
