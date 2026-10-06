# v5.0 WP3b — fit robustness on real spectra — pre-registration (2026-10-06)

Written before any fix code. Source: the room's first drive (`room-drive-2026-10-06.md`, findings 1–2), a Gate D
diagnosis and an independent refutation, both run on the owner's private Velox file (diagnostics only; nothing derived
from it is committed) and on synthetic spectra. Gate D applies: every fix below moves a scientific number.

## The diagnosis, as it survived the refuter

| # | Finding | Status |
|---|---|---|
| D1 | With the listed set O, Si, Ti, Ni the continuum absorbs strong unlisted lines (Ge K, Ge/Ga L, Cu K, Ga K), sits 2–5× above the data at 5–15 keV, and holds Ti at the non-negativity bound (window method: 3058 ± 153). Same with Poisson-ML. Escape peaks, Kramers/ε, axis refinement: not the cause. | confirmed |
| D2 | Even with a complete list, Ti moves with the fit's upper limit (12 elements, LS: 3581 / 3526 / 2924 / 2388 at 10 / 15 / 20 / 80 keV). On synthetic data (truth 3000) the 80 keV fit reads −6 %; at 12–20 keV, or with a (9,15) basis, it is unbiased: the order-5 upper Bernstein segment is too stiff over 1.56–80 keV. | confirmed (refuter) |
| D3 | The model collapses to ≈ 1 % of the data at 1.557 keV (channel 174, the last channel below the split). The two continuum segments are independent bases; the lower one's last coefficients fit to 0, and a Bernstein sum takes the value c_n at the segment end. Reproduced on synthetic data with realistic L-line intensities. Not escape peaks (the drive record's "absent without them" was unsupported). | confirmed, cause established |
| D4 | The split sits at the Al K edge by default — wrong for a specimen without Al. | confirmed |
| D5 | The quoted σ (≈ 108 on Ti) is counting only; list × range × estimator moves Ti by ~±20 %. | confirmed |
| D6 | Proposals alone do not name what is missing: the proposer files the real Cu and Ga lines as sum-peak questions. Listing only the hard proposals gives Ti 245–438; adding Cu and Ga gives 2183. Withholding at% on any proposal would fire on chance elements (1 of 3 synthetic seeds: Lu Mα at 1.08 L_D). | refuted as first proposed |

## The fixes (three lanes)

**F2 — a continuous continuum, edges from the specimen.**
- The segments share their joint coefficient, so the model is continuous at every split.
- At each split one non-negative column allows only a downward step.
- Splits come from the edges of listed elements present in the fit, plus the detector's Si K. There is no fixed Al edge.

**F3 — a continuum flexible enough for 80 keV, and an honest σ.**
- The upper segment's order scales with its width (the refuter's (9,15) is the measured point), or the default fit range is
  capped. Choose by the predictions below, not by preference.
- The results footer says the σ is counting only. A model-uncertainty term is an open item, not built here.

**F1 — name what is missing before at%.** This runs after lane U lands, because both edit `PooledQuantification`.
- The proposer runs on the quantified pool. Its proposals and its sum-peak questions both count as unlisted candidates.
- Two bars:
  - The results always name the candidates.
  - at% is withheld, with the reason, only when refitting with the candidates added as fit-only moves a listed element's
    net by more than its σ.
- The check is cached per (pool, element set, settings) and runs off the main actor. A 4096-channel proposal costs 5–20 s
  (lane P), so the Quantify verb never waits on it: the table says "checking for unlisted lines…" until it resolves.

## Predictions (refuted if any fails)

| | Prediction | Fixture |
|---|---|---|
| P1 | The model at the last channel below every split is ≥ 0.9 × the data on the realistic-L synthetic spectrum (the refuter's `S2c`), on the default settings. | seeded synthetic (new, public) |
| P2 | Seven elements, 80 keV, 5 seeds: Ti within 1 σ of the planted 3000 (today −6 %). | seeded synthetic |
| P3 | On the owner's Velox region with 12 elements, Ti changes by < 10 % over fit ranges 10–80 keV (today 3581 → 2388). | diagnostic only (private) |
| P4 | The 4-element `S2c` run names Ge, Cu and Ga as unlisted, and withholds at% (Ti moves by far more than its σ). | seeded synthetic |
| P5 | With a complete list, a chance proposal (the Lu Mα case) is named but at% is not withheld: refitting with it moves no listed net by more than σ. | seeded synthetic |
| P6 | No synthetic Al-Mg-Si result moves outside its current band: the weak-line bias tests, A4's absorption bounds and the GMS control (χ²ᵣ 1.43). Any that moves is reported with old and new numbers, never re-banded to pass. | existing fixtures |

The synthetic generator must be seeded. The diagnosis's generator used `SystemRandomNumberGenerator`, so it was not
reproducible. Unlisted L lines are planted at the intensities seen in real windows (Ge L ~5.8 × 10⁵ and Ga L ~3.7 × 10⁵
counts per pool), not 5–50× weaker.

## Not here
- A model-uncertainty σ term: its own registration.
- Reading the Velox `SpectrumImage` live and real times, and the GMS tilt and segments: their own reader gates.
- A pure-Al reference for the Al Kα tail: owed by the owner.
