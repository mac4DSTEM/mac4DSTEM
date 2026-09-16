> History, not guidance. Cut verbatim from `docs/open-items.md` on 2026-09-16 (docs consolidation).


## Step 3's 2026-09-16 increments — the record is archived, these are the live residuals

 What stays
live from that day:

- **Step 3 is at 4.21 %** (0.1 % detection threshold, shipped 70-peak cap)
  against the band 0.96–1.75 %. Al 98.11 %, θ′ edge-on 70 %, face-on 99.6 %,
  T1 89 %. No default moved — py4DSTEM's 0.5 % still ships.
- **The error is 83 % refusals** at that threshold: 1024 of 1230, of which T1
  617 and Al 354, and **98 % of them arrive because no candidate cleared the
  guards**, not by the verdict cliff (worth ~30 positions).
- **Closed as levers, do not re-open without new evidence:** the 70-peak cap
  (0.6 % of positions at it; cap 70 vs 200 differ by seven positions), the
  phase-contrast margin (it only converts a verdict to `.notIndexed`, which
  their metric counts as mislabelled, so it can only raise the number), and
  the detection threshold below 0.1 % (0.05 % gives 75.67 %).
- **`matrixFallbackExplainedFraction` ships at 0** by owner decision: at 0.33
  it reaches 3.13 %, but 600 of the 915 improved positions are T1 moving from
  "not indexed" to "Al" — wrong either way — so the score improves and the map
  does not. Turning it on overstates the matrix phase fraction by ~2 % of the
  map.
- **`medianMatrixExplainedFraction` is on screen and UNVERIFIED** — a "Matrix
  evidence" row under the Phases legend. Nobody has looked at it.

## Step 3 ran on a stride-3 subsample and is OUTSIDE their band — measured 2026-09-15

**Science, live; the pre-registered verdict, not softened.** Their 7.4 GB
`datasetA_preprocessed.hspy` was streamed from Zenodo by HTTP range requests
and every third scan row and column written as uint16
(`References/thronsen-datasetA/datasetA_stride3.h5`, 171 × 171, 0.51 GB;
`truth_stride3.json`), and `tools/phase-map-probe --thronsen` runs the
shipped matcher on it and scores by THEIR metric (their four published maps
reproduce at 0.96–1.75 % mislabelled with it). 

 The floor is the
precipitate fraction itself: Al positions are matrix 100 %, but T1 goes to
matrix at 94 % and θ′ face-on at 100 %, because along [001]Al each variant
leaves at most two reflections that are not Al's inside the 0.70 Å⁻¹ mask
(T1: the two-thirds-{220} spots; θ′ face-on: (110) at 0.35), under
`minimumMatchedVectors = 3` and the matrix's last word. θ′ edge-on, with
four (011)-type spots at 0.30 Å⁻¹ per variant, is the only precipitate the
matcher indexes (15–22 %). Their vector matching reached 1.54 % on the same
data by classifying the vectors left after Al removal with no such minimum.
**What Gate D found on the way, all measured:**
- At the shipped detection threshold (0.5 %) the app finds a median of 22
  peaks where an Al [001] pattern inside their 0.70 Å⁻¹ mask has four: their
  direct beam is a flat plateau of ties at the maximum, and the mask edge is
  a ring of maxima no phase explains. Nothing is called matrix: 98.3 %
  mislabelled. At 10 % everything is called matrix (99.7 %) and 26.4 % is
  mislabelled — exactly the precipitate fraction — because T1's reflections
  are 1–5 % of the plateau maximum. The app has no outer-reach setting; the
  probe's `--reach` stands in for the one a masked dataset needs.
- **The T1 reference is wrong in detail.** Along [001]Al the data's T1
  signature is spots at two thirds of {220}Al (0.465–0.477 Å⁻¹ at the {220}
  azimuths) plus intensity on the {200} spots; the [0 -4 1] projection of
  their c = 14.145 Å cell also predicts reflections at 0.233 and 0.367 Å⁻¹
  that the data does not show at all (median 0 % of the maximum at T1
  positions). At 0.5 % the matcher still indexed T1 at 94 % precision, at
  6 % recall.
**The rule, measured (2026-09-15, `--min-matched`), and a claim of mine
refuted on the way:** with the candidate floor at 2 and the shipped 0.5 %
threshold the Al class stays 100 % (28 errors of 21 494), T1 recall goes
6 % → **59 %**, θ′ edge-on 54 %: mislabelled **12.97 %** (at 1 %: 19.7 %).
I first wrote that the matrix challenge's free rotation was absorbing the T1
pairs; re-reading the code refuted it — the challenge must explain STRICTLY
more than the candidate and cannot take a two-of-two pair — and the survivor
histogram the probe now prints settles it: every T1 position still labelled
matrix has **zero** survivors after matrix removal (63.5 % at 1 %, 35 % at
0.5 %), so the pair fell below DETECTION, whose threshold is relative to a
saturated direct-beam plateau. Face-on θ′ is the same limit harder: 93 % of
its positions have no survivors at 0.5 %. **Landed, all three, each measured (`thronsen-*-b-20260915.log`):** the
Friedel-pair floor (`friedelPairMinimumMatchedVectors`: a candidate may
clear 2 when the survivors hold u and −u); the matcher's outer reach
(`maximumVectorInvAngstrom`, "Ignore peaks beyond" in Phase mapping; without
it every Al position is "not indexed" and 86 % is mislabelled); and a
relative-threshold reference that excludes the direct beam
(`relativeReferenceMinimumRadiusPx`, "Reference outside" in Advanced
detection, default 0). **With the first two at shipped defaults: 13.24 %
mislabelled, Al 100 % (28 of 21 494), T1 58 %, θ′ edge-on 45 %, face-on
1 %.** The third only rescales the threshold on this data: against the
brightest Bragg peak, 0.5 % floods the Al class with noise (32 % "not
indexed", 30.6 % total) and 2 % lands at 13.14 % — the same 59 % of T1 —
so the remaining loss is noise separation, not the reference; it lands as
a parameter that moves nothing until set. **Gate B (2026-09-15) on the
three:** the pair floor is a no-op where 5 × chance exceeds two (a
48-vector entry below ≈ 0.3 Å⁻¹ accessible radius) and the matrix
challenge cannot reach a two-of-two winner, so a second matrix grain whose
residual is exactly a candidate's pair would be labelled that candidate —
not seen on the dataset, not tested, recorded in the setting's note; the
detection reference is measured from the brightest maximum, not the array
centre, since the refuter showed descan defeats the centre. The T1 reference's extra predicted
reflections (0.233, 0.367) cost nothing and are not a lever. **Gate D on
"detection at the noise floor" (2026-09-15, pre-registered before the run).**
Diagnosis: the relative threshold is a fraction of a maximum, not a noise
statistic. Instrument: a per-pattern z = (I − median)/(1.4826·MAD) over the
non-beam, non-Al correlation maxima, pairs scored by the weaker member.
Prediction: ≥ 80 % of T1 positions keep a pair at the z where ≤ 0.1 % of Al
positions do; refuting observation: ≤ 60 %. **Refuted** — 57.6 % at z ≥ 5
(`tools/phase-map-probe --noise-floor`, `thronsen-noise-20260915.log`; face-on
θ′ alone separates by z, 81 % at 0.1 % Al). The same positions answered a
question I had not asked: a fraction of the beam at **0.2 %** keeps 80 % of
T1 pairs at 0.07 % Al, where the shipped 0.5 % keeps 59 %. Through the whole
pipeline (`thronsen-rel0.002/0.003-friedel-20260915.log`): **0.5 % → 13.24 %,
0.3 % → 12.22 %, 0.2 % → 8.75 %** (Al 99.6 %, T1 78 %). The default stays
py4DSTEM's 0.5 % (`decisions.md`); the number is the setting's. New at 0.2 %:
θ′ **face-on is labelled edge-on at 38 %** — the candidates' in-plane
rotation is free, so an edge-on variant rotated 45° puts its (002) at
0.345 Å⁻¹ on face-on's (110) at 0.350, inside the pair radius; the known
orientation relationship to the matrix is not enforced. **Gate D on the
orientation relationship (2026-09-15 evening, pre-registered before the
build).** Mechanism measured first: face-on positions labelled edge-on take
the edge-on entry at 45° to the matrix (84 % in the 45–60° bin,
`thronsen-rel0.002-angles-20260915.log`). Instrument:
`PhaseDefinition.inPlaneDegreesRelativeToMatrix` (nil = free) and a ±10°
filter on candidate entries once the matrix is fitted
(`PhaseVectorSettings.orientationRelationshipToleranceDeg`); the probe's
`--or` gives θ′ {0, 90, 180, 270} and T1 the measured clusters. Prediction:
face-on → edge-on below 5 %, face-on correct above 50 %, edge-on within
5 points, T1 within 2, total below 8.75 %. **Result: 8.75 → 7.89 %, face-on →
edge-on 38 → 0 %, face-on correct 13 → 47 %, T1 78 → 78 % — and the
refuting observation fired: edge-on correct 50 → 31 %** (not indexed
42 → 60 %), because half of the correct edge-on matches sit near 22° and
67° to the matrix (5° bins, control log), which a {0, 90} list cuts. So the
constraint is right for face-on and wrong-as-listed for edge-on; the
capability lands inert (nil everywhere, a test broken four ways), no panel
control until the 22°/67° edge-on matches are explained. **Gate B raised the
frame** — an entry's in-plane axes come from `ACOMOrientation.detectorBasis`,
which branches on the zone axis, so a listed angle is the library's, not a
lab angle — and that caveat is real and recorded on the field, but it is
**not the cause here**: computed from the code's own rule, edge-on [100] has
x̂ = c, ŷ = −b and Al [001] has x̂ = b, ŷ = −a, so (002)θ′ ∥ ⟨200⟩Al is an
exact multiple of 90° in the library's frame (the list was right). What
fits the clusters is a **partial self-coincidence of the θ′[100] net**: a
rotation of 70° or 110° maps 4 of its 16 non-Al-coincident vectors — the
(011)/(022) family at ±55° and ±125° — onto each other within the pair
radius, and 110° folds to 20°, 70° to 70°. **The survivor dump settled it
(`tools/phase-map-probe --dump-edge-on`, `thronsen-rel0.002-dump-20260915.log`,
110 off-OR positions):** at those positions the OR-consistent entry matches
6–11 of ~20 survivors (mean matched fraction 0.20) and the free winner
matches **2** (0.12) — a Friedel pair of the (011) family, admitted by the
morning's pair floor, at a mean distance of 0.003–0.009 Å⁻¹; the honest
6–11-vector fit sits at 0.010–0.016 Å⁻¹ and falls over
`notIndexedAboveInvAngstrom` (0.01, half a pixel here), which is why the
constraint sent them to "not indexed". The best entry per phase is chosen
by mean distance alone, so a sparse lucky pair beats a dense fit, and the
label is right for the wrong reason. The correct on-OR fits sit at
0.0099 — on the cliff. A many-vector fit under strain and sub-pixel jitter
has a mean residual of half to three-quarters of the pair radius by
construction; a cliff at half a pixel rejects exactly those. **The cliff
moved to 0.75 of the pair radius (pre-registered, measured on both
datasets, its own item below): Thronsen at 0.2 % is now 7.96 % free and
6.64 % with the OR** (edge-on 69 %, face-on 52 %, face-on → edge-on 0,
T1 80 %, Al 99.6 %), and the orientation relationship now passes every
clause of its pre-registration. **The OR in its own form landed the same
evening** (pre-registered, `thronsen-orform-20260915.log`): a phase states
pairs of parallel lattice vectors — planes (hkl) or directions [uvw] — and
Core derives the allowed in-plane angle per (matrix entry, candidate entry)
from both zones' own frames, modulo 180° (a flat-Ewald ZOLZ is
centrosymmetric); a pair whose vector is not in the entry's zone does not
apply. θ′ edge-on "(002) ∥ (200), (002) ∥ (020)", face-on "(200) ∥ (200),
(200) ∥ (020)", T1 free: **6.64 %**, edge-on 68 %, face-on 52 %, face-on →
edge-on 0, T1 80 %, Al 99.6 % — every clause held, within one position of
the library-frame angle list it replaces. The field sits under a candidate
slot's zone axis in Phase mapping ("Parallel to matrix") and the pairs are
in the run's provenance. T1's OR is written in real-space directions
([1-10]Al ∥ [10-10]T1) and is not yet stated for its [0 -4 1] zone — it
stays free. **Gate B on the form** confirmed the frame identity (0.0° at
every rotation), the exactness of the 180° fold under the flat Ewald
sphere, and ~9–10 surviving entries per variant at 10°; it found that a
matrix fitted on a zone the pairs were not written for narrows a
two-variant relationship to whichever variant is still in that zone, or
frees it, with nothing shown — recorded here, not hidden; and two test
blind spots, one closed (the crystals swapped inside the derivation, now
a hexagonal-against-cubic (110) case), one recorded (the exact tolerance
boundary is real-valued and not pinned). What remains: detection at the
noise floor for T1's last 20 % and the 38 % of face-on still read as Al. Also
recorded: a phase filtered to no entries vanishes from the map silently,
and every phase empty refuses the map (unreachable while no phase lists
angles).

## The matrix is a verdict by exclusion, so it fails exactly when detection improves — MEASURED 2026-09-16, Gate D target

**Science, live.** 

:

```swift
// 2 — the matrix, by exclusion.
if surviving.count < settings.minimumVectors {
    result.verdict = .matrix
```

 The matrix is scored on its merits in exactly one
place, `challengeByMatrix` (:890), and only as a challenge to a candidate
that has already won; when no candidate clears the guards there is no path
back to a matrix verdict at all, and the position becomes `.notIndexed`.

**The cost is measured, at two thresholds (2026-09-16):**

| detection threshold | Al called Al | Al not indexed | total mislabelled |
|---|---|---|---|
| 0.2 % (shipped record) | 21 400 of 21 494 | 86 | **6.64 %** |
| 0.05 % | **9** of 21 494 | **18 445** | **75.67 %** |

At 0.05 % the precipitates are very nearly solved — θ′ face-on 52 → **93 %**,
T1 80 → **93 %**, and no position in any class has zero survivors any more —
and the map is destroyed anyway, because 99.5 % of Al positions retain 4+
noise survivors and so never reach the by-exclusion branch. The same
behaviour costs **806 positions at 0.2 %, 41.5 % of the whole error**, which
is the share of step 3 nobody has probed.

**Why this is the next increment and not the detector kernel:** every
detection improvement makes this worse, not better. A better kernel that
finds the weak (110) and two-thirds-{220} reflections also finds more noise
maxima on Al, and each one pushes an Al position past `minimumVectors` and
out of the only branch that can call it matrix. The kernel cannot be
evaluated honestly until the matrix verdict stops being a fall-through.

**Not yet diagnosed, and therefore not yet a fix.** What is established is
the branch and its measured cost. What is NOT established is why the
candidate guards let 3 040 Al positions be labelled a precipitate at 0.05 %
while refusing 18 445 others, or what a positive matrix verdict should be
scored against (the matrix entry competes on the SURVIVORS, which it by
construction does not explain — so it would have to be scored on the full
vector set, which is a different comparison from every other phase's). 

 This entry is the diagnosis's starting point, not its conclusion.

**Distinct from** "A challenged matrix verdict is drawn like one by
exclusion" below, which is presentation — two matrix verdicts drawn the same
grey. This one is the verdict itself.

## Phase mapping's two distance thresholds sit near a cliff — added 2026-09-12, the cliff moved 2026-09-15

**Closed as a defect, kept as a caution.** Measured by Gate B on the
harness's own plant: halving `notIndexedAboveInvAngstrom` (0.010 → 0.005)
took β″ from 100 % to 0 %, and doubling `pairRadiusInvAngstrom` did the
same. The second half closed 2026-09-14 (the two radii read their own
values, tested). **The cliff's first measured instance on real data,
2026-09-15 (step 3 entry):** at half a pixel it rejected honest 6–11-vector
θ′ fits at 0.010–0.016 Å⁻¹ while a lucky two-vector pair passed. Moved to
0.75 of the pair radius (0.015; `scaledToDetector` 0.75 px), pre-registered
and measured on both datasets: Thronsen 7.96 % free / 6.64 % with the OR at
0.75 and 7.94 / 6.61 at 1.0 (seven positions), Al unchanged; the demo cube identical at 0.5,
0.75 and 1.0 (`demo-cliff*-20260915.log`, `thronsen-cliff*-20260915.log`).
Not 1.0, where it could never fire. 

## A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12

**Code hygiene, and it is a trap not a defect.** 

 An `XCTFail`
planted in its first line never fired. In the same state a real mutation of the
code under test "survived" — which reads exactly like a blind spot in the test
and sends you looking for a missing assertion that is not missing.

The cause was a stale test bundle:
`Testing failed: … Failed to create a bundle instance representing …`. After
`rm -rf ~/Library/Developer/Xcode/DerivedData` the method was discovered
immediately and the same mutation turned the suite red.

 **A third time, 2026-09-14,** in a
session-scratch `-derivedDataPath`: the run after adding one test method ran
20 of 21 in `PhaseVectorMatchingTests`, dropping a pre-existing method the
previous run had listed, with `-quiet` saying nothing; wiped, the same tree
ran 46 of 46. Count by class, with the suffix `grep -o "()' passed on 'My Mac"`. This is the same family as the
2026-09-08 finding that `-only-testing` with a file name runs nothing and exits
0: the harness reporting success while doing nothing.

## The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15

 Residuals:

 Exports carry no ellipse provenance at all
  (pre-existing: `ResultExport` names the origin fit and rotation, never the
  ellipse).
- **Two radii sharing every azimuth pass the one-ring check** — Gate B built
  it: rings at 40 and 50 px at the same six azimuths blend to a marked,
  isotropic fit at 48.5 px, a radius that is neither ring's. The check reads
  between sectors; no cheap statistic separates within-sector mixing from one
  ring of large disks. Recorded as the cost fixture `overlap_bins_2radii`.
- **The 1.10 bound's value is unpinned**: 1.06 passes, 1.59 refuses, nothing
  between is tested; an unweighted per-sector mean survives every fixture too.
- **Seen on screen 2026-09-15** (`archive/v3/drive-2026-09-15.md`): the
  refusal, the offer, two correct one-ring refusals on the demo cube (its
  {111}/{200} pair is the fcc case the bound exists for), the marked row in
  orange and the caption under Correction.
Also still open from the 2026-09-14 run: R–Q rotation reads "measured" −67.5°
on a cube with no physical rotation (the rotation entry below).

## The rotation null keeps the field's structure now — what it still cannot do — Gate D 2026-09-15 night

**Science, live, narrowed again.** `RotationCalibration.solve`'s null is a
phase-randomised surrogate per channel (each channel's amplitude spectrum
kept, phases randomised, Hermitian pairs opposite), not a shuffle of the scan
positions. Gate D: the diagnosis "the shuffle null is calibrated for white
fields" predicted certification of a rotation-free field rising with its
correlation length, and `tools/rotation-null-probe` measured 15 → 32 → 52 →
65 % for box 1/3/5/7 (`rotation-probe-gateD-before-20260915.log`). After:
7 → 8 → 5 → **17 %** (`…-after-…`); white noise 8 %; planted 30° still 60 of
60; a per-row drift 0 of 6. Pinned by `testAStructuredRotationFreeFieldIsRefused`.
**Two predictions missed, both recorded as limits, not fixed:**
- **Localised features are under-certified.** A 0.05 px two-channel step
  edge, predicted to stay certified because it IS a rotated gradient, is
  refused 6 of 6: a spectrum-preserving surrogate delocalises a step into a
  field-wide wave, so the null's depth exceeds the real field's. A real
  rotation carried mainly by one grain boundary may be refused.

- **Box 7 on a 40-px field certifies 10 of 60**, not 1 in 16 — Gate B
  wrapped the same field periodically and got 5 of 60: the excess is the
  periodic surrogate meeting a non-periodic field, not the rank test.
- **Gate B found `FFT2D`'s one-call vDSP path returning garbage for nx = 8
  or 4 with ny ≥ 8** (round trip off by O(1), DC bin zero) — pre-existing,
  first reached by this null on scan-sized inputs; small power-of-two shapes
  now take the axis-wise path, pinned by
  `FFT2DArbitraryLengthTests.testSmallPowerOfTwoShapesRoundTripLikeTheLargeOnes`.
- **Gate B's four mutations all passed the pinned tests**: dropping the
  Hermitian pairing was catastrophic in the probe (60 → 16 of 60) and
  invisible to a noiseless fixture, so `testANoisyPlantedRotationIsStillCertified`
  now pins sd 0.03; same-phase channels and a cx-only surrogate are
  unfalsified by any current measurement and recorded as such.
- **A 1-D field is refused by design** (a striped specimen and a descan ramp
  are the same field; no cross-channel relation to destroy).

**Presentation fixed 2026-09-15 late night and SEEN on screen 2026-09-15**
(`archive/v3/drive-2026-09-15.md`): the full refusal sits in the inspector's
Rotation diagnostics in orange, the caption says the marker is the minimum
the fit found and was not written, the status bar carries one line pointing
there. The drive also read a stale word — the sentence still said
"shuffling the scan positions" — fixed the same morning to name the
surrogate, pinned by the test. The Gate B narrative
(2026-09-15 morning) is in `archive/closed-items-2026-09.md`.

## ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15

**Do not start a tenth hypothesis.** Nine are refuted and listed with their
measurements in
[`archive/v3/acom-zone-axis-2026-09-15.md`](archive/v3/acom-zone-axis-2026-09-15.md),
including the two most tempting: exporting the demo cube at kMax 1.2 (refuted
by geometry — the added reflections miss the detector) and per-ring L2
normalisation (refuted by measurement — ⟨122⟩ 12.82° → 12.93°, ⟨112⟩ 0.00° →
2.51°; reverted).

 `plan.templates`, `expRe` and `expIm` are already
`package`, so it is about three lines of harness. Nine attempts to guess the
difference have failed; a fix without those pictures is a guess.

**Shipped honesty:** the ACOM panel carries a dated caption — good to a few
degrees on most axes, up to 13.6° off on ⟨122⟩ including the bank's own floor,
more templates measured worse — and "Best" no longer claims to be the finest
sampling. Unverified on screen.

## 26 of 200 ACOM templates do not recover themselves at an off-grid rotation — added 2026-09-14

**Science, live, in shipped code, found by the refuter of the entry above.**

 Confirmed in the Swift harness on a perfect,
complete, noise-free Al [011] pattern: rotation 0.0000° → template 1 at 0.000°,
score 1.00000; rotation 2.8125° → template 1 at 0.000°; **rotation 1.4000° →
template 160 at 1.836°**. Independent of the entry above, which is
rotation-invariant.
**Reproduced harder, 2026-09-15, and the obvious fix was REFUTED.** An
analytic complete noise-free Al [011] net swept across one azimuthal bin in
0.2° steps: **13 of 15 rotations return the wrong zone axis**, by 1.84° or
3.56°, and only the two grid-aligned rotations are right. The wrong template
scores HIGHER (0.7318 against 0.7205), so the rounding is not losing a tie, it
is creating one.
**The fix that does not work:** depositing the azimuth linearly between the two
adjacent bins — which is what py4DSTEM does, and which makes the deposited
centroid exact — takes it from 13 of 15 wrong to **15 of 15 wrong**, breaking
the rotation that used to be right. Reverted, not tuned. So the rounding is not
the mechanism, or not the only one.
**What the numbers now suggest, untested:** the discrimination between zone
axes this close is marginal whatever the deposition. 200 templates over the
cubic fundamental zone is ~1.7° of sampling; the winners here sit 1.8–3.6° from
the truth with scores within 1.5 % of each other; and raising the bank to 1 000
templates made an earlier [001] case WORSE, not better (3.98° against 5.03°).
The next hypothesis to test is therefore that the polar correlation at 32 × 128
bins cannot resolve a zone axis better than a few degrees on a sparse cubic
pattern — i.e. that this is the method's resolution and not a defect at all.

## py4DSTEM's `power_radial` is absent from the port, with no DEVIATION note — added 2026-09-14

**Code hygiene with a science edge; CLAUDE.md makes the note a hard rule.**

`OrientationPlan.swift` carries one DEVIATION note (the sg sign); four more are
owed, all found 2026-09-14: `corr_kernel_size` is py4DSTEM's |sg| membership
cutoff and the experimental image's σ, with **no radial spreading of templates
at all**, where the port spreads both; py4DSTEM's radial axis is discrete
shells at the crystal's unique |g|, the port's is 32 uniform bins over
[0, kMax]; the port subtracts a per-ring mean where py4DSTEM's equivalent is
commented out; and the azimuthal deposition differs as the entry above says.

## Contiguous invalid regions fabricate precipitates — blocks wiring

 The
imputed region is a synthetic constant with ~0 ridge response; past a share of
the frame it dominates the median *and* the MAD of `filtered` and collapses the
robust threshold until background noise clears it. Measured on a six-needle
fixture with a masked column band (truth is 6 at every step): 6 objects to 18 %
masked, then **9 at 25 %, 23 at 31 %, 25 at 37 %** — eighteen fabricated
objects at 31 %, each carrying an area and a length, and `area` reaches an
export through `arealDensity`. `valid[i] = false` cannot help: every fabricated
object lies wholly in valid territory. 

## The three redistributed dylibs have no rebuild path

`libhdf5.dylib`, `libaec.0.dylib` and `libsz.2.dylib` are committed binaries.
As of 2026-09-09 `NOTICE` states each one's SHA-256, byte size and declared
`LC_ID_DYLIB` version, the licence texts are in `Licenses/` and ship at
`Contents/Resources/Licenses/` (verified in a built bundle, not assumed), and
`run-tests.sh inventory` fails if a dylib is unnamed in NOTICE or its hash
moves. 

 Two consequences the hashes do not fix — a security update means hand
work, and their arm64-only-ness is now load-bearing: it is half the reason the
release is pinned to `arm64` (`tools/lib/release-arch.sh`). The `ARCHS` half of
register `D064` is closed — the pin landed 2026-09-09 and the release path is
gated since 2026-09-11. 

## Reading an accessibility label crashes the app — evidence aged off 2026-09-15, suspect named

**Known, a crash, Gate D owed, and now partly un-reproducible.** 

**The `.ips` files are GONE** (checked 2026-09-15: zero mac4DSTEM reports left
in `~/Library/Logs/DiagnosticReports`). macOS ages them out, so the stack quoted
above is now the whole surviving record and nobody can re-read the originals.
Anything wanted from them has to be re-captured by reproducing the crash.
**Suspect, from reading — NOT established.** The app has exactly two
`.accessibilityRepresentation` sites, `UI/HistogramView.swift:66` and
`UI/PaneOverlays.swift:439`, and both layer it on top of an element that has
already been given its own identity:
`.accessibilityElement(children: .ignore)` → `.accessibilityLabel` →
`.accessibilityValue` → `.accessibilityRepresentation { … }`. A representation
REPLACES those, so they are dead weight in the ordinary path — but they are
still in the chain the framework walks while resolving a role, which is exactly
where the reported recursion sits. The histogram's representation is the
stronger suspect of the two: its two sliders have mutually dependent ranges
(`lo`'s upper bound is `hi`'s value and vice versa), so resolving one can
invalidate the other. This repo already has form here — `UI/WorkspaceView.swift:581`
carries a note about a `.combine` that made a button unreachable.
**The experiment, two minutes, owner:** open Accessibility Inspector, point it
at the app's front window, and walk the tree with the inspection pointer while
an Imaging pane with its histogram and a virtual-detector overlay are both on
screen. If it crashes there, comment out the two `.accessibilityRepresentation`
blocks and walk it again — if it then survives, the cause is established and
the fix is to stop layering a representation over a hand-built element. 

## In-body controls report no accessibility label — the same bug

 **This is NOT missing labels in the source** — checked
2026-09-09: they are already `Button("Fit Detector Ellipse")`,
`DisclosureGroup("Ellipse correction")`, `Label("Compute Mean / Max", …)`.
Adding `.accessibilityLabel()` would restate text that is already there, so it
was deliberately NOT done. The emptiness and the crash above are almost
certainly one defect in the same SwiftUI resolution path — the crash happens
while SwiftUI tries to DERIVE a label, and these are exactly the controls whose
label never resolves. 

## The learned-detector parity fixture is a same-runtime claim, and CI has no Neural Engine — added 2026-09-14

**Verification debt.** 

 Gate D: predicted and measured, the
same test fails on the owner's Mac with the model forced to `.cpuAndGPU` —
the fixture's heatmaps are Neural Engine numbers and the near-threshold picks
round differently off it. 

 **Refuted-and-held
2026-09-14:** an independent refuter measured the CPU paths — `.cpuAndGPU`
raw picks 346/354 (97.7 %) with 8 extras (2.26 %), `.cpuOnly` 341/354 with 14;
only the two pick bars fail, accepted counts and positions pass — and
confirmed the gate runs (and fails) here when the app is forced off the ANE.
Two corrections: the fixture records compute units `"all"`, not the Neural
Engine by name; and the probe is hardware PRESENCE, so a Neural Engine that
Core ML declines to use (thermal, an unsupported op) leaves the test running
and failing rather than skipping — acceptable, but not what the skip message
implies. 

## The published v2.5.1 artefact is universal, and Intel users get a broken app

**Not a v3.0.0 blocker — a live defect in what users can download today**
(found 2026-09-11 while closing the archive blocker, which is now fixed;
`archive/closed-items-2026-09.md`). 

 `H5Reader.swift:167` **dlopens**
libhdf5 rather than linking it, so an Intel Mac runs the x86_64 slice, launches
normally; DM4/DM3, MIB and EMPAD data still load, because those readers never
touch libhdf5, while 

 **Cause,
corrected by the refuters 2026-09-11:** NOT an incomplete `D064` fix. The
commit the artefact was built from, `a9a0437`, contains **no `ARCHS` setting at
all** — `git show a9a0437:mac4DSTEM.xcodeproj/project.pbxproj | grep -c 'ARCHS'`
is 0 — so Release simply fell through to `ARCHS_STANDARD`. The pin landed five
days later at `5d08c7d`. An app-target pin would have *removed* this hazard, so
the two defects point in opposite directions and neither is evidence of the
other. **Not established:** the runtime behaviour above is derived from Mach-O
headers and source; no mac4DSTEM build has ever been run on Intel hardware, and
nobody has reported it. v3.0.0 is arm64 alone and gated, so this ends with
v2.5.1 — **verified 2026-09-15**: the project now carries `ARCHS = arm64` in
both configurations and `a9a0437` carried none, so nothing built from here can
repeat it. 

## Owed on screen from C4(c) and C7, after the 2026-09-09 drive

 **Remove IS confirmed** — the 2026-09-09
drive saw `Remove Saved Result?` with a red destructive button and a working
Cancel (`archive/v3/drive-2026-09-09.md`, finding 17). **C7's sidecar reopen is
half-answered**: the calibration round trip works — origin, probe and R–Q
rotation come back as "From session" / "Restored from session" after quit,
relaunch and reopen, and fields never set stay "Not set" (finding 10). 

 Also unreached, same cause: every `Advanced` disclosure, the
Strain / Orientation / Parallax / ptychography sub-pages, and the WS2 CIF import.

## The hexagonal IPF colour key is labelled the wrong way round (2026-09-11)

`OrientationResult.swift:477-479` sets green `sqrt(tilt * (1 - fraction))`,
maximal at azimuth 0, and blue `sqrt(tilt * fraction)`, maximal at 30°.
`Crystal.swift:94` builds `latReal[0] = (a, 0, 0)` at γ = 120°, so +x is a₁ =
⟨11-20⟩ and 30° is ⟨10-10⟩. `PaneOverlays.swift:1021/1023` prints `11-20` then
`10-10` across the key, and `:1031` says "0001 red, 10-10 green, 11-20 blue" —
both read as the opposite assignment. 

 If it is a
swap, a reader takes a 30° texture error off a correct map with nothing on
screen disagreeing, on WS₂, MoS₂, graphite, Ti, Zn and Mg. Reported twice before
(register `D020`). 

## Single-slice ptychography publishes under a mode its export guard misses

 If `runSingleslicePtychography` publishes under
`.singleslicePtychography`, the four iterative branches returning
`objectSamplingRow/ColumnAngstrom`, `engine`, `iterations` and `final_error` are
unreachable, and the phase image gets the scan step as its scale bar instead of
the object sampling — physically independent quantities
(`PtychographyPreparation.swift:110-112`). 

 Feature is `Advanced` and refuses on the owner's cube for
memory, so a smaller cube reaches it first. 

## The Quantitative badge consults no origin gate at all (2026-09-11)

`AppState.quantitativeStatus(for:units:)` decides the badge from a product's
kind and units alone — verified: **zero** references to `originFitIsSane`,
`originSupportsReciprocalMetrology` or `origin_reference_is_measured`. Observed
on the owner's drive: a strain map badged **Quantitative** on the same screen
where Prepare badged its origin **Not quantitative**, computed against
`origin_reference = apertureCentre`.

 Four assumptions it made are false and
must not be repeated. All of it, including the mutation table:
[`archive/2026-09-11-drive/quantitative-badge-gate-b.md`](archive/2026-09-11-drive/quantitative-badge-gate-b.md).

## A radius-only aperture drag destroys the fitted origin (2026-09-11)

Latent, found by the Gate D refuter, and **not** what happened on the owner's
drive. 

 After any
origin fit or restore the live centre is fractional — (69.3133, 54.5009) on
`downsample_Si_SiGe_exp`. 

 Distinguished from
the owner's incident by magnitude: rounding moves <= 0.5 px, his centre moved
10.884 px. The pinning test the refuter proposes is a hypothesis and must be
broken before it is trusted: restore a calibration holding the sidecar's origin
maps, set the aperture to `meanOrigin`, drive `emit` with an outer-radius-only
change, assert `calibration.origin` survives. 

## Moving the detector destroys the origin fit with no durable warning (2026-09-11)

Gate D closed: `updateAperture`'s centre-change branch is doing exactly what it
was designed to do (Gate B note, 2026-08-28), and the design is the problem. 

 the undo (`canRestoreFittedOrigin`)
is real but sits inside `DisclosureGroup("Fit diagnostics & advanced
correction")` with `@SceneStorage showsDiagnostics = false`
(`PrepareSettings.swift:30,120-128`) — collapsed by default and the last row of
a different workspace's sidebar, as the 2026-09-01 drive already recorded. The
app gives no indication that moving the detector destroys the origin fit until
after it has. 

## The one-peak warning is below the fold, and Strain unlocks without it (2026-09-09)

 `Detect All Disks` completed to a green status
strip `Disks ✓ 16384 peaks (Parabolic subpixel)` — exactly one peak per
position, the direct beam only, which is the documented WS₂ behaviour at the
shipped 0.5 % (`DiskDetection.swift:290-296` names this cube) and is what
`expected.json` pins. **The app is not silent**: the acceptance funnel reads
`45 candidates → 1 accepted · absolute 45 · relative 1 · spacing 1`, an amber
smoothing warning is shown, and `summary.warnings` — which includes the
median ≤ 1 text naming Min relative intensity — renders at
`MapSettings.swift:211`. The defect was placement and gating, not absence:
that block sat immediately after the `Per pattern median…` row, which at the
default window height put it **below the visible fold** while the green headline
sat in the bottom bar. **Placement fixed 2026-09-09** — the warnings now render
BEFORE the two count rows (`MapSettings.swift`); unverified on screen. 

 The driving agent first reported this as "nothing distinguishes it from
a healthy run"; that overstated it and the review corrected it — recorded so the
next reader does not re-derive the wrong version. 

## Bullseye disk detection accepts noise — two of three fixes landed 2026-09-05, drive owed

Owner playthrough 2026-09-01 (`calibrationData_bullseyeProbe.h5`). Gate D on
py4DSTEM truth (`tools/bragg-spacing-probe/bullseye-kernel-truth.py`): (1) the
probe-size estimator reads the ring-shaped probe at 7.4 px where the ring ends
at ~10–12; (2) the trench kernel at THOSE radii leaves the beam never
brightest — at the true radii it works as well as flat, so (2) is (1) in
another guise; (3) correlation noise is 2–5 % of the beam peak, so the 0.5 %
default keeps ~130 noise peaks/position. 

## ACOM orientation/export coverage gaps (2026-08-31)

Found in W4b Gate B; the shipping numbers are believed correct but nothing
gated would catch a regression. 

 (c) The exported orientation matrix
can decouple from the reported template index unnoticed. (d) Unpinned: an
additive radial offset, the reliability distinctness test, `intensityPower`.

## Q-calibration scale defects on real crystals (2026-09-02)

(a) closed 2026-09-05 by Gate D + B (`q-calibration-design.md` §8): the
per-position minimum was the same spoke at 99 % of WS₂ positions — a 0.26 px
origin-fit offset, which a symmetric cluster MEAN cancels; the cluster reads
18.902 px against 18.901 from the independent 11-20 shell; `estimate` now
averages the same-shell cluster (14 mutations, 79 harness checks). Residual,
folded into (b): on a single crystal with a 2.4 % Friedel-pair asymmetry
(sim_Au) the band truncates clusters and neither estimator is shown to be
truth. 

## C3 drive leftovers: presentation observations (2026-09-07)

Presentation (C4, no Gate D): the status bar's `0` / `%` wraps during a run
(`shots-c3/a5-running.png`); at ~1 080 pt the status text wraps and the bar
grows (`a3b-narrow.png`); the log opens at its top (`a6-log.png`); a fresh
open shows the Bragg-vector slot or the automatic pass's Virtual detector
depending on the previous state (`b1-configurator.png` vs `b3d-reopened.png`);
"Open with Options…" is reachable only from the empty-state view; "Correlation
power, 1.00" wraps with a stray comma (`a9-strain.png`); System Events cannot
resolve the window's content (VoiceOver question); launching with `-NSRequiresAquaSystemAppearance 1` or
`-AppleInterfaceStyle Light` gives a windowless process. The owner's four
checks closed 2026-09-07 23:38 (light, Remove, crop restore, the warning).

## Parallax and ptychography are unrunnable on the owner's Mac (2026-09-11)

Owner drive, `051_STEM_SI_preprocessed_unfiltered_bin_4_20260629.h5` — a
128x128 scan of 64x64 patterns, **268.4 MB** as f32. Both Advanced Phase
features refuse:
`Parallax KDE needs about 8,16 GB, above the 1,07 GB working limit` and
`Single-slice ptychography needs about 11,55 GB, above its 1,07 GB limit`.
**The refusals are correct behaviour** — they name the number, the limit and the
remedy ("Reduce the factor or crop/bin the dataset first"), and nothing was
computed against a bad budget. Two of the app's failure paths are therefore
driven and good.

The owner has postponed testing them to a machine with more memory; blocking a
release on hardware he does not have is open-ended, so this is scoped, not
blocking (owner, 2026-09-11).

## DM4Reader silently reads the whole file into RAM off non-local volumes (2026-09-02)

 `H5Reader`/`VendorRawReaders` are immune (hyperslab/seek reads).
No fix landed; `.alwaysMapped` trades this for a SIGBUS risk if the
volume disappears mid-read. Needs a CI fixture (a disk image on the internal
disk reproduces `MNT_REMOVABLE` with no external hardware). 

## Scan-fastest DM4 detector pair may be transposed — Gate D owed (2026-09-05)

 DM's convention, which the
same code applies to the scan pair (survey `Spectrum Image Rect` 202 × 895 px
= 17 wide × 77 tall confirms it) and to detector-fastest files, is x first:
dim 3 = 448 = width. Nothing in the 2026-09-05 commit justifies the
asymmetry; its fixture was generated from the code's own model. 

 Residual: honour newer
GMS's `Meta Data.Data Order Swapped` tag (LiberTEM reads it first).

## The open/promote unwind is sixfold, and Cancel can vanish mid-load (2026-09-04)

Six begin/finish brackets, not three: `openFileAsync`, `commitPendingLoad`,
`promoteToFullExtent`, plus `selectDataset`, `openManualPath` and
`openDemoFixture` with no cancel handling at all. The old hazard 1 is
refuted — no suspension point sits between the last cancellation check and
`finishDatasetLoading` on any path (`AppState` is main-actor isolated,
`project.pbxproj:492`). 

## Toolbar Cancel button renders wrong during a run — cosmetic, not blocking (2026-09-04)

Owner, seen driving a full-scan Bragg detection on
`sim_Au_data_all_binned.h5`. `WorkspaceView.swift:231` is a bare
`Button("Cancel", role: .cancel)` with no `.buttonStyle`, so it renders as a
bordered text pill beside three icon-glyph toolbar buttons; `role: .cancel`
buys nothing in a toolbar. The action WORKS — appearance only, and the owner
called it not a big deal. Note the comment above it (`WorkspaceView.swift:224`):
the old inline progress bar was removed there precisely because it squeezed
this label to "C…", so a fix must not reintroduce a width contender in that
slot. Exact symptom still the owner's to pin down (style vs size vs
placement) before anyone changes it.

 What that fix established and this entry can now use: `.mini` sets a 9 pt
label (measured) and a `Text`-labelled button is a flexible child that a tight
row squeezes — the `C…` collapse was reproduced at 1080 pt. The remedy that
worked there is the same glyph-plus-`.help()` pair; 

## DPC's banner contradicts its badge — entry corrected 2026-09-04

Three claims here were wrong. **Mechanism:** the fall-through is `.relative`
(`AppState.swift:761`), not `.quantitative` — only named families are
quantitative (`:759`). Still true: it pattern-matches strings and consults no
calibration readiness, while `idpcPhysicalCalibration` consults three gates.
**Carrier:** not XMP — the PNG `Description` JSON chunk and the status burned
into the caption's pixels (`ResultExport.swift`). 

## Misc unclaimed, low priority (2026-09-02)

 #17a: the wider pane-arrangement
question (design decision, reverted on sight once). Detector-bounds
convention sweep: whether other tests use an index convention for
continuous positions besides the one already fixed, nobody has checked.
HDF5 multi-dataset axis order is assumed (`[ry,rx,qy,qx]`), not checked —
only Ry↔Rx/Qy↔Qx transpositions would be silent, and the app names the
dataset it picked. `MAC4DSTEM_ACOM_SCALE_OVERRIDE`: the sidecar keeps the
estimate scale, not the override scale the map was matched at (design call).
Virtual-detector mask boundary (`r² < rOut²` vs `<=`) is unpinned against
analytic truth. 

## The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04)

`NSGenericException` from `_postWindowNeedsUpdateConstraints`, through
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. 

 SwiftUI's split machinery loops on
it, and `NavigationSplitView` and `.inspector` are splits too. `.fixedSize()`
on text whose string changes is the easiest way to do it by accident, and it
only fires on a dataset big enough for an operation to tick — every
demo-fixture launch was clean and a real one died. 
