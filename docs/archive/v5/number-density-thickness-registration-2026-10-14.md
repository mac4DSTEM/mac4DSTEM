# Precipitate number density N_V with typed thickness — a new registration (2026-10-14)

Suite ROADMAP "What blocks the study" item 4. ADR 046 parked volumetric density; the owner now needs it for the correlative
study. The 2026-09-28 registration (`../v4/volumetric-density-preregistration-2026-09-28.md`) closed refuted (§10: no
estimator may ship) — per ADR 050 this is a **new item**; that file is not amended. Tier 1 (a number a scientist reads is
new, and any doubt means tier 1). Gate D applies (a new scientific number). Registered before any code or run.

**What the old estimator was, and how it failed.** Per object, N_V = (1/A) Σ 1/(t + hᵢ), hᵢ = extent along the beam (θ′
edge-on: trace length; T1 on {111}: d·√(2/3)); then class-level Nie–Muddle variants (b), (c). Run 1 failed every variant;
the refuter (§10) found (c) exact only for one plate size (0.935 at CV 0.4, 0.82–0.87 at CV 0.6, d ≈ 190 nm, t 50), and
object length read ~1 px long (oracle lengths 0.986–1.013, §9–10). (a) was biased by truncation (1.08 at θ′ d 100 t 50,
analytic 1.095). Unestablished then: polydisperse behaviour, sliver visibility, merging at real coverage, any real thickness.

**The candidate.** A per-object (Horvitz–Thompson) estimator, which is the only form in the record that does not assume one
plate size: N_V = (1/A) Σᵢ wᵢ / (t + hᵢ), summed over counted objects; literature form Nie & Muddle, Acta Mater. 56 (2008)
3490, as applied in arXiv:1804.09634 Eq. 2. Corrections, each from the record:
- projection: hᵢ = Lᵢ·s per class as the old §2 table (face-on θ′ areal only unless a plate thickness is typed);
- length: Lᵢ reduced by the measured point-sampling overshoot (θ′ +0.70–0.73 px, T1 d 20 +1.23–1.35 px; refuter §10) — the
  exact correction is **to be set from the first synthetic run's design before the candidate is run**;
- edge: wᵢ = S²/((S−bxᵢ−p)(S−byᵢ−p)), the refuter's form that excludes the border pixel (ADR 045 omits the −p);
- overlap: objects merged at real coverage are not corrected; the synthetic sets report the rejection rate and the bar
  is stated at the generator's ~1 % coverage only;
- truncation (centre outside the foil, d ≳ t) is **not** corrected per object; it is a predicted failure below.

**Thickness and σ.** The user types t (nm), σ_t and a source (EELS, CBED, assumed); SpectroKit's EELS t/λ fills the same
three fields later. Refused: t ≤ 0, σ_t < 0, no t (areal only, row says why). With cᵢ = wᵢ/(t+hᵢ):
σ_t,N = σ_t · (1/A) Σ cᵢ/(t+hᵢ); Poisson σ_P = (1/A) √(Σ cᵢ²); length systematic σ_L = σ_ℓ · (1/A) Σ cᵢ/(t+hᵢ)
(σ_ℓ ≈ 1 px). σ_N = √(σ_t,N² + σ_P² + σ_L²), the terms shown separately; independence is assumed and said.

**Truth sets** (synthetic, generated in `tools/`, as `tools/volumetric-density-test`; the owner's data are never truth).
Circular plates of known N_V in a foil, projected along [001], counted through `PrecipitateSegmentation.classObjects`
with `PrecipitateStatistics`' edge rule. Ranges: class θ′ edge-on and T1 {111}; t ∈ {50, 100, 200} nm; mean d ∈ {20, 100,
190} nm; lognormal size CV ∈ {0, 0.3, 0.6} (the refuter's range; real T1 sits at d ≈ 190, CV 0.6); field 2400 nm, pixel
2.5 nm and 1.25 nm; seeds until SEM ≤ 1.5 % (cap 400). The owner's Al-Mg-Si cube with a typed t is a **non-truth
consistency check** only (areal × 1/(t+h̄) against the object table); no number from it is called validated.

**Predictions** (bar |mean − 1| ≤ 5 % per cell, the owner's 2026-09-28 §4 bar; set before any run):
- P1 CV 0: passes every cell with d/t ≤ 1 (recorded (a): 0.95–1.03 after the length correction, 0.972–1.015 raw d 20/100).
- P2 CV 0, θ′ d 100 t 50 (and d 190 t 50): **fails** high, ≈ 1.08–1.10 (truncation; recorded 1.081 vs 1.095 analytic).
- P3 CV 0.3 and 0.6: bands **to be set from the first synthetic run's design before the candidate is run** — no basis;
  the record measures only (c), not (a), on polydisperse sets. Expected direction: (a) unbiased in size, so no worse than
  its CV 0 row except through truncation.
- P4 the naive N/(A·t) fails every d ≥ 100 cell (recorded 1.31–2.87), so the test can fail.
- P5 propagation: σ_t,N equals a finite difference of N_V in t to 1e-6 relative on a hand-derived 3-object case.

**Refuting observations** (any one): a CV 0 cell with d/t ≤ 1 outside 5 %; a P2 cell inside 5 % (the model is wrong);
the naive estimator passing a d ≥ 100 cell; the σ_N error bar covering truth in < 60 % of 100 seeds' replications at the
1σ level on the cells where the bias is < 2 %; a mutation of w, hᵢ or the σ formula the tests do not catch.

**Ships badged unvalidated** (CLAUDE.md "Unvalidated stays labelled") unless a cell fails the bar nowhere in the range
the owner's data fall in; a fail anywhere in range ships it areal-only, with the failing cells in the help text. Either
way: "unvalidated against real foils — no independent thickness yet", `validation:"none"`, in provenance and CSV with t,
σ_t, source and hᵢ per object. Areal density stays shown beside it.

**UI cost** (to confirm at build; a mock to the owner first): in Precipitates, 2 rows — "Foil thickness [ ] ± [ ] nm"
(same `OptionalNumericField` pattern as the Quantify thickness rows, `SpectroscopyInspectors.swift`) and "Source [ ▾ ]" —
one result line per phase, one Object Table column; no new workspace, the frozen shell untouched. State owner: the
specimen area's thickness lives in the sidecar with the calibration (the precipitate settings of `PhaseMappingProduct`),
not `AppState`; confirm at build.

**Gates.** Tests before code (hᵢ per class, refusals, the σ derivation, each broken first); unit + scientific; a fixture
(a synthetic foil cell, red on the naive form); one independent Gate B refuter reviewing the diagnosis, not the diff;
a card to the owner only if a shipped number moves (the ADR 045 areal density changes if the −p edge term is adopted).

Registered 2026-10-14 before any code or run.

## Results (2026-10-15 night; lane NV, Sonnet; `number-density-thickness-design-2026-10-15.md`, `number-density-thickness-2026-10-15/`)

The design note (committed before any run, `3d7b7e4a`) derived E[N̂]/N_V = ρ(h, t) per size and **predicted P1 refuted** at
d/t = 1 once the edge weight is exact (the edge loss no longer cancels truncation). Lane NV built only the Core estimator
(9 tests written first, 8 red on a stub; six mutations, each red) and the harness (point-sampled, 54 cells), no UI.
- **P1 refuted:** θ′ d 100 t 100 = 1.074, θ′ d 190 t 200 = 1.064, T1 d 190 t 200 = 1.058 (bar 5 %).
- **P2:** the θ′ t 50 cells read 1.148 (d 100) and 1.245 (d 190) — failing, as the note's ρ said (1.144, 1.231), not 1.08–1.10.
- **P3** (the note's bands): 54 of 54 cells within ±0.05 of ρ̄ (mean |difference| 0.006, max 0.044 at T1 d 190, 5–13 plates).
- **P4 held:** the naive N/(A·t) fails every d ≥ 100 cell. **P5 held.** σ_N covered truth on 100 % of the 18 cells with bias < 2 %.
- Deviation: plates carry one pixel of thickness (a zero-thickness edge-on plate is measure-zero under point sampling); the
  1.25 nm pixel run and `T6_RASTER=cells` were not done.

**Outcome.** The item closes (ADR 050); nothing ships; areal density stays. The model is confirmed, so a truncation-corrected
estimator is a new item: `number-density-thickness-v2-registration-2026-10-15.md` (registered before any code or run).
