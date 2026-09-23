# T2 — The direction check: published maps vs truth, at object level

**DRAFT — owner review.** 2026-09-23 night, run on the owner's Mac (not in the cloud: the cloud
environment's proxy refuses `zenodo.org`, PR #2's `PROGRESS.md` B2). Brief:
[`../2026-09-23-brief.md`](../2026-09-23-brief.md) § T2. Neither Gate D trigger applies: nothing
under `mac4DSTEM/` changed and no app number moved; this is a measurement of published maps.

**Data.** Thronsen, E. et al., *Ultramicroscopy* 255 (2024) 113861; data Zenodo
[10.5281/zenodo.6645396](https://doi.org/10.5281/zenodo.6645396), CC BY 4.0: `ground_truth.hspy` and
`datasetA_phasemap_{ANN,NMF,TMP,vectors}.hspy`, each md5-checked against the record. The authors'
notebooks (`elisathr/SPED-phase-mapping`, no licence) were read to learn their conventions; no code
was copied.

**Commands** (Python 3.12.3, numpy 2.5.3, scipy 1.18.1, h5py 3.16.0):

```sh
python3 tools/cloud-analysis/direction_check.py fetch  DATA_DIR          # exit 0, 9/9 md5 OK
python3 tools/cloud-analysis/direction_check.py report DATA_DIR \
        References/thronsen-datasetA/truth_stride3.json                  # exit 0
```

The full printed output is [`T2-T3-report-output.md`](T2-T3-report-output.md). Objects are the
app's own definition through `tools/cloud-analysis/precipitate_objects_ref.py` (PR #2's Python
transcription of `PrecipitateSegmentation.classObjects`). On the app's real stride-3 map, that
reference reproduces all nine rows of the Swift probe's `--object-table` exactly (T3). So the
object numbers below are what the app's object step would print.

## Reading the files first

- **Coding.** All five files use 0 Al, 1 θ′ edge-on, 2 θ′ face-on, 3 T1. Only the truth (4 px)
  and the vectors map (607 px) use 4. Each map gives 85–100 % of each truth class the same label.
- **Their metric, reproduced to the digit:** `count(map ≠ truth) / 512²` = ANN 0.96 %, NMF
  1.50 %, vectors 1.54 %, TMP 1.75 %, identical to the paper and `determine_accuracy.ipynb`.
- **The stride-3 truth** (`[::3, ::3]`) is identical to the repo's
  `References/thronsen-datasetA/truth_stride3.json`, the one the app was scored against.

## The cleanup convention: there is no single rule

`create_ground_truth.ipynb` builds **three** truths, one per annotator. The final truth is a
**pixelwise 2-of-3 vote** (label 4 where all three differ). Each annotator removed small regions
per class with their own cut:

| class | annotator 1 | annotator 2 | annotator 3 | median (rule **P**) | bracket (rule **H**) |
|---|---|---|---|---|---|
| θ′ edge-on | area ≤ 3 removed (skimage `label`, 8-conn) | none | < 7 and < 5, one per orientation (scipy `label`, 4-conn) | keep ≥ 4, 8-conn | same |
| θ′ face-on | area ≤ 2000 removed (8-conn) | 3 blobs picked by hand | < 782 (4-conn) | keep ≥ 782, 4-conn | keep ≥ 2001, 8-conn |
| T1 | none (watershed only) | < 10 and < 30, one per orientation (4-conn) | < 28 (4-conn) | keep ≥ 10, 4-conn | keep ≥ 28, 4-conn |

Under a 2-of-3 vote, a region survives if at least two annotators keep it. If the masks agree
apart from the size cuts, that is the middle of the three cuts, so **P takes the median cut per
class**, counting "none" as keep ≥ 1. That assumption is only approximate: the masks come from
different reflections and thresholds. Where the median is ambiguous, P takes the less aggressive
value and H the more aggressive one. For face-on, annotator 2's cut is unstated. For T1, annotator
2 cut 10 on one orientation and 30 on the other; H uses annotator 3's 28, so a 30 bracket is
untested. Removed pixels become
Al, as they did when the truth was built. What P cannot reproduce:

- The annotators' masks differ in shape, so the vote leaves a few sub-threshold fragments. P
  would remove 1 edge-on and 5 T1 pixels from the truth itself; H would remove 1 and 39.
- Annotators 2 and 3 cut each orientation separately (two VDF masks per class). A class map
  has no orientation.
- Annotators 2 and 3 loop `np.arange(1, max(label))`, so the last-numbered region of each mask
  escapes their cut.

These thresholds belong to this dataset. At 4.63 nm/px, 782 px is about 16 800 nm² per face-on
plate. They are the truth's convention, used here only for a like-for-like comparison. They are not
a proposal for an app default.

## Results — object counts and lengths vs truth

Ratios are predicted / truth. Count includes edge-touching objects; the median is `sorted[n // 2]`
(both as the probe's `--object-table`). Per-class tables with split / merge / vanished / spurious:
[`T2-T3-report-output.md`](T2-T3-report-output.md).

**Full resolution, 512 × 512** (truth: edge-on 38 objects, median 36.3 px; face-on 3, 65.8 px;
T1 41, 59.3 px):

| map (per-position error) | edge-on count | edge-on median | face-on count | face-on median | T1 count | T1 median |
|---|---|---|---|---|---|---|
| ANN (0.96 %) | 1.05 | 0.89 | **20.0** | 0.02 | 1.29 | 0.67 |
| NMF (1.50 %) | 0.95 | 1.01 | **173** | 0.02 | **2.15** | **0.09** |
| vectors (1.54 %) | 1.50 | 0.52 | **82.7** | 0.02 | 1.39 | 0.61 |
| TMP (1.75 %) | 1.55 | 0.37 | **51.0** | 0.02 | **2.41** | **0.03** |
| any map · P | 0.89–0.95 | 1.03–1.14 | 1.00 | 0.99–1.03 | 0.95–1.02 | 0.99–1.09 |
| any map · H | 0.89–0.95 | 1.03–1.14 | 1.00 | 0.99–1.03 | 0.90–0.95 | 1.09–1.37 |

Area fraction is 0.95–0.99 of truth for T1 in every row. For face-on it is 1.01–1.23 raw and
1.01–1.07 cleaned. For edge-on it is 0.86–1.32 in both, because the cleanup does not move it.

**Stride 3, 171 × 171** (truth: edge-on 74 objects, median 1.00 px; face-on 3, 22.2 px; T1 37,
23.1 px):

| map | edge-on count | face-on count | face-on median | T1 count | T1 median |
|---|---|---|---|---|---|
| raw, four maps | 0.58–1.08 | 3.3–38.7 | 0.04 | 1.05–1.38 | 0.53–0.92 |
| cleaned (P) at full res, then subsampled | 0.57–1.08 | 1.00 | 0.97–1.03 | 0.97–1.05 | 0.92–1.18 |
| subsampled, then P on the grid (areas ÷ 9, rounded up) | 0.58–1.08 | 1.00 | 0.97–1.03 | 0.92–0.97 | 1.18–1.33 |

## The headline question

**At their own 0.96–1.75 % per-position error, do the published methods get object counts and
lengths right? Raw, no. With the truth's own cleanup the counts come out right, but the
independent refuter showed that a cleaned count comes out right for random noise too, so it
cannot tell a good classifier from a bad one.**

- **Raw maps.** No method gets θ′ face-on right: 20–173× the truth's 3 objects, median length
  1 px. 57–515 of those objects touch no truth face-on object. For T1, all four methods are
  1.29–2.41× the count and 0.03–0.67× the median length. Area fraction stays within about 5 %
  for T1 throughout. **The per-position metric and the area fraction cannot see speckle; object
  counts and lengths are dominated by it.**
- **Per-position rank does not predict object rank.** NMF (1.50 %) beats vectors (1.54 %)
  per position, but has 2.1× vectors' face-on objects (519 vs 248) and 1.5× its T1 objects
  (88 vs 57).
- **With the truth's convention (P)**, all four maps give 3/3 face-on objects, T1 counts at
  0.95–1.02 and medians at 0.99–1.09. Edge-on counts are 0.89–0.95 at full resolution. Every
  cleaned ratio is within 11 % of truth in count and 14 % in median length.
- **The cleaned count cannot certify a classifier** ([refutation](T2-T3-refutation.md)). With P
  applied, the truth plus random Al flips at the app's own false-call rate gives exactly
  truth·P's counts (37 / 3 / 40), and so does 5 % label noise over the whole map (38–41 / 3 / 40).
  P's cuts (782 / 10 / 4 px) sit far above the size of scattered-error components. The cleaned
  count does catch a deleted object, and sometimes boundary erosion (edge-on shattered to 16 in
  one trial). It misses a merge. **The classifier's signal is in what the cleanup removes:
  raw spurious objects (57–515 face-on here) and location overlap (split / merge / vanished).**
- **At stride 3, θ′ edge-on is not measurable as objects by anyone.** The truth itself goes from
  38 to 74 objects with a median length of 1 px: the needles are about one sample wide, so
  subsampling breaks them. No cleanup changes this (its grid threshold is 1 px). Face-on and T1
  keep their object statistics at stride 3.

**Limits.** This is one dataset with one truth. The cleanup thresholds are that truth's, so a
second dataset with smaller face-on plates would need its own. The spreads above come from four
methods, not from a resampling. Every number here was recounted independently:
[T2-T3-refutation.md](T2-T3-refutation.md).
