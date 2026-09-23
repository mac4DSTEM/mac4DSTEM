# Relative detection floor sweep, 0.1 / 0.15 / 0.2 % — Thronsen dataset A, 2026-09-23 night

The owner's next run (`docs/status.md` handoff, commit `b3584d3`): the relative detection floor at
0.1 / 0.15 / 0.2 % "at today's settings". 0.15 % is his working value on this data and has never
been scored against the truth. The app's 0.5 % default is not under test: the floor is
dataset-dependent (owner). **A measurement, not a proposal. Neither Gate D trigger applies:** no
code changes and no app number moves.

Data: Thronsen et al., *Ultramicroscopy* 255 (2024) 113861; Zenodo 10.5281/zenodo.6645396,
CC BY 4.0 (stride-3 subsample, `tools/thronsen-dataset`).

## Settings (identical across the three runs)

```sh
tools/thronsen-dataset/run.sh probe --rule known-variants --or --min-relative F \
  --min-intensity 0 --al-precipitate-detail --object-table --dump-labels labels-F.json
python3 tools/cloud-analysis/direction_check.py app labels-F.json \
  References/thronsen-datasetA/truth_stride3.json
```

F = 0.001, 0.0015, 0.002. These are today's settings: the known-variants rule, per-phase slab (the
default), `--or`, library intensity floor 0. They are the overnight refuter's command plus
`--dump-labels`. 0.001 is tonight's baseline (1.81 %), rerun here so all three come from one build.
Object metrics follow the T4 draft (`docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md`):
raw spurious objects and split / merge / vanished first, cleaned (P/9) counts second.

## Prediction — committed before any run

The 2026-09-16 sweep (`archive/v3/step3-2026-09-16.md`, an older rule) went from 4.21 % at 0.1 % to
6.64 % at 0.2 %, mostly as missed precipitates: a higher floor loses the weak precipitate
reflections. The known-variants rule has changed what counts as a match since then, so I
predict directions firmly and sizes loosely:

| metric (baseline at 0.1 %) | 0.15 % | 0.2 % |
|---|---|---|
| per-position error (1.81 %) | up, 1.9–3.5 % | up further, 2.5–5 % |
| Al → precipitate false calls (407) | down | down further |
| T1 → Al / not-indexed misses | up | up further |
| T1 raw spurious objects (23) | down | down further |
| θ′ face-on raw spurious objects (67) | down | down further |
| T1 area fraction (0.2183; truth 0.2174) | down, below truth | further below |
| T1 after P/9: vanished (2), split (1) | up or equal | up |
| θ′ edge-on area fraction (0.0219) | within ±10 % (strong reflections) | within ±15 % |

**Refuted if:** per-position error falls at 0.15 % or 0.2 %; or T1 raw spurious objects rise. Either
would mean the floor's main effect on this data is not the weak-reflection loss seen on 09-16.

## Result

*(Written after the runs.)*
