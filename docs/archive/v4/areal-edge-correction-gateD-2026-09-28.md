# Areal precipitate density: the edge rule reads low — Gate D (2026-09-28 night)

Owner's go 2026-09-28 night ("Fix it, Gate D"). Registered before any code or run.

## Diagnosis

`PrecipitateStatistics.density` counts only objects clear of the scan edge (`touchesEdge == false`) but divides by the
whole analysed area. An object of bounding box bx × by pixels is counted only when it lies inside the (W − 2)(H − 2)
interior, so the count falls short by the probability an object its size is cut — larger objects more. Found by
reading the code (T6 amendment §7) and confirmed by the T6 refuter (`volumetric-density-preregistration-2026-09-28.md`
§10): ≈ 13–17 % low for T1 on Thronsen A, whose model predicts edge/counted 0.29–0.40 against the drive's 14/43.

**Refuted if** the corrected rule below does not move the synthetic foil's areal density onto truth, or the current
rule already reads within 3 % at d = 190 nm.

## The fix (Miles–Lantuéjoul)

Each counted object carries the weight wᵢ = W·H / ((W − bxᵢ − 1)(H − byᵢ − 1)), bxᵢ, byᵢ its bounding box in pixels —
the inverse of the fraction of positions at which a box that size lies clear of the border row. Areal density =
Σ wᵢ / (analysed pixels × p²). Counts shown stay integers; the density, the CSV and provenance name the rule.
`density` gains the frame's width and height; its two callers pass them. Assumption stated: the frame is the whole
scan; not-indexed pixels inside it are not treated as edges.

## Experiment and prediction (T6 harness, areal mode, same generator as T6 run 1)

Truth λ = visible plates per area = accepted / (S + 2R)². Cells: θ′ edge-on and T1 × d ∈ {20, 100, 190} nm ×
t ∈ {50, 100, 200} nm, field 2400 nm, pixel 2.5 nm; plus one Thronsen-geometry cell (pixel 13.89 nm, 171²,
T1 d 190, t 100). Predicted ratio (areal / truth), the ≤ 1 % of sub-pixel plates (refuter) not modelled:

| | θ′ d 20 | θ′ d 100 | θ′ d 190 | T1 d 20 | T1 d 100 | T1 d 190 |
|---|---|---|---|---|---|---|
| current rule | 0.99 | 0.96 | 0.92 | 0.99 | 0.93 | 0.87 |
| corrected | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

**Bar:** corrected within ±3 % in every cell (mean over seeds, SEM ≤ 1 %); the current rule must fail it in at least
the T1 d 190 cells (the test can fail). The Thronsen-geometry cell is reported, not barred.

## Then

Unit tests before the app change, each broken first (a hand-computed weight; an interior object's weight > 1; the
edge-excluded object still excluded; a 1×1 object's weight). Refuter on the diagnosis and the run. Unit + scientific
gates. ADR if it passes.

## Run 1 (`areal-run1.log`; T6 run 1 reproduced byte-identical first)

The app's own `density.arealDensity` equals the "current" column in every cell. **Current rule: fails where
predicted** (0.88–0.95 at d 100/190). **Corrected: FAILS one cell as registered** — θ′ d 190 t 100, 0.957 ± 0.009;
all three θ′ d 190 cells sit ≈ 3 % low (0.971, 0.957, 0.974); every other cell 0.990–1.025.

```
theta' edge-on d= 20 t= 50  current 0.978+-0.001 PASS  corrected 0.990+-0.001 PASS
theta' edge-on d= 20 t=100  current 0.982+-0.001 PASS  corrected 0.994+-0.001 PASS
theta' edge-on d= 20 t=200  current 0.985+-0.001 PASS  corrected 0.997+-0.001 PASS
theta' edge-on d=100 t= 50  current 0.952+-0.005 FAIL  corrected 0.991+-0.005 PASS
theta' edge-on d=100 t=100  current 0.953+-0.004 FAIL  corrected 0.994+-0.004 PASS
theta' edge-on d=100 t=200  current 0.952+-0.006 FAIL  corrected 0.994+-0.006 PASS
theta' edge-on d=190 t= 50  current 0.904+-0.008 FAIL  corrected 0.971+-0.009 PASS
theta' edge-on d=190 t=100  current 0.889+-0.008 FAIL  corrected 0.957+-0.009 FAIL
theta' edge-on d=190 t=200  current 0.901+-0.008 FAIL  corrected 0.974+-0.008 PASS
T1 {111} d= 20 t= 50  current 0.980+-0.002 PASS  corrected 0.997+-0.002 PASS
T1 {111} d= 20 t=100  current 0.980+-0.003 PASS  corrected 0.997+-0.003 PASS
T1 {111} d= 20 t=200  current 0.979+-0.002 PASS  corrected 0.996+-0.002 PASS
T1 {111} d=100 t= 50  current 0.937+-0.009 FAIL  corrected 0.994+-0.010 PASS
T1 {111} d=100 t=100  current 0.953+-0.009 FAIL  corrected 1.014+-0.010 PASS
T1 {111} d=100 t=200  current 0.951+-0.009 FAIL  corrected 1.017+-0.010 PASS
T1 {111} d=190 t= 50  current 0.883+-0.009 FAIL  corrected 0.982+-0.010 PASS
T1 {111} d=190 t=100  current 0.916+-0.009 FAIL  corrected 1.025+-0.010 PASS
T1 {111} d=190 t=200  current 0.889+-0.009 FAIL  corrected 1.001+-0.010 PASS
```

**Hypothesis M (before any further run):** the harness rejects an overlapping plate only against in-field pixels, so
plates centred in the margin [−R, 0) ∪ (S, S + R] are never rejected yet count in truth. Where rejection is high
(θ′ d 190: 16 %) and the margin large ((S + 2R)² − S² = 14 % of the box), truth is inflated by ≈ 0.14 × 0.16 ≈ 2–3 %,
matching. **Predicted:** rejecting on an extended canvas covering the whole box moves the θ′ d 190 corrected cells to
≈ 0.99–1.00 and leaves T1 (rejection ≈ 2 %) within its SEM. **Refuted if** θ′ d 190 stays ≈ 3 % low.

