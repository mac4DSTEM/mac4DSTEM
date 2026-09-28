# Stride invariance on Thronsen A — registration (2026-09-28 night)

ROADMAP 3's first test, on the local cube (owner, 2026-09-28: "this would be important as a test"). No ground truth
needed: the same scan analysed at real-space stride 3, 6 and 9 must agree where the physics says it should.
Registered before the probe change exists.

## Set-up

`datasetA_stride3.h5` is every 3rd position of the 513² scan; every 2nd / 3rd position of it is stride 6 (86²) and
9 (57²). The phase-map probe gains `--scan-stride N` (N = 1, 2, 3 on this cube; truth and positions subsampled
together) and prints the edge-corrected areal density per class (pixel = 13.89·N nm, `PrecipitateStatistics.density`).
Configuration: the B1 record's T4 command (known variants, guard, 0.15 % floor, reach 0.68). Minimum object size
held at a constant AREA (10 px at N = 1 → round(10/N²): 3 px, 1 px). Runs one at a time.

## Predictions

1. **Labels (sharp):** classification is per position, so the stride-6/9 labels equal the stride-3 labels at the
   kept positions at ≥ 99.9 % of positions; any difference comes from whole-scan fits (matrix orientation) and is
   listed. **Refuted if** < 99.9 % — then something per-position depends on the scan it sits in.
2. **Phase fractions:** within 1 percentage point of stride 3 for every class (sampling only).
3. **Edge-corrected T1 density:** within its Poisson error of stride 3 at stride 6; at stride 9 lower (T1 traces of
   ≈ 190 nm are ≈ 4.6 px, and objects merge or split with the grid). Reported with errors, not barred. θ′ (3 face-on
   objects) is too few to read.
4. **T1 median length:** quantised — reads near 13.89·N-nm multiples; a change of up to one pixel is expected.

## What it is for

(1) proves the per-position independence the whole precipitate path assumes; (3)–(4) measure, on real data, the
one-pixel length effect T6 found on synthetic data — the argument for keeping stride 3 (or finer) for density.
