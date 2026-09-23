# T2/T3 independent refutation — Thronsen dataset-A direction check

**DRAFT — owner review.** 2026-09-23 night. Refuter: a separate agent (Sonnet) that did not write
T2/T3, briefed to break them; it imported neither `direction_check.py` nor
`precipitate_objects_ref.py`. Its report is kept verbatim below this header. Its scripts are
committed as `tools/cloud-analysis/refute_verify.py` and `refute_null_maps.py`, with the scratch
paths replaced by arguments. Rerun from the repo, each exits 0 and prints output identical to the
refuter's own run:

```sh
python3 tools/cloud-analysis/refute_verify.py    DATA_DIR References/thronsen-datasetA/truth_stride3.json LABELS_JSON
python3 tools/cloud-analysis/refute_null_maps.py DATA_DIR References/thronsen-datasetA/truth_stride3.json LABELS_JSON
```

(`DATA_DIR` from `direction_check.py fetch`; `LABELS_JSON` from the probe's `--dump-labels`,
T3 § Commands.) Data: Thronsen et al., Zenodo 10.5281/zenodo.6645396, CC BY 4.0. How T2–T4
changed in response is at the end.

## C1 — per-position error — **NOT REFUTED**

Recomputed `count_nonzero(map != truth)/512²` directly from the nine `.hspy` files:

| method | this run | paper |
|---|---|---|
| ANN | 0.9609 % | 0.96 % |
| NMF | 1.4980 % | 1.50 % |
| TMP | 1.7479 % | 1.75 % |
| vectors | 1.5430 % | 1.54 % |

All four match the paper to rounding. Confirms the class-coding and array
orientation used to load the `.hspy` files is correct (a transposed or
mis-oriented load would have broken every one of these numbers).

## C2 — raw object counts — **NOT REFUTED**

Independent `scipy.ndimage.label(mask, structure=np.ones((3,3)))` (8-connected),
component = every connected region, edge-touching included, per class:

Full res (512×512), edge-on/face-on/T1:
- truth 38/3/41 — exact match
- ANN 40/60/53 — exact match
- NMF 36/519/88 — exact match
- TMP 59/153/99 — exact match
- vectors 57/248/57 — exact match

Stride 3 (`[::3,::3]`), same order:
- truth 74/3/37, ANN 51/10/39, NMF 80/116/51, TMP 43/21/45, vectors 52/36/39 — all exact matches.

Also confirmed `truth_stride3.json["labels"]` is bit-identical to `ground_truth.hspy[::3,::3]`.

## C3 — the cleanup-rule derivation — **PARTLY REFUTED**

Read `create_ground_truth.ipynb` cell by cell (96 cells; full cell-by-cell index built and inspected).

**Confirmed correct:**
- Cell 1: "Three different ground truths were prepared by three different people…" — three annotators, confirmed.
- Cell 92 is the actual combination rule:
  ```
  if gt1[i,j]==gt2[i,j]: gt[i,j]=gt1[i,j]
  if gt1[i,j]==gt3[i,j]: gt[i,j]=gt1[i,j]
  if gt2[i,j]==gt3[i,j]: gt[i,j]=gt3[i,j]
  if all three differ:   gt[i,j]=4
  ```
  This is mathematically a genuine 2-of-3 majority vote (any pairwise agreement wins; three-way disagreement → 4). The "2-of-3 majority vote" claim is correct.
- Every literal threshold number in `RULES` traces to a real notebook cell:
  - Edge-on 4 (P **and** H): cell 26, `skimage.measure.label`+`regionprops`, `area <= 3` removed ⇒ keep `area ≥ 4`. `skimage.measure.label` defaults `connectivity=input.ndim` = 2D full connectivity = 8-connected — the "(4, 8)" attribution is correct.
  - Face-on H = 2001: cell 27, same skimage call, `area <= 2000` removed ⇒ keep `≥ 2001`, 8-connected — correct.
  - Face-on P = 782, T1 H = 28: cell 73 (`Theta_3` `label_th=782`; `T1_1`/`T1_2` `label_th=28` each), cleaned in cell 78 via `scipy.ndimage.label(precip.vdf_mask)` with **no** `structure` argument. `scipy.ndimage.label`'s default structure is `generate_binary_structure(rank,1)` = 4-connected — the "(782, 4)" and "(28, 4)" attributions are correct.
  - T1 P = 10: cell 49, `scipy.ndimage.label(righttop_mask)` (again default = 4-connected), `th = 10` — correct.
  - The `np.sum(labs[labs==i])/i < th` idiom (cells 49/53/78): checked by hand — since every pixel in `labs[labs==i]` has value `i`, `sum/i` equals the pixel **count** of component `i`. It is an obfuscated area computation, not a bug. Verified correct, contrary to how it reads at a glance.

**Refuted or weakened:**
1. **T1's "aggressive bracket" (H=28) is not actually the most aggressive value in the notebook.** Cell 53 (`lefttop_mask`, also T1, same annotator/GT2) uses `th = 30`, not 10 or 28 — a threshold *more* aggressive than the claimed H=28. The notebook contains at least three distinct T1 cutoffs (10, 28, 30) from two annotators, not "three annotators, one number each"; picking 28 as "the" aggressive bracket ignores the documented 30.
2. **Edge-on is not a single per-annotator number either.** GT3 (cell 73) sets `Theta_1` (lefty) `label_th=7` and `Theta_2` (righty) `label_th=5` — two different thresholds for two orientation sub-masks of the same class, not one. GT1 gives 4 (cell 26); GT2's edge-on construction (cells 36–42) has **no** area-based cleanup step at all (only threshold+combine). So "P/H edge-on = 4" folds {4, 5, 7, "no cleanup"} down to a single number by an unstated rule, not a literal per-annotator median as described.
3. **Not every annotator cleaned every class.** GT1 has no T1 area-cleanup step; GT2 has no edge-on or face-on area-cleanup step (face-on is done via watershed + 8 manual pixel edits, cell 62/67, no `label`+threshold pass). "The median of the three annotators' cuts per class" presumes three comparable numbers per class; for two of three classes at least one annotator contributes no number at all, so "median" silently substitutes 0/absent for that annotator.
4. **A genuine off-by-one bug in the notebook's own cleanup loops** (found by "checking hard" per the brief): cells 49, 53, and 78 all loop `for i in np.arange(1, np.max(labs)):` — this excludes `i == np.max(labs)`, so **the single highest-labelled component in each pass is never checked against the threshold and can never be removed, however small it is.** (Cells 26/27, which use `skimage.measure.regionprops`, do **not** have this bug — they iterate `range(len(props))`, i.e. every region.) This means GT2's T1 and GT3's entire cleanup pass (face-on 782, T1 28/28, edge-on 7/5) each have one arbitrary immune micro-object per pass in the actual historical ground-truth construction. `direction_check.py`'s `cleanup()` does **not** reproduce this bug — it filters every component uniformly via `np.bincount`. So "P"/"H" as coded are the *intended* thresholds, not a byte-exact replay of how `ground_truth.hspy` was actually built; this cannot be checked further without the unreleased `ground_truth_{1,2,3}.hspy` intermediates.

Net: the four numbers in `RULES["P"]`/`RULES["H"]` are literal, correctly-cited notebook constants with correctly-attributed connectivities. The narrative wrapped around them ("median of three annotators' cuts, aggressive bracket") is an oversimplification of a messier, inconsistent, occasionally-buggy, per-orientation multi-threshold process — verdict **PARTLY REFUTED**: the numbers survive, the "median of three" story does not survive scrutiny unmodified.

## C4 — full-res maps converge to truth under P — **NOT REFUTED (numbers), but see interpretation below**

```
truth        : {edge-on 38, face-on 3, T1 41}
truth · P    : {edge-on 37, face-on 3, T1 40}
ANN · P      : {edge-on 36, face-on 3, T1 39}
NMF · P      : {edge-on 34, face-on 3, T1 41}
TMP · P      : {edge-on 36, face-on 3, T1 40}
vectors · P  : {edge-on 36, face-on 3, T1 42}
```
Face-on = 3 for all four (exact). T1 range 39–42 vs truth 41 (raw). Edge-on range 34–36 vs truth 38 (raw) — all reproduce the claim's numbers exactly. Note the comparison baseline used throughout is the **raw, uncleaned** truth (38/3/41), not `truth · P` (37/3/40) — truth is not itself perfectly stable under its own derived rule (see interpretation section).

`cleanup(cleanup(x,P),P) == cleanup(x,P)` verified idempotent (True) — no double-counting artifact in the implementation.

**P strips the overwhelming majority of each map's own components**, leaving exactly the truth-scale count:

| map | class | raw objects | removed by P | remaining |
|---|---|---|---|---|
| ANN | face-on | 60 | 57 | 3 |
| NMF | face-on | 519 | 516 | 3 |
| TMP | face-on | 153 | 150 | 3 |
| vectors | face-on | 248 | 245 | 3 |

(full table for all classes in `verify_out.log`). This 95%+ removal rate is exactly the mechanism stress-tested below.

## C5 — stride-3 alone changes truth's edge-on count — **NOT REFUTED**

```
truth full   : edge-on 38, median principal-axis length ≈ 34.7 px (own PCA-extent re-implementation; claim states 36)
truth stride3: edge-on 74, median length = 1.0 px
face-on: 3 -> 3 (unchanged)
T1: 41 -> 37
```
All object-count and face-on/T1 transitions match exactly. My own principal-axis-length reimplementation (PCA on pixel coordinates, not the app's own `length_px`) gives median 34.7 px at full res, not exactly 36 — close enough, and the direction of the claim (needles shatter to ~1 px) is confirmed: 51% of stride-3 edge-on "objects" are literal single pixels.

## C6 — app's stride-3 baseline and P/9 — **NOT REFUTED numerically, REFUTED in the strong form of the interpretation**

Reproduced the app's own dumped stride-3 labels independently:
```
app baseline        : edge-on 101, face-on 70, T1 62      (exact match to claim)
P/9 thresholds       : edge-on ceil(4/9)=1, face-on ceil(782/9)=87, T1 ceil(10/9)=2  (exact match)
app baseline + P/9   : edge-on 101, face-on 3, T1 37       (exact match to claim: 101/3/37)
```
So the headline numbers are correct. But the claim compares **cleaned app** (37) against **uncleaned truth** (37, the raw stride-3 truth count). Applying the identical grid rule to the truth itself, for a fair like-for-like comparison:
```
truth@3 raw   : edge-on 74, face-on 3, T1 37
truth@3 + P/9 : edge-on 74, face-on 3, T1 34   <-- truth's OWN T1 count drops under its OWN cleanup convention
```
Three real stride-3 T1 objects in the truth itself (each a literal single surviving pixel after stride-3 subsampling of larger real T1 particles) are below the `P/9` T1 threshold (2 px) or fail some other subset condition and get removed. Cleaned-vs-cleaned, the app's T1 gap is **37 vs 34 (+3)**, not 37 vs 37 (0) as the raw comparison implies. The cleanup narrows the T1 gap from 25 (62 raw vs 37 truth-raw) down to 3 (37 vs 34, fair comparison) — a large real improvement, but not the exact closure the one-sided framing states.

For face-on the fair comparison holds exactly: truth@3 (3) and truth@3+P/9 (3) are identical, and app+P/9 (3) matches both — face-on's part of the conclusion is solid.

For edge-on: `ceil(4/9) = 1` is a no-op threshold (every component has area ≥ 1), confirmed by the app baseline count being bit-identical before/after P/9 (101 -> 101). This mechanically confirms "edge-on is not measurable at stride 3" — the rule literally cannot remove anything at this stride, so any apparent edge-on "agreement" or "disagreement" downstream of this cleanup step carries zero information.

## Null-map stress test of the C4/C6 interpretation — the central ask

Ran four families of synthetic maps through the identical P-cleanup pipeline (`null_maps.py`, full output in `null_out.log`).

**(a) Truth + random Al→{face-on,T1} pixel flips at the app's own false-call rate** (0.43% Al→face-on, 0.59% Al→T1, measured from the app's stride-3 baseline vs. truth):
```
raw:       edge-on 38, face-on ~800, T1 ~1080   (err ≈ 0.75%)
P-cleaned: edge-on 37, face-on 3,    T1 40        <-- indistinguishable from truth·P
```
**(d) 5% uniform random label noise over the WHOLE 512×512 image** (every class, everywhere, iid, no relation to real structure):
```
raw:       edge-on ~3100, face-on ~3000, T1 ~2300  (err ≈ 3.75%)
P-cleaned: edge-on 38-41, face-on 3, T1 40          <-- also indistinguishable from truth·P
```
**Conclusion: the P-cleaned object-count metric is essentially blind to arbitrarily large amounts of spatially unstructured misclassification, provided the true objects are still present in the underlying map.** Both nulls recover face-on=3 and T1≈40 and edge-on≈37-41 purely because P's area thresholds (782 px, 10 px, and 4 px with 8-connectivity) are far larger than the typical connected-component size random iid mislabelling produces in a 512² image, so almost none of the injected noise survives the filter — cleanup mostly just re-discovers truth's own already-present real objects, which were never touched by the injected pixel flips. **This directly falsifies the stronger claim that C4/C6's near-truth cleaned counts by themselves demonstrate real classifier/pipeline quality** — a classifier producing the correct pixel classification less than 97% of the time at random would show the identical "near truth" cleaned counts.

**(b) Boundary erosion/dilation (structured, not iid)** — a more realistic error mode (per-position error 5.7–6.2%):
```
trial 0: raw edge 34, T1 54  -> P-cleaned edge 34, T1 41   (close to truth)
trial 1: raw edge 76, T1 31  -> P-cleaned edge 16, T1 31   (edge-on far off: 16 vs truth 37)
trial 2: raw edge 34, T1 54  -> P-cleaned edge 34, T1 41
```
Unlike iid noise, spatially-correlated boundary noise **does** sometimes survive cleanup and produce a badly wrong cleaned count — erosion of the already-thin edge-on needles shattered them below the area-4 threshold in trial 1, crashing the cleaned edge-on count to 16. So the metric **can** detect boundary-scale structural distortion, particularly for the already-marginal edge-on class, but **cannot** detect scattered/unstructured misclassification of any magnitude.

**(c) Deleting one real 678-pixel T1 object**: per-position error only 0.26% (a whole object vanishing barely moves the headline pixel-accuracy number), but the P-cleaned T1 count correctly drops 40→39 — object counting **can** catch this where pixel-percentage cannot.
**(c) Bridging (merging) two real, well-separated T1 objects (23.6 px apart) into one via a thin 1-pixel path**: per-position error 0.00%, raw T1 count correctly drops 41→40, but the **P-cleaned count stays at 40 in both the merged and unmerged case** — the merge event is completely invisible to the cleaned object count (a coincidental cancellation: one previously-sub-threshold component's removal offsets the merge). This is a genuine "cannot detect" case: a real topological error (two objects becoming one) that the cleaned metric reports as zero change.

### What the cleaned object-count metric can and cannot detect
- **Cannot detect:** iid/scattered misclassification of any rate up to at least 5% of all pixels, as long as it doesn't coincidentally form components ≥ the class threshold (782/10/4 px) — this includes realistic classifier confusion rates on Al pixels.
- **Cannot reliably detect:** merges of two real objects into one (can cancel against unrelated below-threshold removals).
- **Can detect:** deletion of a real, large object (count drops by exactly one).
- **Can sometimes detect, sometimes miss:** spatially-correlated boundary noise — very sensitive for the already-thin edge-on class (shatters below area-4), much less sensitive for face-on/T1 whose thresholds (782/10) are far above typical boundary-erosion pixel counts.

### Other checks requested
- **Does P remove any TRUE objects from the published maps (vanished count rising)?** Yes, by construction/design — that's the point of the rule (57/60, 516/519, 150/153, 245/248 face-on components removed from ANN/NMF/TMP/vectors respectively). This is expected and not itself evidence of a defect; it's the same mechanism the null tests exploit.
- **Does P/9 at stride 3 treat true T1 singletons in the truth as noise?** Yes — quantified above: 3 of the truth's own 37 stride-3 T1 objects are removed by `P/9` (37 → 34). This is the single most important number for grading C6's interpretation: the "convergence" claimed for T1 uses an internally inconsistent (cleaned vs. uncleaned) reference.

## Other issues found

1. **C3's numeric derivation is more fragile than presented** (see above) — multiple sub-thresholds per class per annotator, one annotator's most aggressive T1 cut (30) is unused in favor of a less aggressive one (28) mislabelled as "the aggressive bracket," and two of three annotators skip area-cleanup entirely for at least one class each.
2. **An off-by-one bug in the notebook itself** (`np.arange(1, np.max(labs))`, cells 49/53/78) leaves one arbitrary micro-component immune per cleanup pass in the historical ground-truth construction; `direction_check.py`'s `cleanup()` does not reproduce this, so "P"/"H" are idealized versions of the historical rule, not byte-exact replays. Cannot be resolved further without the unreleased per-annotator `ground_truth_{1,2,3}.hspy` files.
3. **The headline "count converges to truth" framing (C4/C6) is necessary but not sufficient evidence of classifier quality**: object count alone does not verify that a map's surviving large components sit at the correct locations relative to truth (that requires the split/merge/vanished/spurious location-overlap check already present in `direction_check.py`'s `smv()`, which is a stronger and more defensible statistic than count alone — the count-only framing in the claims as given should not be read as validating classifier accuracy by itself).

## Verdict summary

| Claim | Verdict |
|---|---|
| C1 | NOT REFUTED |
| C2 | NOT REFUTED |
| C3 | PARTLY REFUTED (numbers correct, "median of 3 annotators" narrative oversimplified/inconsistent; found a notebook off-by-one bug not replicated in the tool) |
| C4 | NOT REFUTED (numbers exact); interpretation needs the null-map caveat below |
| C5 | NOT REFUTED |
| C6 | NOT REFUTED (numbers exact); **the specific interpretive claim "the face-on and T1 object gap... closes... is the truth's cleanup convention, not the classifier" is REFUTED in its strong form** for T1 (fair cleaned-vs-cleaned comparison leaves a +3 gap, not 0) and is **directly falsifiable in general** by the null-map tests: random noise achieves the same "near truth" cleaned counts, so the convergence alone cannot be attributed to classifier quality one way or the other — it is at least as much a property of the area thresholds relative to real-object sizes as of the classifier. The face-on part of the claim (gap fully closes, cleaned-vs-cleaned) does hold. The edge-on "not measurable" part is confirmed and explained mechanically (P/9 edge-on threshold floors to 1, a no-op).

## Appendix — `refute_null_maps.py` output (seed 20260923)

```
Reference: truth raw = {1: 38, 2: 3, 3: 41} ; truth+P = {1: 37, 2: 3, 3: 40}

==============================================================================
(a) truth with random Al pixels flipped to face-on/T1 at the app's false-call rate
  app's Al->face-on rate = 0.00433, Al->T1 rate = 0.00586 (from stride-3 baseline vs truth)
  random Al->{2,3} flips trial 0         err=  0.76%  raw={1: 38, 2: 815, 3: 1114} P-cleaned={1: 37, 2: 3, 3: 40}  
  random Al->{2,3} flips trial 1         err=  0.73%  raw={1: 38, 2: 785, 3: 1061} P-cleaned={1: 37, 2: 3, 3: 40}  
  random Al->{2,3} flips trial 2         err=  0.74%  raw={1: 38, 2: 788, 3: 1089} P-cleaned={1: 37, 2: 3, 3: 40}  

==============================================================================
(b) truth with random erosion/dilation of precipitate boundaries (structuring elt radius 1, 50% each)
  erode/dilate trial 0                   err=  6.12%  raw={1: 34, 2: 3, 3: 54}   P-cleaned={1: 34, 2: 3, 3: 41}  
  erode/dilate trial 1                   err=  5.72%  raw={1: 76, 2: 3, 3: 31}   P-cleaned={1: 16, 2: 3, 3: 31}  
  erode/dilate trial 2                   err=  6.22%  raw={1: 34, 2: 3, 3: 54}   P-cleaned={1: 34, 2: 3, 3: 41}  

==============================================================================
(c) truth with one real T1 object deleted, and two T1 objects merged
  T1 object #14 (size 678) deleted       err=  0.26%  raw={1: 38, 2: 3, 3: 40}   P-cleaned={1: 37, 2: 3, 3: 39}  
  T1 objects #34 & #35 bridged (dist=23.6 px) err=  0.00%  raw={1: 38, 2: 3, 3: 40}   P-cleaned={1: 37, 2: 3, 3: 40}  

==============================================================================
(d) 5%% random label noise (uniform over {0,1,2,3}) over the whole 512x512 truth
  5% noise trial 0                       err=  3.75%  raw={1: 3172, 2: 3001, 3: 2330} P-cleaned={1: 39, 2: 3, 3: 40}  
  5% noise trial 1                       err=  3.76%  raw={1: 3082, 2: 2948, 3: 2371} P-cleaned={1: 41, 2: 3, 3: 40}  
  5% noise trial 2                       err=  3.74%  raw={1: 3113, 2: 3010, 3: 2305} P-cleaned={1: 38, 2: 3, 3: 40}  

==============================================================================
Cross-check: apply the SAME grid rule (P/9) to truth@3 itself vs to a null map at stride 3
  truth@3 raw    = {1: 74, 2: 3, 3: 37}
  truth@3 + P/9  = {1: 74, 2: 3, 3: 34}
  null3 (Al flips) raw   = {1: 74, 2: 93, 3: 145}  err=0.71%
  null3 (Al flips) + P/9 = {1: 74, 2: 3, 3: 34}
```

## What changed in T2–T4 because of this

- **T2 § cleanup convention:** "no cut" is now stated as "keep ≥ 1", and the median argument's
  assumption (masks agree apart from the cuts) is stated. H's T1 value is 28 (annotator 3).
  Annotator 2's other T1 orientation used 30, which is noted.
- **T2 headline and T3:** a cleaned object count no longer counts as evidence of classifier
  quality. Random Al flips at the app's own false-call rate clean up to exactly the truth's
  counts, and so does 5 % label noise. The fair T1 comparison at stride 3 (truth also cleaned) is
  37 vs 34, not 37 vs 37.
- **T4:** raw spurious objects and location overlap are the primary classifier metrics; cleaned
  counts are secondary. A null-map test is required: the bar must fail truth + random flips at
  the classifier's own rate.
