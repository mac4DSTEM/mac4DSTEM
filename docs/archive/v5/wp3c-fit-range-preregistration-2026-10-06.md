# v5.0 WP3c — the default fit range, not the continuum — pre-registration (2026-10-06)

Written before any code, after WP3b's F2/F3 were refuted (`wp3b-fit-robustness-preregistration-2026-10-06.md`, addendum). Drafted by Fable from harness runs on the pristine fit code and the seeded realistic-L generator (lane F23's `tools/edx-pins/realistic_l_sim.py`, which lands with the implementing lane); the run logs are in the session scratchpad. Gate D: the implementing lane is a different model, and an independent review follows.

## Problem

With a complete list the old continuum has no dip (ratio 1.00–1.01) and is unbiased on Ti at every upper limit from 11 to
60 keV (E1: z of the 5-seed mean −0.18 … +0.54); only the axis end, 80 keV, biases it (z −2.28, −8 %). The defect left is
"fit to the axis end" on long axes, not the form. A model change costs more than it returns: specimen-edge splits localise the
continuum (undercutting F1), and every fixture ends at 20 keV, so changed orders move P6's bands (F2-A: eight tests red).
The physics option does not rescue the long range: E4, Kramers × ε(SDD) × Bernstein, is z +0.53 at 20 keV and z −2.76 at 80.
P3's 47 % real spread is confounded: as fitTo sweeps 10–80 keV the 12-element list's K lines (Zr 15.7, In/Sn 24–25, Yb 52,
Pt 66) enter and leave the model, with χ²ᵣ 15–91 throughout; P3 never measured the continuum alone.

## Options

| | Option | Effort | Risk |
|---|---|---|---|
| A | Change nothing; add a named range-sensitivity statement (one extra fit at the axis end). | S | The default stays biased on 80 keV axes (−8 % synthetic; owner's Ti 2388 vs 2924 at 20 keV, window 3058 ± 153). |
| B | F3-A1: upper-segment order per e-fold (4.4), splits unchanged. P2 met (z +0.46, `H2-A1-p2.log`). | M | 28 coefficients; on a 20 keV axis the order goes 5 → 11, so every P6 band moves (unmeasured for A1 alone); real spread 24.7 %. |
| C | **No model change.** Default upper limit = min(axis end, beam, 20 keV): the width the orders (9,5) were measured on (`Continuum.swift` header; every fixture), inside E1's unbiased band. Named in the footer; typed limit under Expert (`QuantificationMethod.fitToKeV`, nil = default, old records keep their hash). The at% row takes the Kα group only when supported, else the highest supported group, named. A sensitivity statement when the axis runs past the default. | S–M | 20 keV is a property of the fixtures it was measured on (stated, not asserted); the GMS demo axis ends at 20.03 keV, so its fit loses 6 channels (predicted). The real χ²ᵣ ≈ 47 is not claimed fixed. |

**Recommendation: C.** The smallest change that removes the measured bias; the user keeps the fit (default named on every
result, alternative under Expert, eXSpy's convention); F1's premise stands; the physics agrees: above 20 keV a 450 µm SDD
goes transparent, and the nuisance polynomial was carrying that decline with the six coefficients that shape 2–10 keV. The
sensitivity statement is a statement, not a σ term (the absorption AM/GM precedent).

## Predictions for C (refuted if any fails)

| | Prediction | Refuting observation | Fixture |
|---|---|---|---|
| P1 | 7 elements, default settings (fitTo resolves to 20 keV): 5-seed mean Ti within 1 σ of 3000 (E1 today: 3049, z +0.45); no other planted Kα's mean z moves by more than 0.5 between 20 and 60 keV (E1: largest 0.30). Cu's −0.8…−1.0 is range-independent (Ni Kβ overlap), not a bar. | Mean z > 1, or a Kα move > 0.5 | realistic-L, seeds 0–4 |
| P2 | A record without `fitToKeV` replays today's numbers exactly (Ti 2616/2911/2675/2794/2789, `H0-old-p2.log`); the footer names "fit range 0.2–20 keV (default; axis to 80 keV)". | A digit differs; footer silent | realistic-L |
| P3 | The statement appears only when axis end > default: on realistic-L Ti −7.5 … −12.0 % (−2.2 … −3.3 σ) per seed, every other element within ±2 σ (E3); on 20 keV axes no second fit runs. | Absent at 80, present at 20, or outside E3's numbers | realistic-L; weak-line sim |
| P4 | F1 at the new default: 4 listed elements, Ti at the bound; refit with Ge, Cu, Ga moves it by +27.8 … +29.0 σ (E2); at% withheld as before. | Δ/σ < 1 on any seed | realistic-L |
| P5 | Fixtures with a 19.997 keV axis (weak-line bands, A4, selection score 402): byte-identical, not "within band". GMS control (B0 protocol, axis 20.03 keV): every net moves < 0.1 %, χ²ᵣ 4.913 by < 0.01, from the 6 trimmed channels; old → new reported. | A synthetic digit changes; GMS beyond the bound | suite + demo dm4 |
| P6 | Plant Sn (Lα 3.44, Kα 25.3 keV; generator extension): at the default the Sn row uses Sn_La, named, within 1 σ of the plant; at Expert fitTo 80 it uses Sn_Ka. Today the row fails "no support". | Row fails, or Lα off by > 1 σ | realistic-L + Sn |

Mutations that must go red: fitTo forced to the axis end (P1, P3), the key written when nil (P2), Kα-only choice (P6).

## Stays open

- A model-uncertainty σ (list × range × estimator): its own registration; the statement is not it.
- χ²ᵣ 15–91 on the real spectrum with a complete list (Kramers × ε × absorption vs nuisance polynomial), and the Al-edge
  split on Al-free specimens (D4): harmless with a complete list; a new item if F1's drive shows otherwise.
- The order-5 segment past 60 keV: an Expert range there is the user's; the footer says where the orders were measured.
- P3's real-region sweep is retired as a continuum measurement (list-confounded). Velox file: diagnostics only.
