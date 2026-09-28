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
