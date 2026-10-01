# Lane SB (row 1 + sub-bin azimuth deposition) — independent refuter (Gate B), 2026-10-01

Opus refuter, scratch harnesses only (a copy of the ACOM sources with a deposit switch nearest | linear | gaussA | py4d and a
mirror-pass switch; the convention and mirror harnesses reseeded over 40 random angle sets; seed 0 = the gate's own set,
reproduced exactly: nearest 116 / 122, linear 121 / 125, gaussA 121 / 122, no mirror pass 131; mirror test 9/107, 3/93).
The lane's pre-registered P3 and P4 MISSED, so this registration is closed (CLAUDE.md); nothing from it lands.

- **The F-A "shared quantisation root" is REFUTED.** Without the mirror pass the Au 40-set mean is 132.1; with it ≈ 125 under
  every deposit. The ≈ 7/144 loss is the mirror pass's (the Friedel / half-turn class), not quantisation. The gate's 116 is an
  unlucky angle set (below nearest's 40-set minimum of 118). Grain B: P3 is a null result — mechanism open.
- **The deposit choice was noise.** Au paired over 40 sets: linear − nearest +0.6 ± 0.33 SE; linear − gaussA +0.8 ± 0.14.
  Al mirror, 41 seeds: linear − gaussA +0.07 ± 0.08; "3 vs 4 of 93" is noise (seed 0 is lucky: mean 6.7, sd 2.5). The lane's
  "gaussA" was not py4DSTEM's kernel (constant 1.5-bin σ, template blur kept); a py4DSTEM-shaped experiment kernel on this
  port's uniform radial grid and per-ring mean scores 102/144 Au — experiment parity needs the shell grid and no ring mean too.
- **P4's on-grid exact win was a nearest-bin coincidence**, not a regression: t1 won only on multiples of 2.8125°; the angle-
  averaged error falls 2.67° → 2.27° with linear. Errors of 1.8–3.6° are bank spacing (≈ 2° at 200 templates).
- **FitOverlays mirrored formula HOLDS**: π − (t + θ) puts every spot of 12 mirrored synthetic wins within 0.84 px (HEAD 33–43 px off).
- **The new test never ran the production path** (radialKernel 0.08 → reach > 0; all four tests passed 0); the DEVIATION note
  claimed a py4DSTEM comparison that was not made.

Recommendation: land row 1 + FitOverlays with the Au bound re-pinned from a measured distribution (row 1 under nearest:
40-set min 118, mean 125; the gate's set 116), the reason being the mirror pass's half-turn cost. New items: (i) linear deposit
as a parity step, predicted neutral ±1 on paired seeded sets, with a reach > 0 test; (ii) the mirror pass's half-turn cost
(≈ 7/144 Au); (iii) grain B 6.50° (t84), mechanism unknown; (iv) a full experiment-side py4DSTEM port against an independent
truth set. Quote gate counts in predictions as distributions over angle sets.
Patches: `slot2-fa-row1-mirror-pass-v2-2026-10-01.patch` (row 1 + FitOverlays) and `slot2-sb-subbin-deposit-2026-10-01.patch`.
