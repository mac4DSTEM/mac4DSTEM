# 069 — Card M3: the ring fit lands two starts and the floor guard; an annulus guard is registered next

**Date:** 2026-10-14 · **Status:** decided by the owner (card M3, option **b**, as recommended; relayed by the suite
coordinator and confirmed in the session's chat) · **Follows:** 068, the record `../_archive/mac4DSTEM/docs/archive/v5/ring-fit-two-start-gateD-2026-10-14.md`

## Context
The Fit's profile model (`fitAmorphousRing`) accepts wrong ellipses on noisy rings with a good centre guess, and on the
owner's patterns it accepts ring-less fits (Ni65Cu35 [11, 14] px, Au_ref [30, 38] px) and a ring outside its annulus (Au_ref
[29, 39] px). The ADR 068 item measured his cubes, then built and refuted two starts (c), a floor guard (b2) and an 8 % seed
check (s) with their combinations. On 2009 synthetic rows, wrong / right lost / b/a off > 0.01: HEAD 414 / – / 319, cb (two
starts + floor guard) 79 / 11 / 59. The seed check was refuted on real data (it refuses agreeing fits on shifted Au_ref
annuli, with no fallback). Card: `../_archive/mac4DSTEM/docs/archive/v5/owner-decisions-2026-10-14-ring-fit-m3.json`.

## Decisions
1. **cb lands:** `fitAmorphousRing` refines from py4DSTEM's ring-σ start and from the ring's half-maximum width, each through
   every acceptance check plus the floor guard (a ring σ ≤ 0.30 px is refused), and keeps the passing fit with the lower cost;
   the Fit falls back to the conic when neither passes. The floor message is reworded to say what is tested.
2. **Accepted by the owner, in the card's words:** one failed registered clause (the floor guard refuses 19 point-sampled
   synthetic rings 0.25–0.30 px wide, falling back to a conic within 1.1 % and 0.005 in b/a); cb was chosen from the data, no
   prediction named it; a worse niche (gapped rings over a steep 1/r² background at 10–20 counts, 14 → 16 wrong).
3. **The seed check does not land.** A threshold-free **annulus guard** (refuse a ring fitted outside the annulus the user
   drew) is registered as a new Gate D item; a seed check gated on the conic's own residual only if still needed after it.
4. macTEM, which copies `EllipseCalibration.swift`, is told when cb lands (its camera length S3′ waits on it).

## Consequences
- Two profile fits per click (0.11 → 0.55 s per fit on a 192 px test ring; under a second on the owner's patterns).
- The ellipse tool's expectations are unchanged: `grains_12_one_annulus` still fits isotropic, through the second start.
