# Parity with the published references (app level)

The kits' own parity tables are `../<Kit>/docs/parity.md`. This file lists what the app has been checked against as a whole.
Numbers match the reference within its own spread, never stricter (suite rule D17).

## Precipitation workflow: Thronsen et al., Ultramicroscopy 255 (2024) 113861 (Al-Cu-Li, T1 + θ′, SPED)

Data: Zenodo 10.5281/zenodo.6645396 (CC BY 4.0, kept outside the repo in `References/mac4DSTEM/thronsen-datasetA`). Dataset A, 512 × 512
(PDF page 3), stride 3 here (171 × 171; the full cube is not on this disk). Facts, page and table per number: `mac4DSTEMTests/Fixtures/thronsen-parity/truth.json`.
Run (heavy, real data, skipped unless asked; 8 GB cap): `../tools/memcap.sh --gb 8 -- env TEST_RUNNER_MAC4DSTEM_THRONSEN=1 MAC4DSTEM_UNIT_ONLY=ThronsenParityTests tools/run-tests.sh unit`
(`mac4DSTEMTests/ThronsenParityTests.swift`, 8 s after the build).

| Check | Reference | Ours | State |
|---|---|---|---|
| Phase map accuracy, the paper's metric (share of positions equal to the manual ground truth, all classes counted) | Table 3 (PDF page 11), full resolution: NMF 98.50, vector matching 98.46, template matching 98.25, ANN 99.04 % | **98.69 %** at stride 3 (383 of 29 241 positions differ; 774 243 peaks) | inside the paper's spread (98.25 to 99.04); the published maps at stride 3 are 98.44 / 98.49 / 98.30 / 99.05 % (computed by us from the Zenodo maps, not published) |
| Same, as the adopted T4 bar (ADR 040, 041) | per-position error 1.31 % | 1.31 % | reproduced; pinned in the test (±0.05) |
| Object statistics: count, Feret length, edge-corrected areal density (tasks 39 and 41) | none in the paper; derived from the truth map, **not published** | see below | exercises the pipeline end to end; unvalidated |
| N_V, composition, strain | none (no thickness, no EDS in the dataset) | not checkable here | said so, not scored |

Objects at the stride-3 step (7.4829 nm per position, the file's 2.4943 nm × 3), raw, no minimum size, edge-touching objects excluded from the counts:

| class | truth counted (edge) | ours counted (edge) | count ratio | median Feret, truth / ours | density /µm², truth / ours |
|---|---|---|---|---|---|
| θ′ edge-on | 70 (4) | 75 (4) | 1.07 | 7.5 / 15.0 nm | 45.1 / 48.4 |
| θ′ face-on | 3 (0) | 35 (1) | 11.7 | 166 / 7.5 nm | 2.4 / 22.5 |
| T1 | 21 (16) | 26 (17) | 1.24 | 102 / 80 nm | 17.1 / 20.2 |

Where the maps differ (positions, truth to ours): T1 to Al 204, Al to θ′ edge-on 55, θ′ face-on to Al 26, Al to face-on 25, Al to T1 24. The raw face-on count is
speckle: the T4 bar applies its cleanup rule before comparing (archived scorer `t4_score.py`), which this table does not apply (the app's minimum-object-size setting was left at 1 px); with cleanup the T4 run found
count, median and area ratios inside the published spread for T1 and face-on, and θ′ edge-on raw spurious objects 7 against a limit of 5. More than half of all disagreeing
positions are one failure: T1 patterns read as Al (204 of 383 positions, 0.7 % of the scan).
