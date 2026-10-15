# 065 — E1 first, pooled by class; Auto ID's pile-up fix for the escape case only; the ellipse radius bias closed with its note

**Date:** 2026-10-12 · **Status:** accepted (owner, by option on the decision sheet) · **Amends:** 061 (E's order), 064 §3.1 (cards E1–E6 answered)

## Context
Three sheets: `../_archive/mac4DSTEM/docs/archive/v5/owner-decisions-2026-10-08-e-pooling.json` (cards E1–E6, A1), `owner-decisions-2026-10-12-ellipse-radius.json`
(card M1). Each card had a recommendation and an independent second opinion. He answered **a** on every card, the recommendation each time.

## Decisions
1. **E1 now** (pooled spectra through the existing Quantify path, with refusals, badges and lineage); H, I, K and "excess over the matrix"
   stay in v5.0 as separate registrations, each registered once its input exists and dropped from v5.0 if it cannot be.
2. **E2 a:** pool by class in E1 (all objects of a phase are the phase pool); single-object pooling is E1b, after a mock he has seen.
3. **E3 a:** the Source picker is sectioned — Drawn · Whole map · Phases · Groups; with no phase map, one disabled line pointing at Crystal Maps.
4. **E4 a:** positions the matcher did not index are a pool, "Not indexed", badged unvalidated.
5. **E5 a:** a 4D map pools EDX pixels only through the identity of the same scan ("same scan, identity; no lag check"); a size mismatch is
   refused with a sentence naming both sizes.
6. **E6 a:** nothing new is drawn in E1; a pool behaves like a drawn region; phase pools show the Phase row and the unvalidated badge.
7. **A1 a:** the sum-vs-one-component fix lands for the escape case only, as a new registration; the line case (La Kα = Cd Kα + Tl Lα on
   33.5–37.8 keV axes) keeps failing with `rankDeficient` — a failed run, never a false La.
8. **M1 a:** the conic fit's radius bias (a floor of 1.75 (s/R)², the note on `fit1D`) is closed with the note; no number this app applies
   depends on the radius. The background effect on the conic fallback stays unmeasured and is not registered.

## Consequences
E1 is built to `docs/registrations/e1-pooling-preregistration-2026-10-08.md`, which already assumed these answers (nothing to fold in).
A1 is registered in `../_archive/mac4DSTEM/docs/archive/v5/sum-escape-only-preregistration-2026-10-12.md`. macTEM is told: calibrate a camera length with the profile fit.
