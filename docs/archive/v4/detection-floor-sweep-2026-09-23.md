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

Logs (session scratchpad, not retained): `floor-0.001.log`, `floor-0.0015.log`, `floor-0.002.log`,
each exit 0 on its own line (`floor-exits.txt`), and `app-0.001.log`, `app-0.0015.log`,
`app-0.002.log`, each exit 0. The 0.1 % rerun reprints 529 = 1.81 % and 101/70/62, and its Python
object output is byte-identical to T3's `app.log`. The instrument is unchanged.

| floor | per-position error | Al → precipitate | T1 → Al | face-on → Al | T1 / face-on / edge-on raw spurious objects | T1 area fraction (truth 0.2174) | face-on area fraction (truth 0.0332) | edge-on area fraction (truth 0.0143) | T1 after P/9: objects, split, vanished |
|---|---|---|---|---|---|---|---|---|---|
| 0.1 % | 529 = **1.81 %** | 407 | 39 | 0 | 23 / 67 / 49 | 0.2183 | 0.0372 | 0.0219 | 37, 1, 2 |
| 0.15 % | 424 = **1.45 %** | 150 | 177 | 26 | 5 / 36 / 9 | 0.2106 | 0.0343 | 0.0181 | 34, 2, 5 |
| 0.2 % | 1189 = **4.07 %** | 94 | 671 | 367 | 2 / 26 / 11 | 0.1935 | 0.0220 | 0.0170 | 40, 5, 5 |

Correct precipitate calls, truth → same class: T1 6258 → 6129 → 5647 of 6358; face-on
969 → 944 → 603 of 970; edge-on 398 → 400 → 402 of 417. With the known-variants guard
(`specific ≥ 1`, `--al-precipitate-detail` sweep A): 1.45 % → **1.31 %** (383) → 3.99 %.
Published raw spurious objects at stride 3 (T2): T1 1–13, face-on 7–113, edge-on 0–5.

### Against the prediction

- **Per-position error: REFUTED at 0.15 %.** It fell (1.81 → 1.45 %) where I predicted a rise.
  At 0.2 % it rose to 4.07 %, inside the predicted 2.5–5 %. **So error is not monotone in the
  floor over this range.** The 09-16 sweep's 0.1 → 0.2 % rise (+2.43 points) recurs here
  (+2.26 points). Its 0.15 % point was never measured.
- **Directions held on every other metric:** Al false calls fell (407 → 150 → 94), T1 misses
  rose (39 → 177 → 671), T1 and face-on raw spurious objects fell, T1 area fraction fell below
  the truth, and T1's vanished and split counts rose.
- **θ′ edge-on area fraction: REFUTED.** It fell 17 % and 22 % (predicted within ±10 % and
  ±15 %), toward the truth. Al → edge-on false calls went 188 → 94 → 70 and T1 → edge-on went
  53 → 36 → 26. Edge-on's reflections are strong, but much of its excess area was false calls,
  and those shrink with the floor.

What the numbers show, without a mechanism claimed: the floor trades Al false calls against
precipitate recall. Between 0.1 % and 0.15 %, 257 fewer Al false calls outweigh 138 more T1 and
26 more face-on misses. Between 0.15 % and 0.2 %, 56 fewer false calls cost 494 T1 and 341 face-on
misses; face-on recall falls to 62 %.

### On the T4 draft's object metrics

At **0.15 %, the app's raw speckle falls inside the published range** on T1 (5 vs 1–13) and
face-on (36 vs 7–113). Edge-on (9 vs 0–5) is still outside but much closer than 49. At 0.1 % T1
was outside (23). The cost shows after cleanup: T1 vanishes 5 truth objects (2 at 0.1 %), and its
P/9 count is 34, equal to the cleaned truth. At 0.2 % the precipitates are lost: face-on area
fraction 0.66× truth, 38 % of face-on positions called Al, and under H/9 two of three plates gone.

**0.15 % is the best of these three points on this dataset.** A threshold is a property of the
dataset and settings it was measured under (`CLAUDE.md`). Three points are not a curve, and the
minimum could lie anywhere between 0.1 % and 0.2 %. The app's 0.5 % default is untouched, per the
owner. Owed by the T4 draft and not run here: the null-map raw spurious counts, and the
convention-break mutations.
