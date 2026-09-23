# T4 — Draft pre-registration: an object-level pass bar for phase mapping

**DRAFT — owner review. Nothing here is decided.** Drafted 2026-09-23 night from
[T2](T2-direction-check.md) and [T3](T3-gap-decomposition.md), in the shape of `ROADMAP.md`
§ "How a v3 feature is done": what it touches, who owns its state, the tests written first, the
decisions owed. Data: Thronsen et al., *Ultramicroscopy* 255 (2024) 113861; Zenodo
10.5281/zenodo.6645396, CC BY 4.0.

## Why a new bar

The per-position metric (the paper's `count(map ≠ truth) / N`) is the only bar phase mapping has
had. T2 shows it cannot see what users measure. At 0.96–1.75 % per-position error, the four
published maps have 20–173× the truth's θ′ face-on objects and 1.29–2.41× its T1 objects, all
with area fraction within 5 % for T1. Per-position rank does not predict object rank either:
NMF beats vectors per position but is worse on objects. Precipitate objects are the product
(count, length, area fraction), so the bar has to be stated at object level.

## What it touches, and who owns the state

- **Measurement only.** `tools/phase-map-probe --object-table --dump-labels` (the app's own
  `PhaseMapObjectsBridge` → `PrecipitateSegmentation.classObjects`) and
  `tools/cloud-analysis/direction_check.py app`. No `mac4DSTEM/` source. No app state.
- **Out of scope:** any cleanup step inside the app. If the owner ever wants one, it is a separate
  feature with its own pre-registration. Its state would belong to the phase-map objects bridge,
  and its thresholds would be dataset properties the user sets, never a shipped default.

## Metrics, per class, predicted vs truth

The independent refuter ([T2-T3-refutation.md](T2-T3-refutation.md)) showed that **cleaned counts
alone cannot certify a classifier**. Random Al flips at the app's own false-call rate clean up to
exactly the truth's counts, and so does 5 % label noise. The metrics are therefore in two tiers.

**Primary: the classifier's own signal, measured before any cleanup.**

1. **Raw spurious objects**: predicted objects touching no truth object of their class. T3: the
   app has 23 for T1, against the published 1–13 at the same stride.
2. **Location overlap after cleanup**: split / merge / vanished (probe definitions). These catch
   the deleted-object case the refuter built. A merge can still hide behind an unrelated removal
   (refutation § null maps (c)), so merges are also counted raw.

**Secondary: the product numbers, like for like, after the convention.**

3. **Object count ratio.**
4. **Median length ratio**, with the IQR reported: `sorted[n // 2]`, all objects including
   edge-touching, as `--object-table` has always printed it.
5. **Area fraction ratio.**
6. Per-position error, reported for continuity. It does not gate.

## The like-for-like convention (named, not tuned)

- **Resolution:** stride 3, `[::3, ::3]` from 0 (what the app runs on dataset A today;
  `tools/thronsen-dataset/make_truth.py`).
- **Cleanup:** the truth's own convention, rule **P** from T2 (the median of the three
  annotators' cuts: θ′ edge-on keep ≥ 4 px 8-conn, θ′ face-on ≥ 782 px 4-conn, T1 ≥ 10 px
  4-conn). It is applied to the prediction on the grid with areas ÷ 9, rounded up. Rule **H**
  (face-on 2001 px 8-conn, T1 28 px) is always reported beside it as the sensitivity bracket.
  These are **the paper's convention on this dataset**, not a method property.
- **θ′ edge-on:** at stride 3 the truth itself breaks from 38 to 74 objects with a median length
  of 1 px, so its object count and length are **not scored**. Edge-on is scored on area fraction
  and raw spurious count only, unless the owner funds a full-resolution run (below).

## Reference level: the best published methods, same footing

At stride 3 with P/9 (T2), the four published maps reach:

| class | count ratio | median length ratio | area fraction ratio | raw spurious objects |
|---|---|---|---|---|
| θ′ face-on | 1.00 (all four) | 0.97–1.03 | 1.00–1.07 | 7–113 |
| T1 | 0.92–0.97 | 1.18–1.33 | 0.95–0.99 | 1–13 |
| θ′ edge-on | not scored | not scored | 0.87–1.36 | 0–5 |

At full resolution with P, every published ratio is within 11 % in count and 14 % in median
length. The app today (known-variants baseline, stride 3, P/9; T3) scores face-on 1.00 / 1.03 /
1.04, T1 1.00 / 1.01 / 1.00, edge-on area 1.54. Raw spurious counts are face-on 67, T1 **23**,
edge-on **49**.

## Datasets

- **Dataset A:** has the truth. It is the only dataset where accuracy can be claimed.
- **Dataset B:** Zenodo has the four published maps (`datasetB_*`) but **no truth**. B can show
  whether the app's objects fall within the spread of the four methods' objects under the same
  convention. That is **agreement, never accuracy**. Running the app on B needs the 9.0 GB
  `datasetB_preprocessed.hspy` streamed and subsampled. `tools/thronsen-dataset` handles A only
  today. Whether B is worth that cost is an owner decision.

## Tests written first

- The Python reference's own `selftest` / `mutate` / `crosscheck` (PR #2, exit 0 here).
- **Swift = Python on the run's own map:** the `app` step reprints the probe's `--object-table`
  rows and the two must agree row for row (9/9 on 2026-09-23). A disagreement stops the run.
- **Break the convention before trusting it:** off-by-one on the ÷ 9 rounding, or 4- vs
  8-connectivity for face-on, must move at least one reported number. Not yet run; owed with the
  first scored run.
- **The null map must fail the bar:** the truth plus random Al flips at the run's own measured
  false-call rate (`tools/cloud-analysis/refute_null_maps.py`, seeded). If the null passes on
  every metric, the bar is blind and the run does not count. On cleaned counts the stride-3 null
  passes today (74 / 3 / 34, identical to the cleaned truth). Its raw counts are 74 / 93 / 145
  against the truth's 74 / 3 / 37 (refuter's run), so raw spurious objects should fail it, but
  **that has not been measured**. The null's raw spurious counts are owed and must be printed by
  the first scored run.

## The prediction a future run must state before it runs

Every change to phase mapping that claims an object-level effect writes, before running, one line
per metric per scored class: direction (up / down / unchanged) and rough size, against the baseline
row above. Two examples:

- **The owner's next run, the detection floor at 0.1 / 0.15 / 0.2 %:** state before running
  whether T1 raw spurious objects (23 today) move toward the published 1–13, and whether the P/9
  T1 count stays at 37 ± 2.
- **The known-variants guard (k ≥ 1):** the overnight refuter already showed that its T1
  median-length gain is singletons removed from the median. Under this bar the guard is judged
  on raw spurious counts (T1 23 → 9, edge-on 49 → 21; T3) and must leave the P/9 row unchanged
  within the H bracket.

## Decisions owed to the owner

1. Adopt object-level metrics as phase mapping's pass bar, with per-position error kept as a
   continuity number.
2. The convention: P with H as the bracket, applied on the grid (as here) or before subsampling.
   The two orders differ by up to 0.13 in T1 count ratio and 0.41 in median-length ratio (TMP; T2 stride-3 table).
3. The bar's form, for example "within the published four methods' range on every scored metric"
   or "within their range plus a margin". The brief forbids this draft from choosing an X.
4. θ′ edge-on: accept area-only scoring at stride 3, or fund a full-resolution run (the
   7.4 GB dataset A, on this Mac's disk floor).
5. Whether dataset B's agreement run is worth its 9 GB.
