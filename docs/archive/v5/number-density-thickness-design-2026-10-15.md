# Number density N_V with typed thickness — design note (2026-10-15, before any candidate run)

Sets the two items `number-density-thickness-registration-2026-10-14.md` deferred. From algebra and the record only; the
registration is not amended. The bands below come from a quadrature of the formula in §2 (arithmetic, not a run of the
candidate or the harness).

## 1. Length correction: none in the estimator; the harness rasteriser is the defect (form: κ = 0)

The refuter's overshoot (θ′ +0.70–0.73 px, T1 d 20 +1.23–1.35 px) was measured on a harness that rasterises by **cell
intersection** (`main.swift`: every pixel any sample point falls in). A chord c laid on the grid covers c/p + 1 cells, so
the app's L (range + 1) reads c + p; the harness's sample grid (spacing p/4) loses ≈ p/4 at the two ends together, giving
≈ 0.75 p. That reproduces 0.70–0.73 for θ′; at 45° the cell count grows with (|cos|+|sin|) and the extra width of the
strip adds to it: ≈ √2 · 0.75 ≈ 1.06 plus width terms, vs 1.23–1.35 measured. The overshoot is the rasteriser's.
A scan samples **points**: a chord of length c holds n ≈ c/p centres (E[n] = c/p), range + 1 = n, so E[L] = c for
axis-aligned traces (0 px). For a thin trace at 45° L = (n−1)√2 + 1 ≈ c − 0.41 p (−0.4 px). Both lie inside σ_ℓ = 1 px.
**Design:** no subtraction in the estimator (a subtraction tuned on the cell-intersection harness would bias real data
low by ~0.7 px); the generator rasterises by **point sampling** (pixel i on iff its centre lies in the plate's in-foil
footprint, solved exactly per pixel, no sample grid); σ_ℓ = 1 px stays the systematic term. The cell-intersection
rasteriser is kept behind `T6_RASTER=cells` only to reproduce the refuter's numbers.
Costs honestly stated: a plate whose footprint holds no pixel centre is invisible (slivers; run 1: 0.3–1 % at 2.5 nm).
Truth counts every placed plate; the harness prints the invisible fraction and P1 is read with it.

## 2. P3 bands (CV 0.3, 0.6) — derived, not fitted

Per size d (h = s·d, s = 1 θ′, √(2/3) T1), a counted plate has centre z uniform on a slab t + h. Inside the foil
(probability t/(t+h)) the visible length is d. Outside (probability h/(t+h)) the foil cuts a chord d·√(1−q²), q
uniform on (0,1) (mean π/4, Nie–Muddle). Counted plates per area are N_V f(d)(t+h), so with exact edge weights

 E[N̂]/N_V = E_f[ ρ(h,t) ],  ρ(h,t) = t/(t+h) + h ∫₀¹ dq / (t + h√(1−q²)),

f the volumetric number distribution of sizes. The per-object form is unbiased in size (no d̂ inversion); the only
CV dependence is Jensen on ρ (concave in d), so ρ̄ falls slowly with CV. Checks against the record: θ′ d 100 t 50
ρ = 1.144, × the edge loss 0.955 = 1.092 (registered 1.095); θ′ d 100 t 100: 1.071 × 0.957 = 1.025 (registered 1.025).
Lognormal: σ² = ln(1+CV²), median d̄e^(−σ²/2)… truncated at 4 d̄. E[ρ] (θ′ | T1; t = 50, 100, 200):

| mean d | CV | θ′ | T1 |
|---|---|---|---|
| 20 | 0 / 0.3 / 0.6 | 1.020 1.006 1.002 / 1.021 1.007 1.002 / 1.021 1.007 1.002 | 1.015 1.005 1.001 / 1.015 1.005 1.001 / 1.016 1.005 1.002 |
| 100 | 0 | 1.144 1.071 1.028 | 1.119 1.055 1.021 |
| 100 | 0.3 | 1.140 1.070 1.029 | 1.117 1.055 1.021 |
| 100 | 0.6 | 1.132 1.068 1.029 | 1.111 1.054 1.022 |
| 190 | 0 | 1.231 1.137 1.067 | 1.202 1.114 1.052 |
| 190 | 0.3 | 1.225 1.134 1.066 | 1.197 1.111 1.052 |
| 190 | 0.6 | 1.211 1.127 1.064 | 1.185 1.106 1.050 |

**P3:** each CV 0.3 / 0.6 cell reads within ±0.05 of its table value (the bar's width: 1.5 % SEM ×2 plus ≤ 2 % for
pixelisation, merging and thinning). A cell with table value > 1.05 is predicted to FAIL the 5 % bar; ≤ 1.05, to pass.
Table values are for an unthinned population; rejection thins big plates, moving ρ̄ by < 0.005 (ρ varies ≤ 0.14 over the
whole size range).

**Consequence for P1/P2 as registered (finding, not an amendment).** With exact edge weights the edge loss no longer
cancels truncation, so ρ > 1.05 at d/t = 1 (θ′ d 100 t 100: 1.071; T1 d 100 t 100: 1.055; θ′ d 190 t 200: 1.067). P1
("passes every CV 0 cell with d/t ≤ 1") is therefore **predicted refuted** at those cells, and P2's value is 1.14, not
1.08–1.10. The registered ship rule then gives areal-only unless a truncation correction is registered as a new item.

## 3. Generator, exact (changes from run 1 are the three marked ★)

Field S = 2400 nm; pixel p = 2.5 nm (960², registered) and 1.25 nm (1920², reported, not gated); foil 0 ≤ z ≤ t; plates
zero-thickness discs; θ′ normals ±x, ±y; T1 (±1, ±1, 1)/√3. ★ Raster: point sampling (§1). ★ Sizes: d = d̄ (CV 0) or
lognormal(σ² = ln(1+CV²), mean d̄) truncated at 4 d̄, drawn **size-biased by V(d) = (S+2R)²(t+h)** (rejection against V at
the cap) so the volumetric density of size d is ∝ f(d). ★ Overlap rejection on a canvas covering the whole generation box
(`T6_REJECT_EXTENDED` semantics of ADR 045) with margin ⌈R_cap/p⌉ + 2; 8-neighbour dilation of one pixel as before.
Centres uniform in x, y ∈ [−R, S+R], z ∈ [−h/2, t+h/2] of each plate's own R, h. Stop at 1 % in-field coverage.
Truth N_V = Σ over accepted plates 1/V(d_k) (= accepted/((S+2R)²(t+h)) at CV 0, as run 1). Counting: `classObjects` on
the 0/1 map, objects with touchesEdge == false; lengths L = lengthPx · p; bounding box bx, by; w = S²/((S−bx−p)(S−by−p)).
Grid: class {θ′, T1} × t {50, 100, 200} × d̄ {20, 100, 190} × CV {0, 0.3, 0.6} = 54 cells. d̄ 190 added by this note
(the real T1 size; reported against the table, gated like the rest). Seeds: SplitMix64 state =
cellIndex·0x100000001B3 + seedIndex·0xD6E8FEB86659FD93 + 0x12345678, two draws discarded; seedIndex 0,1,… until the SEM of
the ratio ≤ 0.015, minimum 20, cap 400. Size draws and positions use the one stream, in the order: size, cx, cy, cz,
normal bits. σ_N coverage (refuting observation 4): 100 seeds' ratios, error bar from the app formula, covered when
|N̂ − truth| ≤ σ_N, on cells whose table value is within 1.02. Naive N/(A t) is scored beside every cell.
