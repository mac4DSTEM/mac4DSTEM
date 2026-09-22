# Precipitate classification, overnight measurement — 2026-09-23

Track `sci` (YELLOW, overnight autonomy rules: measure/diagnose/propose, never move a
shipped number). Continues `docs/archive/v3/theta-prime-slab-2026-09-21.md`'s per-phase-slab
known-variants baseline (529 mislabelled = 1.81 %, Al → precipitate 407, T1 → θ′ edge-on 53)
and `docs/archive/v3/phase-map-objects-gateD-2026-09-21.md`'s unwired class-map → objects
bridge. Every command below runs through `tools/thronsen-dataset/run.sh probe` (which itself
calls `tools/phase-map-probe/run.sh References/thronsen-datasetA/datasetA_stride3.h5 2 0.01904
--thronsen References/thronsen-datasetA/truth_stride3.json --reach 0.68 "$@"`); flags below are
the `"$@"` this session added. All logs are in the session scratchpad, named here, not
committed (per `docs/status.md`'s own log-naming rule).

**Neither Gate D trigger applies to this session's code.** Nothing under `mac4DSTEM/Core/`
changed — every edit is in `tools/phase-map-probe/{main.swift,run.sh}`, all four additions are
off by default (`--cif-check`, `--cif-crystals`, `--al-precipitate-detail`, `--object-table`),
and no shipped default, threshold, or verdict moved. `core` was not re-run because no `Core/`
file changed; `tools/run-tests.sh inventory` exits 0 on the tree this record commits with
(`inventory-precip-overnight-20260923.log`).

## Step 0 — reference integrity

**Question.** `thronsen.swift`'s header says its three crystals are "built directly rather
than through `CIFImport`, which admits only cubic and hexagonal cells (θ′ is tetragonal)".
New flag `--cif-check <Al.cif> <thetaPrime.cif> <T1.cif>` loads
`References/crystal-structures/{Al,thetaprime,T1}_thronsen2024.cif` through the app's real
`CIFImport.crystalModel(from:fileBaseName:)` and diffs the result against the hand-typed
crystals at both levels asked for. Log: `cif-check-20260923.log`.

**Finding 1 — the header comment is stale.** `CIFImport.classifyFamily` only *proposes* cubic
or hexagonal from the cell metric; anything else (θ′'s I-4m2, tetragonal) falls through to
`.identity` (added 2026-09-11, per its own comment) rather than being refused —
`CIFImportError.unsupportedPointGroup` is declared but never thrown anywhere in the current
file. `.identity` means no ACOM point-group reduction (no IPF key), not "rejected": atom-site
expansion still runs off the CIF's own listed symmetry operators. All three CIFs imported
successfully: Al `symmetry=cubic, spaceGroupNumber=225`, θ′ `symmetry=identity,
spaceGroupNumber=119`, T1 `symmetry=hexagonal, spaceGroupNumber=191`.

**Finding 2 — atom sites match exactly.** Hand-typed vs. CIF-imported, nearest-neighbour
matched under periodic wrap: Al 4/4, θ′ 6/6, T1 22/22, in every case 0 unmatched either side
and worst matched separation `0.0` (fractional).

**Finding 3 — kinematic reference vectors match exactly for θ′ and T1.** Same zone axes the
probe uses (θ′ edge-on [100], θ′ face-on [001], T1 [0 −4 1]), same settings
(`kMax = 0.70 Å⁻¹`, `inPlaneStepDeg = 2`, θ′'s slab override 0.3): θ′ edge-on 14/14 vectors
matched, θ′ face-on 8/8, T1 18/18 — every case worst `|q|` separation `0.00000 Å⁻¹` and worst
relative-intensity difference `0.0000`.

**Finding 4 — Al differs, by a real, small amount.** The app's hand-typed `Crystal.aluminum`
(`fcc(a: 4.0495, z: 13)`) and the paper's own CIF (`a = 4.04000`) differ by ≈0.24 %. Atom
*positions* still match exactly (FCC fractional coordinates don't depend on `a`), but the
[001] matrix entry's reflection *count* differs at the shipped excitation-slab settings: 8
(hand-typed) vs. 4 (CIF) vectors, with matched vectors' worst `|q|` separation `0.00116 Å⁻¹`.
This is a `DEVIATION`-worthy discrepancy nobody had measured before.

**Baseline reproduced first**, exactly, before anything else ran
(`baseline-repro-20260923.log`): `known-variants`, `--or --min-relative 0.001 --min-intensity 0`
→ **529 / 29241 = 1.81 %**, Al → precipitate 407 (188 θ′ edge + 93 θ′ face + 126 T1), T1 → θ′
edge-on 53, T1 → T1 6258, θ′ edge → θ′ edge 398/417, θ′ face → θ′ face 969/970 — all matching
`theta-prime-slab-2026-09-21.md` digit for digit.

**Additional probe (per the brief, never replacing the default):** new flag
`--cif-crystals <Al.cif> <thetaPrime.cif> <T1.cif>` substitutes CIF-imported crystals for the
three hand-typed ones inside the SAME `--thronsen` phase list (every other field —
role/zoneAxes/orientationRelationships/slab override — untouched), leaving the shipped default
phase list completely alone unless the flag is passed. Re-running the baseline with it
(`cif-crystals-repro-20260923.log`): **534 / 29241 = 1.83 %** — Al → precipitate rises to 412
(189+92+131), everything else (T1 → θ′ edge-on 53, T1 → T1 6258, edge → edge 398/417, face →
face 969/970) **unchanged to the last digit**. The +0.02-point shift is attributable entirely
to the Al lattice-constant difference found above, not to any error in the hand-typed θ′/T1
cells. **Verdict: the hand-typed crystals are faithful to the paper's own CIFs for θ′ and T1;
the residual under investigation below is not a reference-data artifact.**

## Step 1 — Gate D on the 407 Al → precipitate false calls

**Diagnosis (written before running `--al-precipitate-detail`, from reading
`PhaseVectorMatching.swift`, not from data).** `classifyKnownVariants` is a faithful,
`DEVIATION`-documented port of the paper's own cell 16/19: unlike `.search`, it has **no**
`chanceMatchMultiple` guard, **no** `minimumMatchedVectors` floor, and **no**
`challengeByMatrix` re-offering of the matrix — all three exist in `.search` and are named,
one by one, in `classifyKnownVariants`'s own doc comment as *absent by design*. Once a
truth-Al position keeps more than `directMatrixMaximumVectors` (shipped 1) survivors after
matrix removal, EVERY surviving vector is matched to its true nearest reference in EVERY
non-matrix library entry, however far, argmin over the whole set, cut off only by the flat
`residualCutoffInvAngstrom` (0.07 Å⁻¹).

**Refuting observation, pre-registered.** If the false-call population's matched-reflection
counts and scores are statistically indistinguishable from genuine precipitate detections',
a simple count/margin guard cannot separate them and the mechanism is something else (a
spatial/physical artifact, not chance-level noise).

**Predicted outcome.** False Al → precipitate calls will show fewer matched/phase-specific
reflections and scores closer to the 0.07 cutoff than genuine precipitate calls.

**Measured** (new flag `--al-precipitate-detail`, log `al-precip-detail-20260923.log`; "Al
score" = the same unique-hit mean-distance formula scored against the fitted matrix entry —
diagnostic only, Al is never scored this way in production; "specific" = matched reflections
of the winning entry whose `q` sits nowhere near an Al reflection, "shared" = the opposite):

| group | n | best score (Å⁻¹) p50 | Al score p50 | margin p50 | specific p50 (p25) | shared p50 |
|---|---|---|---|---|---|---|
| Al → precipitate (FALSE, group A) | 407 | 0.0328 | 0.3323 | 0.0198 | 1 (0) | 0 |
| Al → Al (correct, group B, only 1466/21087 ever had a survivor) | 1466 | 0.0060 | 0.2814 | n/a | 0 | 0 |
| precipitate → same subclass (correct, group C) | 7625 | 0.0102 | 0.3727 | 0.0581 | 7 | 0 |

**Prediction partially confirmed.** Group A's scores and specific-reflection counts are
markedly worse than group C's (median score 3× higher, median specific count 7× lower) — the
"no chance guard" mechanism is real and measurable — but the two distributions overlap (group
A's `p75` specific count is 2, group C's `p25` is 3), so no single cut is clean. The
"shared-with-Al" column contributes almost nothing (median 0 everywhere): the false calls are
not, in the main, artifacts of Al's own reflections coincidentally overlapping a candidate's —
they are calls built on too few, too-far reflections with nothing to check them.

**Guard sweep** (a position failing the guard falls back to `matrix`, not `notIndexed` — Al is
what "not enough evidence" should mean for a rule with no `challengeByMatrix` step; only groups
A and C can move the headline, since a cross-subclass wrong call, e.g. T1 → θ′ edge-on, stays
wrong under either label):

| guard | fixes / 407 (A) | costs / 7625 (C) | new headline |
|---|---|---|---|
| specific ≥ 0 (no-op) | 0 | 0 | 529/29241 = 1.81 % |
| **specific ≥ 1** | **112** | **6** | **423/29241 = 1.45 %** |
| specific ≥ 2 | 257 | 166 | 438/29241 = 1.50 % |
| specific ≥ 3 | 356 | 1311 | 1484/29241 = 5.08 % |
| margin ≥ 0.002 | 28 | 11 | 512/29241 = 1.75 % |
| margin ≥ 0.005 | 65 | 20 | 484/29241 = 1.66 % |
| margin ≥ 0.010 | 115 | 40 | 454/29241 = 1.55 % |
| margin ≥ 0.020 | 205 | 194 | 518/29241 = 1.77 % |

The sweep is non-monotonic (specific ≥ 2 is *worse* than ≥ 1 despite fixing more false calls,
because it costs disproportionately more true ones) and the best single point measured is
**`specific ≥ 1`: 1.45 %** — inside the paper's own 0.96–1.75 % band, at a cost of 6 of 7625
correct precipitate calls. A margin-based guard tops out at 1.55 % (`margin ≥ 0.01`), less
effective at its best point than the specific-count guard.

**Proposal, stated honestly.** `specific ≥ 1` is the best point *measured on this one
dataset*. Per the repo's own threshold rule, this is not offered as a property of the method —
it has not been measured on the demo cube or any other dataset, and both `directMatrixMaximumVectors`
and `residualCutoffInvAngstrom` interact with it in ways not swept here. It is a candidate for
the owner to weigh, not a default change, and none was made: `classifyKnownVariants` in
`Core/` is untouched.

## Step 2 — the 53 T1 → θ′ edge-on confusions

Log: `step2-detail-20260923.log` (added one named `--residual-detail` cell, "T1 (truth) →
theta-edge-on (ours)", to read the population directly instead of re-deriving it from the
rotation-angle table alone).

**Which reflections decide them.** `matchedCount` (reflections within the normal 0.02 Å⁻¹ pair
radius of the winning θ′ edge-on entry) is **0 for 39 of 53** — the large majority of these
calls have *no* reflection genuinely close to the winner; `survivingCount` is mostly 6–9 (30)
or 10+ (12), i.e. plenty of leftover T1 signal survived matrix removal. Winning scores cluster
near the cutoff: `p10 0.0399, p50 0.0519, p90 0.0601` against a 0.07 Å⁻¹ ceiling — the identical
"no floor, no guard" mechanism as Step 1, this time θ′ edge-on's dense 46-vector entry (vs. the
shipped global slab; see `theta-prime-slab-2026-09-21.md`) edges out T1's own (worse-than-usual)
score by argmin alone.

**Spatial clustering vs. truth boundaries.** Checked directly against `truth_stride3.json`
(a one-off Python read, not a probe change): **52 of the 53 positions sit within 2 scan pixels
of a DIFFERENT truth label** (only 1 sits purely inside bulk T1). Neighbouring labels, counted
per position (multiple per position possible): θ′ face-on 34, Al 30, θ′ edge-on itself 10,
"disagreement" 8. Two dense connected clusters account for ~30 of the 53 (rows 15–24 / cols
10–14, and rows 42–46 / cols 115–131 — both look like elongated precipitate edges or tips in
scan space); the rest are scattered singles/pairs. **Conclusion: these are overwhelmingly
boundary positions**, not scattered statistical noise through bulk T1 — physically ambiguous
mixed-signal patterns at a real phase edge, which the missing chance-guard turns into a
confident wrong label instead of `notIndexed` or a correct T1 call.

## Step 3 — object-level truth check

New flag `--object-table` (needs `PrecipitateSegmentation`/`PrecipitateStatistics`/
`PhaseMapObjectsBridge`, none of which had a `sources.manifest` group; `core` — every `Core/`
source, a strict superset — added to `tools/phase-map-probe/run.sh`'s sourcing instead of a
new group, at the cost of a slower build (~75 s vs. ~55 s), not a wrong one).
Log: `step3-object-table-20260923.log`. Runs `PrecipitateSegmentation.classObjects` (8-connected,
the same call `PhaseMapObjectsBridge.labeledMap` feeds it) on (a) truth labels, (b) the
baseline predicted labels, (c) the step-1 `specific ≥ 1` guarded labels (recomputed inline,
not stored). "Areal density" is reported as area fraction (pixelCount / analysed pixels) —
`pixelSize` is `nil` here (no physical calibration on this synthetic-truth cube), so
`PrecipitateStatistics` correctly refuses a physical density; this is the honest,
`validation:"none"` proxy, not a claimed measurement.

| phase | source | objects | median length (px) | area fraction | split | merge | vanished |
|---|---|---|---|---|---|---|---|
| θ′ edge-on | truth | 74 | 1.00 | 0.0143 | – | – | – |
| θ′ edge-on | baseline | 101 | 1.00 | 0.0219 | 6 | 18 | 0 |
| θ′ edge-on | guarded | 85 | 2.00 | 0.0181 | 8 | 15 | 0 |
| θ′ face-on | truth | 3 | 22.23 | 0.0332 | – | – | – |
| θ′ face-on | baseline | 70 | 1.00 | 0.0372 | 0 | 0 | 0 |
| θ′ face-on | guarded | 54 | 1.00 | 0.0365 | 0 | 0 | 0 |
| T1 | truth | 37 | 23.14 | 0.2174 | – | – | – |
| T1 | baseline | 62 | 8.61 | 0.2183 | 2 | 1 | 0 |
| T1 | guarded | 48 | 13.37 | 0.2175 | 2 | 1 | 0 |

Analysed pixels: truth 29241, baseline 29239, guarded 29239 (of 29241 total; the app's own
`notIndexed`-exclusion rule, `phase-map-objects-gateD-2026-09-21.md`, accounts for the 2).

**Reading.** θ′ face-on is the clearest story: truth is 3 large blobs (median 22 px), but
baseline predicts 70 mostly single-pixel objects at a slightly HIGHER area fraction (0.0372 vs.
0.0332) — consistent with Step 1's 93 Al → θ′ face-on false calls landing as scattered,
disconnected singleton pixels far from the true blobs (0 split, 0 merge — nothing they touch).
T1 is the clearest case the guard helps: baseline shatters the true 37 objects into 62,
dragging the median length down to 8.61 px; the guard recovers most of it (48 objects, median
13.37 px) while barely moving the area fraction (0.2183 → 0.2175, both close to truth's
0.2174) — fewer, longer, more truth-like objects from the same total area. θ′ edge-on's high
merge counts (15–18 of ~74–85 predicted objects touch 2+ truth objects) says predicted
edge-on regions are more spatially contiguous than the truth speckle pattern, in both baseline
and guarded runs; `vanished = 0` everywhere means no truth object was ever missed entirely at
either setting.

## Owner questions

1. Is `classifyKnownVariants`'s missing chance-guard/matrix-challenge (both present in
   `.search`, both absent here by DEVIATION-documented design) something to close the gap on,
   or is faithfulness to the paper's own published rule the point, with the residual reported
   rather than fixed?
2. If a guard is wanted, `specific ≥ 1` (matched, phase-specific, non-Al-shared reflections) is
   the best single point measured **on this one dataset** — does the owner want it measured on
   a second dataset (the demo cube, or a live-fetched Materials Project structure) before it is
   even considered as an off-by-default candidate flag in `PhaseVectorSettings`?
3. Al's hand-typed lattice constant (4.0495 Å) vs. the paper's own CIF (4.04000 Å) is a small,
   real, previously-unmeasured discrepancy (Finding 4). Worth a `DEVIATION` note and/or
   reconciling, independent of everything else in this record?
4. Step 3's object-level view (median length recovers 8.61 → 13.37 px on T1 under the guard,
   closer to truth's 23.14) is a second, independent line of evidence pointing the same
   direction as Step 1's confusion-matrix headline — does that shift the owner's read of
   question 1/2 at all?

## What changed

`tools/phase-map-probe/main.swift` (four new off-by-default flags: `--cif-check`,
`--cif-crystals`, `--al-precipitate-detail`, `--object-table`; one new named cell in the
existing `--residual-detail` table) and `tools/phase-map-probe/run.sh` (sources `crystal` and
`core` groups, plus `Session/PhaseMapObjectsBridge.swift` directly). Nothing under
`mac4DSTEM/Core/` changed. No shipped default moved.

## Independent refutation — 2026-09-23 01:00 CEST

Refuter: a separate agent that did not write a6d82d0, briefed to break the claim. No tracked file
other than this section was edited. Logs (session scratchpad, not committed):
`refute-repro-20260923.log` (the committed probe, `tools/thronsen-dataset/run.sh probe --rule
known-variants --or --min-relative 0.001 --min-intensity 0 --al-precipitate-detail
--object-table`, exit 0); `refute-dump-20260923.{log,csv}` (a scratch copy of the probe that adds
one per-position CSV dump inside the `--object-table` block — the same truth-free "specific"
formula as `main.swift:1571–1597`, additionally evaluated at pair radius 0.010/0.015/0.020/0.025/
0.030 Å⁻¹ and at 0.5×/1×/2× the Al-shared tolerance; its own confusion matrix and headline are
529 = 1.81 %, identical); `refute-analysis-20260923.log` and `refute-analysis2-20260923.log`
(Python over that CSV: full recount, splits, bootstrap, boundary and object provenance).

| # | claim | verdict |
|---|---|---|
| 1 | baseline 529 = 1.81 %, guard 423 = 1.45 % | **NOT REFUTED** — reproduced to the digit (confusion matrix, sweeps A/B, object table all identical to the author's logs); a full recount on guarded labels (not the `529 − fixed + broken` shortcut) also gives 423, and 438 for `≥ 2` |
| 2 | "specific" is leak-free | **NOT REFUTED**, one qualification — truth never enters it: it is computed from the survivors and the entry the position was *called* as (`result.entryIndex`), which a production guard would have. But the guard is one-directional by construction (precipitate → Al only, never the reverse), so it can only trade toward the 73.5 % majority class |
| 3 | `specific ≥ 1` is not an overfit | **PARTIALLY REFUTED** — held-out it generalises; as a "parameter-free" rule it does not (below) |
| 4 | guard only removes Al → precipitate false calls | **PARTIALLY REFUTED** — the error arithmetic is right; the flip set is wider (below) |
| 5 | "inside the paper's band" is like-for-like | **PARTIALLY REFUTED** — same metric and denominator, different sampling (below) |
| 6 | Al lattice constant; 1.81 → 1.83 % | **NOT REFUTED** as a conclusion; the stated mechanism is wrong (below) |
| 7 | step 3 truth and prediction extracted identically | code **NOT REFUTED**; the *reading* **REFUTED** (below) |

**3 — held out.** Choosing k ∈ 0…6 on one half and scoring the other, for six spatial splits in
both directions (left/right, top/bottom, checkerboard, even/odd rows, even/odd columns, diagonal):
k = 1 is chosen 9 times of 12, k = 2 three times, and the held-out half improves every time, by
0.21–0.42 points (e.g. left → right 1.62 → 1.29 %, right → left 1.99 → 1.60 %). 200 random 50/50
splits: k = 1 chosen 170 times, k = 2 30 times; held-out change median −0.35 points (5–95 %
−0.42 to −0.18). At the probe's radius the k curve is a two-point plateau (1.45 / 1.50 %) then a
cliff (5.08 % at 3), not a knife edge at 1. **But "≥ 1" is only defined relative to the pair
radius, which the author never varied**: k ≥ 1 gives 2.18 % at 0.010 Å⁻¹ (worse than no guard),
1.35 % at 0.015, 1.45 % at 0.020, 1.56 % at 0.025; k ≥ 2 gives 1.30 % at 0.025. With radius free
too, the held-out halves pick 0.025/k = 2 in 10 of 12 and score 1.08–1.63 %. The Al-shared
tolerance is flat (0.5×–2× changes ≤ 3 positions). So 1.45 % is neither the best point on this
dataset nor a property of the method: it is one point on a (k, radius) ridge, and the probe runs at
0.020 while the app's `scaledToDetector` would use one pixel, 0.01904. Within-dataset halves share
the microscope, sample and detection settings; none of this is cross-dataset evidence.

**4 — what flips.** The guard flips 158 positions: 112 truth-Al fixed (69 → θ′ edge,
22 → θ′ face, 21 → T1), 6 correct calls lost (4 T1, 2 θ′ edge-on), and **40 already-wrong
precipitate positions relabelled as Al** (39 of the 53 T1 → θ′ edge-on, 1 θ′ face → edge). Those
40 are error-neutral under the metric but move errors from "wrong precipitate" to "missed
precipitate": precipitate → Al errors go 39 → 85. All 6 lost calls sit 1–2 scan pixels from a
different truth label (boundary), each with 2–10 survivors, `matchedCount` 0, and 1–3 specific
reflections that appear only at radius ≥ 0.025 (two only at 0.030). Boundary check on the whole residual: **354 of the
407 Al → precipitate false calls are 8-adjacent to a non-Al truth pixel, against a 21.9 % base rate
for truth-Al** (287 adjacent to the very class they were called). Step 1's "chance-level,
too-little-evidence" reading describes the *isolated* minority better than the population; the
guard is selective for it — 60 of its 112 fixes touch the called class, versus 227 of the 295
it leaves.

**5 — the band.** Same code, same metric (`ours != theirs`, not-indexed and the 2 "disagreement"
positions counted wrong), same 29 241 denominator. Not like-for-like: the 0.96–1.75 % band is their
maps on the full 512 × 512, ours a stride-3 subgrid, and their maps were never scored on the same
subgrid. A spatial block bootstrap (9 × 9 blocks, 2000 draws) gives baseline 1.81 % [1.55, 2.08]
and guarded 1.44 % [1.23, 1.69] (95 %): P(baseline ≤ 1.75 %) = 0.34, P(guarded ≤ 1.75 %) = 0.995.
The guarded point is inside the band robustly; **the baseline was never distinguishably outside
it**, so "just outside the band" (theta-prime-slab, 2026-09-21) and "moves it inside" are both
statements within sampling noise at this stride.

**6 — Al.** 4.0495 Å is pure Al at room temperature; 4.04 Å is the paper's CIF, the same value as
θ′'s a (Cu and Li in solution contract Al slightly, but not settled here). The 8-vs-4 vector
difference is not an excitation-slab effect as Finding 4 says: it is the {220} ring straddling the
probe's `kMax` 0.70 Å⁻¹ — √8/a = 0.6985 Å⁻¹ at 4.0495, 0.7001 at 4.04 — a cutoff knife edge
(the 4 matched {200} vectors differ by the 0.00116 Å⁻¹ reported). Five positions; no
conclusion depends on it.

**7 — objects.** Truth and predictions go through the same `PrecipitateSegmentation.classObjects`
call (8-connected, `pixelSize` nil); only the not-indexed role differs ({} vs {−1}). Two small
errors: the comment says truth label 4 is excluded from the analysed area, but it is counted
(analysed 29 241 includes its 2 pixels); and label identity relies on the phase list's order
coinciding with Thronsen's 0–3 (it does). The *reading* does not hold: of the 62 baseline T1
objects, 39 overlap truth T1 and 23 overlap nothing (20 single pixels); guarded, 39 overlap truth
and 9 are spurious. The truth-overlapping population is unchanged (39, median area 94 → 93 px, split
2 → 2). **The median-length rise 8.61 → 13.37 px is spurious singletons removed from the median,
not shattered objects repaired** — "baseline shatters 37 into 62, the guard recovers most of it" is
refuted. Same for θ′ face-on: 67 of 70 baseline objects are spurious 1–2 px speckles.

**Owner decisions.** (a) If a guard is pursued, it is a two-parameter rule (count, pair radius);
pre-register one pair — k ≥ 1 at the app's own one-pixel radius is the natural choice — and
measure it on a second dataset before any flag. (b) Do not cite the T1 median-length gain as
independent support (owner question 4): it is the same singleton removal the confusion matrix
already counts. (c) Report the headline with its sampling interval, or score their published maps
on the stride-3 subgrid, before saying "inside/outside the band". (d) Correct Finding 4's mechanism
(`kMax` knife edge) if the Al `DEVIATION` note is written. Nothing here invalidates the 1.45 %
number itself; it invalidates calling it parameter-free and calling step 3 a second line of
evidence.
