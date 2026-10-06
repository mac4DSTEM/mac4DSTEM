# v5.0 WP3d — the Al-alloy fit on real spectra: Si-region continuum, the Al Kα excess, implausible candidates — pre-registration (2026-10-06)

Written before any fix code, by a read-only designer session. Gate D applies to all three items: each moves a scientific
number. Sources: the previous session's `realAlMgSi/` logs (`resid-1339/1909/1840.log`, `crude-si.log`, `quant-*.log`,
`out/<file>/resid_<pool>.txt`), and the code as of c57f67ab. Every number below marked **verified** was read from those
files or computed from the `resid_*.txt` columns in this session; everything marked *hypothesis* is not yet tested.
Nothing from the owner's private files is quoted except pooled numbers.

## 0. What the existing evidence already says (verified in this session, not in the open item)

| # | Observation | Where |
|---|---|---|
| V1 | The excess just above Al Kα (1.565–1.64 keV, data − model) is **0.53–0.59 % of the Al Kα sum in all nine pools of all three files** (1339: 0.53/0.55/0.54; 1909: 0.58/0.55/0.59; 1840: 0.58/0.55/0.59 % for whole/matrix/network). A constant fraction of Al Kα across pools whose Mg/Si content differs 20× is a property of the Al K line as recorded, not of an independent element. | `resid_*.txt`, summed this session |
| V2 | The excess is line-like, not a step: +23, +110, +131, +92, +27, −15 σ at 1.551…1.650 keV (1909 whole); centroid ≈ Al Kα + 100 ± 10 eV; Al Kβ (table 1.5596, true Kβ1,3 1.5574) is Kα + 71–73 eV; Lu Mα is Kα + 95 eV. | `resid-1909.log` |
| V3 | The Al Kα core residual is asymmetric (1.412/1.432: −14/−17 σ; 1.551/1.571: +23/+110 σ). A width error alone gives a symmetric pattern, so "resolution mis-set" cannot be the whole story. | `resid-1909.log` |
| V4 | The "missing Si K edge" is mostly **not edge-shaped**. In the only Si-free, Al-wing-free pool (1339 matrix, Si net −20 ± 98) the data are 0.69 × the fitted continuum at 1.69–1.815 keV (below the edge) and 0.58 × above it; at 2.17–2.40 keV (line-free) 0.55–0.57 (1339), 0.82–0.87 (1909), 0.82–0.90 (1840). The fitted continuum is too high over the whole 1.65–2.4 keV range, by a factor that differs between files; a possible real step at 1.839 keV of ~15 ± 4 % rides on top in that one pool (data hi/lo 0.789 against a model hi/lo ≈ 0.96; one pool, ~800 counts/channel). | `resid_matrix.txt` 1339, `crude-si.log` |
| V5 | The fit is **unweighted least squares** (named default; `ElementProposer` header, `EDSFit`). With a 24 M-count Al Kα, a 140 k-count shape misfit at 1.57–1.63 keV weighs 4.5 × 10⁹ in the RSS; the whole 1.85–2.4 keV continuum deficit (≈ 7 k/channel × 30 channels) weighs 1.5 × 10⁹. The continuum's upper segment starts at the split (1.5596 keV) and is order 5 over 1.56–20 keV, so its first 0.5 keV is effectively linear and is set where the RSS is largest. | `Continuum.swift`, `EDSModel.swift`, `resid-1909.log` |
| V6 | `Continuum.swift` has only the Al edge (`edges: [alKEdge]`), no efficiency by default (`efficiency: nil`); the k path's SDD model has "Si dead layer 0.0 µm". The line model is one fixed-width Gaussian per line, no tail, no shelf; a `ReferenceShapes` tie exists (`EDSFit.referenceShapes`, used by the synthetic tail test). | code |
| V7 | Lu is proposed on Mα (net 165 k, 1909 matrix default) while Lu Lα is found at 3.2 k (extended run): Mα/Lα ≈ 50. Hf is proposed on Lα (7.899 keV) where the extended-model Cu Kα residual is +16…+19 σ on the low side and −13…−19 σ on the high side: the data's Cu Kα sits ~10–15 eV below the model's — the refined linear axis does not hold O and Cu at once (report §3.4). | `quant-1909.log`, `resid_whole.txt` 1909 |
| V8 | Cu Kα (1909 whole, extended) shows no localised bump at +100 eV; the residual above it is +5…+15 σ and flat through 8.34 keV. Si Kα (network) shows +7/+4/−2 σ at 1.83–1.87 over a −9…−16 σ continuum deficit: inconclusive. | `resid_*.txt` 1909 |

Consequence for the registration: items 1 and 2 are probably one mechanism seen twice (V4 + V5), and the open item's
phrase "the continuum has no Si K edge" over-states the edge. Both are kept as separate items because their fixes differ.

## Item 1 — the continuum over 1.65–2.4 keV is 1.15–1.8× the data; is any of it a Si K edge?

(a) Observation: V4; per channel −13…−55 σ (`resid-*.log`, whole/matrix, 1.83–1.95 keV).

(b) Hypotheses:
- H1a *detector Si K step* (dead layer / partial-charge layer above 1.839 keV). Pool- and file-independent, a step at one energy, a few % to ~15 % for a 0.05–0.2 µm effective dead layer (magnitude from general SDD knowledge, not sourced here).
- H1b *continuum inflated by the Al Kα excess under unweighted LS* (V5): the upper segment's start is pulled up to cover the 1.57–1.63 keV excess and the stiff segment carries it to 2.4 keV. File-dependent (ratio of Al Kα to continuum), no step, the deficit largest nearest the split.
- H1c *specimen Si K edge* (self-absorption in Si-rich regions). Refuted for the matrix pools on composition (0–0.45 at% Si); network-only if real.
- H1d *axis offset*: a +30 eV offset cannot make a 40 % deficit over 120 eV; refuted by V4's width.
- H1e *Kramers shape / beam energy*: (E0 − E)/E changes 7 % over 1.76–1.90 keV; cannot give 30–45 %; refuted by magnitude.

(c) Refuting observations:
- H1a is refuted if the step across 1.839 keV in a Si-free, Al-wing-free spectrum (1339 matrix; the owner's pure-Al spectrum) is < 2 σ, or if its size differs between files by more than its σ.
- H1b is refuted if the 1.85–2.4 keV deficit survives (i) a Poisson-ML refit and (ii) masking 1.55–1.66 keV from the fit, each within ±10 % of the current ratio.

(d) Predictions (written now): P1.1 Poisson-ML or the mask moves data/bg at 1.85–1.975 keV from 0.58–0.70 to ≥ 0.85 in every whole/matrix pool, and the Al Kα-high residual grows (the misfit is no longer hidden in the continuum). P1.2 A Si-edge split added alone (`edges: [1.5596, 1.839]`) lowers χ² but fits a jump of 25–45 % that differs between pools by > 10 % — i.e. it absorbs H1b, not H1a. P1.3 The step measured locally on 1339 matrix and on pure Al is 5–15 %, the same within σ on both, and smaller than today's deficit. If P1.3 gives < 2 σ, H1a is dropped (no step column lands).

(e) Experiment (headless): extend the old harness `realAlMgSi/mac4DSTEM/diag/main.swift` (SwiftPM `realdiag`, reads one `.emd` in place + a pool mask, writes `resid_<pool>.txt`) with switches: method LS/Poisson-ML, mask range, extra edge, reference shape. A ~40-line Python `step.py` fits `a·(E0−E)/E·(1 − s·H(E−1.839))` to 1.69–1.98 keV of `resid_matrix.txt` (1339) and of the pure-Al spectrum, excluding 1.99–2.13 keV (an unlisted line sits there: Pt Mα / Zr Lα / P Kα candidates, V4's table), reporting s ± σ. Writes `gateD/item1/*.log`.

(f) Candidate fix, only after (d): if H1b wins — the fit's weighting (Poisson-ML or 1/μ-weighted LS as the default for pooled spectra ≥ 10⁵ counts) together with item 2's shape column; if H1a also holds — a measured detector step as a fixed multiplicative `DetectorEfficiency` on the continuum (`ContinuumForm.efficiency`, already plumbed), its size from the pure-Al measurement, named in the footer. Fixture: a seeded synthetic Al-matrix spectrum (`weakline_sim.py` generator S, which has the tail) with a planted 10 % Si-edge step and a 0.6 % Kα-high shoulder; test asserts the fitted continuum at 1.9–2.4 keV within 5 % of truth and the step within 2 σ. Mutation: remove the shoulder column (continuum → > 1.3× truth, red) and plant a 0 % step (step column → < 2 σ, red if it claims one).

## Item 2 — the +45…+131 σ excess at Al Kα + 100 eV (read as Lu/Tm/Er Mα)

(a) Observation: V1–V3. Constant 0.55 ± 0.03 % of Al Kα across nine pools; FWHM-sized (3–4 channels of 20 eV against a model FWHM of 82 eV at 1.5 keV from the Fiori-Newbury law at 133 eV).

(b) Hypotheses:
- H2a *Al K line physics not in the table*: Kβ/Kα larger than 0.0132, or the metallic Kβ band / K-edge satellites above 1.56 keV. Prediction: Al-specific; absent on Si Kα and Cu Kα at the same relative position; present on pure Al at the same 0.55 %.
- H2b *detector line shape* (a high-energy shelf or near-coincidence pile-up with sub-threshold events): the same relative offset and fraction on every strong line (Si Kα in the network, Cu Kα); fraction rises with input count rate (1339 → 1840 differ in frames and dwell).
- H2c *fit artefact of the split*: Kβ sits on the split energy (1.5596 keV, table) and the two segments are uncoupled (WP3b D3); the lower segment absorbs the low-energy tail and the upper starts low. Prediction: the excess moves or halves when the split is moved to 1.50 keV or removed; on a synthetic spectrum with a pure-Gaussian Al K pair and no tail the excess is reproduced by the fit alone.
- H2d *resolution/axis mis-set*: V3 refutes width alone; a residual ≤ 20 % of the excess could still be width-related — test by freeing R on Al Kα alone.
- H2e *a genuine element at 1.58 keV*: refuted for Lu by V7 (Mα/Lα ≈ 50) and for all of them by V1 (fraction constant with composition) — kept only as the control for item 3.

(c) Refuting observations: H2a refuted if Si Kα or Cu Kα show the same relative feature at ≥ 0.4 %; H2b refuted if pure Al shows the feature at the same 0.55 % while Cu Kα does not and the fraction is the same in all three files (count rates differ); H2c refuted if the excess is unchanged (±20 %) with the split at 1.50 keV or absent; H2d refuted if a free width on Al Kα removes < 20 % of the excess.

(d) Predictions: P2.1 A free Gaussian column per strong line at (E_line + Δ) with Δ and area free: Al lands at Δ = +95…+110 eV, 0.5–0.6 %; Si (network) and Cu (listed) land at < 0.2 % — H2a/H2c, not H2b. P2.2 Removing the split changes the excess by < 20 % (H2c refuted; the excess is in the data). P2.3 On pure Al the same column reads 0.5–0.6 % at the same Δ. P2.4 With that column, item 1's ratio moves by ≥ 0.1 even under LS (links the items).

(e) Experiment: same harness; add `--shoulder Al_Ka,Si_Ka,Cu_Ka`, `--split 1.50|none`, `--freeR Al_Ka`; `resid.py` extended to print the excess fraction (this session's awk) per pool. Writes `gateD/item2/*.log`.

(f) Candidate fix, only after (d): if H2a — correct the Al K family in the model: Kβ at 1.5574 keV with a *measured* Kβ/Kα (from pure Al, named `DEVIATION` against eXSpy's 0.0132 and 1.5596) plus, if the +100 eV feature is not Kβ, one `ReferenceShape` tied to Al Kα (`.lineAmplitude(group: "Al_Ka", fraction:)`) carrying the measured high-side shape, shipped with its source spectrum's name in the footer and "unvalidated" until a second Al spectrum agrees. If H2b — a detector shape (tail + shelf) per line, measured on pure Al, applied to every line; a bigger change, its own registration. Fixture: seeded synthetic with a planted 0.55 % feature at +100 eV; test asserts no unlisted candidate within 1.5–1.7 keV above L_D after the fix and the Mg Kα bias within the registered band (P6 of WP3b stays). Mutation: set the tie fraction to 0 → the Lu Mα candidate returns above L_D (red).

## Item 3 — a bar for implausible unlisted candidates

(a) Observation: at% withheld on every pool of every file by Lu/Tm/Er Mα, Hf/Ho/Cs/Ba/Sm Lα… (`quant-*.log` lines 47/86/127 and the extended runs); the withholding bar itself works as registered (candidates move Mg by 2–25 σ through the shared continuum).

(b) The options (the threshold rule: no σ bar from one dataset):
- B1 *line-family consistency* (physics): a candidate proposed on family A is implausible when a sibling family B of the same element is excitable (edge < E0), in the fitted range with ε(E) ≥ 0.2, and its net is < L_D while r_min(B/A) × net_A > F × L_D(B). r_min is a measured lower bound of the B/A ratio, not a theory number: the repo has Bote-Salvat K/L/M shell cross-sections but maps only K (`BoteSalvatCrossSection` DEVIATION) and Krause 1979 yields K and L only, so a first-principles L/M ratio is not available. Catches Lu (Mα/Lα 50, V7), Hf (Hf Mα at 1.645 keV reads ~0 while Lα claims 80 k), Tm/Er alike.
- B2 *shape-residual labelling*: a candidate whose alpha line lies within ±2 FWHM of a listed line with net > 10⁵ counts, or within ±1 FWHM of a continuum split, is reported as "unexplained excess beside X Kα: N counts, p % of X" — a quantity, never an element. Catches Lu/Tm/Er (beside Al Kα, on the split) and Hf Lα (beside Cu Kα). No number to measure; the FWHM multiple is a geometry convention stated in the note.
- B3 *consequence change*: an implausible candidate (B1 or B2) is named but never withholds at%; at% is withheld only by candidates that pass both and move a net by > σ. This is the "ship the quantity, let the reader judge" option; the owner decides it.
- B4 *a measured chance rate on real Al-free data* (already owed in the open items): count Lu/Tm/Er proposals on `References/EDX/SI HAADF 1456…emd` and the three public sets; it calibrates the look-elsewhere note, it is not a bar.

(c)/(d) Refuters and predictions: P3.1 On the nine real pools B1+B2 flag every heavy-M/L candidate named in V7's lists and none of Cu, Mn, Fe, Ar, Zr (the plausible ones; Ar's sum-peak question stays). P3.2 On WP3b's `S2c` synthetic and the public FePt set no real element (Ge, Cu, Ga; Fe, Pt) is flagged. P3.3 r_min(L/K) measured on Cu (three LPBF files), Ge/Ti/Ni (`SI HAADF 1456`), Cu (zenodo AlCoCu) spans < one decade; r_min(M/L) is measured on ONE dataset only (FePt: Pt Mα 2.05 / Lα 9.44 keV) and ships flagged "one dataset" until the owner supplies a heavy-element spectrum. If P3.3's L/K spread exceeds a decade, B1 is not a bar and only B2+B3 land.

(e) Experiment: a Python/Swift script over the fit's exported nets (`fit_pins.py` style, under `tools/edx-pins/`): for each dataset fit the full plausible list, tabulate net(B)/net(A) per element with both families in range; writes `gateD/item3/family-ratios.log`. Datasets: the three LPBF files (private, numbers only), `References/EDX/SI HAADF 1456 77000 x 20260420.emd`, `References/EDX/public/exspy-EDS_TEM_FePt_nanoparticles`, `zenodo-13370975-AlCoCu-TEM-EDS`, and `proposer_sim.py` as the control with known truth.

(f) Fix and fixture: `LineConflicts`/`UnlistedLineCheck` gain a `plausibility` field with the reason string; the sheet decides B3. Test: the planted-Lu seed of WP3b P5 and a planted real Pt (M+L consistent) — Lu flagged implausible, Pt not. Mutation: swap r_min to 0 → Lu passes (red); plant Pt with its Lα removed → Pt flagged (asserted red when it should pass only if B1 is wrongly applied to an out-of-range sibling).

## What the owner can supply (decides most of this)

1. **A pure-Al spectrum on the same detector and kV** (named in the open item): gives the Kα shape and the +100 eV fraction (item 2, H2a vs H2b), Kβ/Kα, and the only clean measurement of a detector Si-edge step (pure Al has no Si: any step at 1.839 keV is the detector). With it, items 1 and 2 need one harness run each.
2. The alloy's nominal composition and the FIB preparation (Pt protection layer? Ga?): explains the 2.0–2.1 keV bump in the matrix pools and gives one heavy-element M/L pair (Pt) for item 3's r_min on his own detector.
3. Per-frame count rate / dead time (Velox metadata) for H2b's rate dependence; per-detector spectra if Velox exported them (a 4-SDD sum with unequal gains would widen lines asymmetrically — not listed above because V1's constant fraction argues against it, but one export settles it).
4. Any spectrum of a known composition (a standard) — for Quantify's at%, not for these three items.

## Effort, risk, order

| Item | Effort | Risk | Order |
|---|---|---|---|
| 1+2 harness run (LS vs ML, mask, split, shoulder, step fit) | 0.5 day, one Sonnet lane, no app code | low: existing harness, existing residual files; private data read in place | **first** — decides whether 1 and 2 are one mechanism |
| 3 family ratios on 6 datasets | 0.5 day, one Sonnet lane in parallel | low; FePt is the only M/L dataset | parallel with the above |
| Item 2 fix (Al K family + reference shape) | 1 day + Gate B | medium: moves Mg/Si nets; WP3b P6 bands must hold or be re-reported | after the pure-Al spectrum or after P2.1–P2.3 on the three files |
| Item 1 fix (weighting default and/or step) | 1 day + Gate B | medium-high: the default estimator changes every pooled number; register the LS→ML switch as its own decision | after item 2's fix is measured |
| Item 3 (B1+B2, B3 by sheet) | 1 day | low: labelling and a consequence; the r_min numbers ship flagged | after the ratios log; independent of 1 and 2 |

Not here: the refined axis's O-vs-Cu nonlinearity (report §3.4, V7) — its own registration; a model-uncertainty σ term; the Velox live/real-time reader.
