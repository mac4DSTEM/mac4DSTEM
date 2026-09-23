# T3 — How much of the app's object gap is sampling and cleanup?

**DRAFT — owner review.** 2026-09-23 night, on the owner's Mac. Brief § T3. Data and cleanup
rules as in [T2](T2-direction-check.md). The brief assumed the app could not be rerun. On a Mac it
can, so this report measures on the **app's own stride-3 map** rather than reasoning from the
overnight record's quoted numbers.

**Neither Gate D trigger applies.** The one code change is a new, off-by-default
`--dump-labels <path>` flag in `tools/phase-map-probe/main.swift`, a diagnostic tool. It writes the
label maps the probe's `--object-table` already builds. Nothing under `mac4DSTEM/` changed.

## Commands

```sh
tools/thronsen-dataset/run.sh probe --rule known-variants --or --min-relative 0.001 \
  --min-intensity 0 --object-table --dump-labels LABELS_JSON          # exit 0
python3 tools/cloud-analysis/direction_check.py app LABELS_JSON \
  References/thronsen-datasetA/truth_stride3.json                    # exit 0
```

The probe command is the overnight refuter's (`precipitate-overnight-2026-09-23.md` § Independent
refutation), plus the new flag. It reprints the overnight numbers unchanged: 529/29 241 = 1.81 %,
and object rows 101/70/62 (baseline) and 85/54/48 (guarded). The Python output is
[`T3-app-output.md`](T3-app-output.md).

**Python vs Swift, on real data.** The Python reference of the object step reproduces every
count, median length and area fraction of the probe's Swift `--object-table`: 9 of 9 rows (truth,
baseline and guarded × three classes). PR #2 could only check the reference against the Swift
tests' hand-derived values. This is its first check against the compiled code.

## The decomposition (stride 3, known-variants baseline = the app today)

| class | truth full res → stride 3 (sampling alone) | app raw | app with the truth's convention on the grid (P/9) | what remains vs truth at stride 3 |
|---|---|---|---|---|
| θ′ face-on | 3 → **3** objects; median 65.8 → 22.2 px (÷ 3 is the unit change) | 70 objects, median 1.00 px; 67 touch no truth face-on object | **3** objects, median 22.85 px, area fraction 0.0346 | count 0; median ×1.03; area fraction ×1.04 |
| T1 | 41 → **37** objects; median 59.3 → 23.1 px | 62 objects, median 8.61 px; 23 touch no truth T1 object | **37** objects, median 23.34 px, area fraction 0.2172 | count 0 vs truth, ×1.09 vs the cleaned truth (34); median ×1.01; split 1, merge 1, vanished 2, spurious 2 |
| θ′ edge-on | 38 → **74** objects; median 36.3 → **1.00** px | 101 objects, median 1.00 px; 49 touch no truth edge-on object | 101 (the grid threshold is 1 px, so P does nothing) | count ×1.36, area fraction ×1.54 |

With the more aggressive bracket H/9, T1 drops to 32 objects (×0.86). **The fair T1 reference is
34, not 37.** The truth itself loses 3 T1 objects under P/9 (37 → 34;
[T2-T3-report-output.md](T2-T3-report-output.md) § T3): on the grid the cut also removes real
single-sample T1 objects. With both sides cleaned, the app's T1 gap is 37 vs 34 (×1.09), not 0.
The face-on comparison is unaffected (3 vs 3 either way).

**"70 vs 3" (θ′ face-on).** Sampling accounts for none of it: the truth has 3 objects at both
resolutions. All of it is speckle that the truth's cleanup removes. P/9 takes out the 67
sub-87-px objects and leaves 3 at median ×1.03. The published methods show the same speckle raw at
stride 3 (10–116 objects), so this is not specific to the app's classifier.

**"62 vs 37" (T1).** Sampling explains 41 → 37 in the truth. It does not explain the app's excess,
which is also measured against the stride-3 truth. P/9's T1 cut on the grid is 2 px, so it removes
exactly the single-sample objects. That takes the app from 62 to 37 at median ×1.01, or 37 vs 34
against the cleaned truth. Raw, the app is worse than all four published methods at stride 3 (62
objects vs their 39–51, median 8.61 vs 12.17–21.25 px). Cleaned, it sits inside their range
(34–39 objects, 21.4–30.8 px).

**But being inside that range certifies nothing about the classifier**
([refutation](T2-T3-refutation.md)). A null map, the stride-3 truth plus random Al flips at the
app's own false-call rate (0.71 % per-position error, raw 74 / 93 / 145 objects), cleans to
74 / 3 / 34, exactly the cleaned truth. The app (1.81 %) cleans to 101 / 3 / 37. On
cleaned counts, scattered random error scores at least as well as the app. So the right reading
is: **the object gap is speckle that the truth's convention removes, and how much speckle a
classifier makes is measured before cleanup**. The app's raw spurious objects are face-on 67
(published 7–113), T1 **23** (published 1–13) and edge-on **49** (published 0–5).

**What remains for the classifier** is raw speckle, where the app sits outside the published
range on T1 (23 spurious objects vs 1–13), and θ′ edge-on, the one class the cleanup does not
touch at all. The app over-calls edge-on: area fraction ×1.54, 49 of 101 objects spurious. That matches the
overnight record's known T1 → θ′ edge-on confusion (53 positions). But edge-on object statistics
are not measurable at stride 3 even for the truth (T2), so the count comparison there means little.
The area fraction is the usable edge-on number.

**Scoring P/9 against this truth is partly circular**, because the truth was built with the same
kind of cut. P/9 lowers the app's per-position error from 1.81 % to 1.57 % (guarded 1.45 % →
1.31 %). That is agreement with the truth's convention, not a better classifier, and it should not
be read as a proposal to ship a cut. The thresholds belong to this dataset (T2 § The cleanup
convention).
