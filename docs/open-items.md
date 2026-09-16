# Open items

Live defects, debts, owed runs and open questions only — status is
`docs/status.md`, history is `docs/archive/`. Four lanes (owner, 2026-09-03):
**Science** items are taken one at a time in the order the status handoff
names, carry no release number, and a landed change to a scientific output
cuts v2.6.0; **Verification debt** closes when its run happens; **Known,
scoped** items and the owner's bug reports ship in the next v2.5.x patch;
**Code hygiene** rides with the session that touches its file. Each entry is
≤ 12 lines and dated: what is wrong, the pinning evidence, the trap, the
owner. No narrative. Closed items move to
[`docs/archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md); the
file before the 2026-09-07 trim is verbatim in
[`docs/archive/open-items-2026-09-07.md`](archive/open-items-2026-09-07.md),
the 2026-09-02 pre-cull file beside it. The merged UI-findings list is
[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3 — point there.

## Phase mapping, landed unvalidated 2026-09-12 — added 2026-09-12

### Step 3 ran on a stride-3 subsample and is OUTSIDE their band — measured 2026-09-15
**Science, live; the pre-registered verdict, not softened.** Their 7.4 GB
`datasetA_preprocessed.hspy` was streamed from Zenodo by HTTP range requests
and every third scan row and column written as uint16
(`References/thronsen-datasetA/datasetA_stride3.h5`, 171 × 171, 0.51 GB;
`truth_stride3.json`), and `tools/phase-map-probe --thronsen` runs the
shipped matcher on it and scores by THEIR metric (their four published maps
reproduce at 0.96–1.75 % mislabelled with it). **Result: OUTSIDE their band at every setting tried.** Shipped defaults
98.26 %; a 10 % threshold 26.40 %; 1 / 2 / 3 / 5 % with the reach 25.91 /
26.18 / 26.24 / 26.32 % (`thronsen-*-20260915.log`). The floor is the
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
That, and T1's last 22 %, are what remains. Until the band is reached a
phase fraction off this map is not a measurement and every product still
says `validation: "none"`.

### The 70-peak cap is NOT what costs — REFUTED by its own control, 2026-09-16

**Science, live; Gate D, the record written before the run.** Two facts read
out of the code, not argued:

1. `DiskDetectionParams.maxNumPeaks` is **70**, and the cap is applied at
   DETECTION (`DiskDetection.swift:812-821`: `accepted.sort { $0.score >
   $1.score }`, then `break` at the cap; the tail is cut again at :956-959).
   It keeps the strongest by net score, so what it drops is the weakest — on
   this data the precipitate reflections, 1–5 % of a saturated beam plateau.
2. The probe raises the cap to 200 **inside `--noise-floor` only**
   (`main.swift`). The main detection path leaves it at 70. So the instrument
   that concluded "0.2 % keeps 80 % of T1 pairs at 0.07 % Al" ran at 200,
   while every full-pipeline number that followed it — 13.24 %, 12.22 %,
   8.75 %, 7.96 %, 6.64 % — was measured at 70. No run has reported whether
   the cap was binding.

**The mechanism is arithmetic.** On this cube (0.01904 Å⁻¹/px, probe radius
2 px, so `minPeakSpacing = max(3, 2) = 3 px`) the matcher's outer reach,
0.68 Å⁻¹, is a circle of radius **35.7 px**; its circumference is 224 px,
which holds up to **74 maxima** at 3 px spacing — more than the whole cap.
The data's own mask edge at 0.70 Å⁻¹ holds up to 76. `--reach` discards
those vectors, but it discards them in `experimentalVectors`, i.e. AFTER
detection has spent the cap on them, and they are brighter than any
precipitate reflection. Lower the threshold and the ring fills first.

**Instrument:** `tools/thronsen-dataset/run.sh probe` with a new
`--max-peaks` on the diagnostic probe only (no Core change); the probe now
prints the fraction of positions sitting at the cap. Cells: `--min-relative`
{0.002, 0.001, 0.0005} × cap {70, 200}, `--or` throughout.
**Control, read first:** (0.002, 70) must reproduce **6.64 %** with Al
99.6 %, edge-on 68 %, face-on 52 %, T1 80 %; if it does not, nothing else in
the table is read until that is explained.
**Prediction:** (0.002, 200) alone improves on 6.64 % — the cap was already
binding — and the minimum over the raised-cap cells is below **6.0 %** with
Al at or above 99 %.
**Refuting observation:** no cell improves on 6.64 % while holding Al at or
above 99 %; or the control's own cap fraction shows the cap never bound at
0.2 %, which refutes the mechanism outright. Either sends the next increment
to the detector kernel and the T1 reference.
**Stated before the result so it is not claimed as a lever afterwards:** if
the cap was binding, every step-3 figure back to 13.24 % was measured under a
binding cap — that is a correction to the record, not a gain. And the fix
this points at is not a bigger cap but applying the reach and the direct beam
BEFORE the cap, so the budget is spent on peaks the matcher will use. That is
a Core change to `DiskDetection`, is **not** in this increment, and would be
pre-registered separately under Gate D and Gate B.

**RESULT — the cap is refuted, and the sweep it was bundled with found the
largest single gain step 3 has had.** Four runs, all on
`datasetA_stride3.h5` with `--or` and the tree's shipped cliff:

| `--min-relative` | cap | mislabelled | Al | θ′ edge-on | θ′ face-on | T1 | Al zero-survivor |
|---|---|---|---|---|---|---|---|
| 0.002 (control) | 70 | **6.64 %** | 99.56 % | 68 % | 52 % | 80 % | 98.4 % |
| 0.001 | 200 | **4.18 %** | 98.11 % | 72 % | 99.6 % | 89 % | 91.3 % |
| 0.001 | 70 (shipped) | **4.21 %** | 98.11 % | 70 % | 99.6 % | 89 % | 91.3 % |
| 0.0005 | 200 | **75.67 %** | 0.04 % | 72 % | 93 % | 93 % | 0.0 % |

Logs: `thronsen-cap70-ctrl-`, `thronsen-rel0.001-cap200-`, `-cap70-`,
`thronsen-rel0.0005-cap200-20260916.log`.

**The control reproduced the record exactly — 1942 of 29 241 = 6.64 % — so
the instrument is sound.**

**The cap mechanism is refuted, three times over.** At 0.2 % the detector
finds a median of **23** peaks and only **189 of 29 241 positions (0.6 %)**
sit at the cap; 74 maxima are geometrically possible on the reach ring and
about 23 occur, so the ring does not fill. And at 0.1 % the shipped cap of 70
and a cap of 200 differ by **seven positions** (4.21 vs 4.18 %). The cap was
never binding at any recorded step-3 figure and raising it is not a lever.
The refuting clause was written before the run and it fired.

**The threshold is, and my own reading of it was wrong.** This entry first
said "0.2 % is already near its optimum"; it is not. **0.1 % takes step 3
from 6.64 % to 4.21 % at the shipped cap** — the largest single gain since
the three decisions of 2026-09-15 — and θ′ face-on goes 52 % → **99.6 %**
(966 of 970), T1 80 % → 89 %. **No default moves**: py4DSTEM's 0.5 % remains
the shipped default by the 2026-09-15 decision, and 4.21 % is this
instrument's number at a stated per-dataset setting.

**The pre-registered prediction is met on the total and MISSED on its own Al
clause.** It said "below 6.0 % with Al at or above 99 %". The total is 4.21 %,
but Al is **98.11 %**, below the 99 % I wrote. Recorded as a miss rather than
rounded away: 407 Al positions of 21 494 are lost to buy 2.4 points of total.
Whether that trade is acceptable is a judgement about this metric, which
counts every class equally while Al is 73 % of the map.

**Below 0.1 % is a cliff, not a slope.** 0.05 % gives 75.67 %. Between the
two the Al class goes from 98.11 % to 0.04 % for a factor of two in
threshold. A setting that good at 0.001 and catastrophic at 0.0005 is not a
default anyone should ship; it is evidence about the code, and the next entry
says what of.

**The mechanism of the cliff, measured across all four runs.** Al's accuracy
tracks its zero-survivor fraction almost exactly — 98.4 → 99.56, 91.3 →
98.11, 0.0 → 0.04. That is the `surviving.count < minimumVectors` branch at
`PhaseVectorMatching.swift:769` and nothing else. See the next entry.

**What the runs also settle about the residual at 0.2 %** (the decomposition
that motivated all of this, reconciled to the printed 1942): 1058 (54.5 %) a
precipitate called matrix, of which 1038 are exactly the ≤ 1-survivor
positions; 806 (41.5 %) not indexed; 76 (3.9 %) genuine cross-phase
confusion. The identity is exact — (18.4 + 19.5) % × 970 = 367.7 face-on
positions with ≤ 1 survivor against **367** labelled Al, and
(4.6 + 5.9) % × 6358 = 667.6 against **671**.

**And it answers the owner's standing question 4** ("may a candidate be
indexed on one or two characteristic reflections, and at what false-positive
cost?") with a bound rather than an opinion — at 0.2 %, granting it
*perfectly* gives 1942 − 564 + 236 = 1614 = **5.52 %**, worth about 1.1
points at its theoretical maximum. At 0.1 % the question largely dissolves:
face-on has no zero- or one-survivor positions left at all. **It should be
decided on its merits for real specimens, not as a step-3 lever.**

**Measured on the demo cube too, before the number is claimed**
(`demo-rel0.002/0.001-20260916.log`, 100 × 100, its own `truth.json`): the
two thresholds are **identical** and every clause of the demo
pre-registration holds at both — grain A matrix 100 %, grain B labelled β″
0.0 %, end-on recall 100 %, needle recall 100 %, vacuum as no-data 100 %,
median 9 peaks at both. So 0.1 % buys 2.4 points on Thronsen and costs the
demo cube nothing. (The demo cube is a weak test of a detection threshold —
its planted reflections are far above any noise floor — which is itself worth
saying rather than reading its agreement as strong confirmation.)

**Where this sends the next increment**, by the stopping rule
(`decisions.md` 2026-09-16): the matrix-by-exclusion branch, which is what
the cliff is made of and what caps every future detection improvement. The
cap is closed; the threshold is measured and is a setting, not a code change.

### The matrix fall-back reaches 3.13 %, and I am recommending AGAINST shipping it — 2026-09-16

**Gate D, written before the run.** Diagnosis, already established by the entry
below and not re-argued: `PhaseVectorMatching.swift` sends a position to
`.notIndexed` whenever no candidate phase clears its guards
(`guard !bestPerPhase.isEmpty else { result.verdict = .notIndexed }`), even
when the matrix orientation already explained most of that position's vectors.
The matrix can only be reached by exclusion (`surviving.count <
minimumVectors`) or by challenging a candidate that has already won. There is
no path from "no candidate fits" back to "this is matrix". Measured cost: 806
positions at a 0.2 % detection threshold (41.5 % of the error), 18 445 of
21 494 Al positions at 0.05 %.

**Instrument:** `PhaseVectorSettings.matrixFallbackExplainedFraction`, **0 by
default so nothing ships changed** — when no candidate clears and the matrix
explained at least that fraction of the position's vectors
(`removedCount / vectors.count`), the verdict is matrix rather than a refusal.
Driven by `tools/phase-map-probe --matrix-fallback f`.

**Control, read first:** `f = 0` at 0.1 % and cap 70 must reproduce **4.21 %**
(Al 98.11 %, edge-on 70 %, face-on 99.6 %, T1 89 %). Anything else and the
table is not read.

**Prediction.** At 0.1 %: the total falls below **4.21 %** and Al rises above
**99 %**, while θ′ face-on and T1 recall each fall by no more than **2
points**. At 0.05 %, where the precipitates are already near-solved and the map
is destroyed by 18 445 refusals, the total falls below **20 %** from 75.67 %.

**Refuting observation.** Face-on or T1 recall falls by more than 2 points —
i.e. the fall-back is buying Al back by swallowing real precipitates — or the
total does not improve at 0.1 %. Either refutes "the refusal is what costs" and
sends the next increment to the detector kernel with the matrix verdict left
as it is.

**RESULT: the fall-back never fired, at either threshold, and the instrument
has been removed.** 0.1 % with `f = 0.8` gave **1230 of 29 241 = 4.21 %** with
every class byte-identical to the control
(`thronsen-fallback0.8-rel0.001-20260916.log`); 0.05 % gave **22 128 = 75.67 %**,
Al still 9 correct and 18 445 not-indexed
(`thronsen-fallback0.8-rel0.0005-20260916.log`). Identical, not merely similar.

**Part of that is a flaw in this pre-registration, and saying so is the
point.** `f = 0.8` was chosen without first measuring what fraction the matrix
actually explains at refused positions. At 0.05 % Al has a median of **14**
detected vectors and its [001] pattern has four reflections inside the 0.70 Å⁻¹
mask, so the explained fraction there is about **0.29** — the gate could not
have opened at 0.8 whatever the verdict logic did. The measurement that should
have come first is the distribution of `removedCount / vectors.count` at the
positions that end not-indexed. **A pre-registration whose threshold is
unmeasured is not a test of its hypothesis; it is a test of the threshold.**

**What the pair of runs does establish.** There are three paths to
`.notIndexed` and only one was instrumented: no candidate cleared
(`bestPerPhase.isEmpty`), the winner's score over the verdict cliff, and the
phase-contrast margin. Since the fall-back changed nothing, the refusals are
NOT arriving by the first path — they arrive with a candidate already chosen
and then rejected, which is the **cliff**. That relocates the target.

**And it re-weights the whole residual.** At 0.1 % the error is no longer
mostly "a precipitate called matrix"; it is **not-indexed, 1024 of 1230 = 83 %**
— T1 617, Al 354, edge-on 49, face-on 4 — against 61 precipitates called matrix
and 143 genuine cross-phase confusions. The 54 %/41 % split measured at 0.2 %
does not survive the threshold change, and any plan resting on it is stale.

**The instrument was removed rather than left inert.** A setting that provably
never fires, kept "in case", is the same defect as
`minimumMatchedFraction` recorded below: code asserting a capability that does
nothing. `PhaseVectorMatching.swift` and `tools/phase-map-probe` are back to
their committed state; this entry is the record.

**Next, by the stopping rule (`decisions.md` 2026-09-16), revised by this
result:** the verdict cliff's contribution to the 1024 not-indexed positions,
measured first as a distribution — the winner's score against
`notIndexedAboveInvAngstrom` at every refused position — before any rule is
changed. T1 alone is 617 of them and its reference is already known to be wrong
in detail, so the T1 reference and the cliff should be measured together.

**CORRECTION, and it is mine.** The commit that recorded the f = 0.8 run
concluded "the refusals do not arrive by the empty-candidate path… they arrive
by the verdict cliff". **That is wrong**, and the next measurement says so
(`thronsen-whynotindexed-20260916.log`). Of the 1024 not-indexed positions at
0.1 %, the refusal path splits:

| truth | refused | nothing cleared | cliff-refused | score/cliff p25–p75 |
|---|---|---|---|---|
| Al | 354 | **347 (98 %)** | 7 | 1.05–1.17 |
| T1 | 617 | **604 (98 %)** | 13 | 1.04–1.14 |
| θ′ edge-on | 49 | 40 (82 %) | 9 | 1.07–1.19 |
| θ′ face-on | 4 | 3 (75 %) | 1 | 1.01 |

**98 % arrive by exactly the path the fall-back patched.** It did nothing
because 0.8 was too high, not because the path was wrong. The verdict cliff is
worth about **30 positions**, all sitting at 1.01–1.19 × the cliff, and is not
a lever. I inferred a mechanism from a null result instead of measuring it, and
the measurement that settles it cost one run.

**The threshold, measured rather than guessed**
(`thronsen-explained-20260916.log`), as the explained fraction
`removed / detected` where nothing cleared: Al p10–p90 **0.33–0.67** (median
0.67), T1 **0.50–0.67** (median 0.67), θ′ edge-on **0.18–0.33**, face-on
0.44–0.67. **Al and T1 overlap almost exactly**, so no threshold separates
them — which is the finding, not an obstacle.

**RESULT at f = 0.33** (`thronsen-fallback0.33-20260916.log`): **915 of 29 241
= 3.13 %**, from 4.21 %. Al 21 087 → **21 402** correct (99.57 %), not-indexed
across the whole map down to **0.3 %**. The demo cube is **unchanged** — all
three grains, both precipitate classes and vacuum at 100 %, every clause held
(`demo-fallback0.33-20260916.log`).

**Why I am recommending against a non-zero default anyway, and the arithmetic
that makes the case.** The 1.08-point gain is two different things added
together:

- **315 positions of real gain** — Al positions that ARE matrix and were being
  refused. Legitimate, and worth having.
- **600 positions of metric-neutral shuffle** — T1 positions that go from
  "not indexed" to "Al". They were counted wrong before and are counted wrong
  now (T1 → Al rises 39 → 639, T1 not-indexed falls 617 → 17). **The score
  improves; the map does not.**

That second part is the problem. The map stops saying "I do not know" about
600 T1 positions and starts positively claiming they are aluminium. **The
deliverable of this whole feature is a phase fraction**, and this silently
overstates the matrix fraction by ~2 % of the map — in the one direction a
microscopist would not catch, because matrix is the expected answer. It also
contradicts the standard this repo set for itself in `8369fbf`, that a refusal
reads as a refusal.

**So: the setting lands at 0, the number is recorded, and the owner rules.**
If he wants it on, the honest form is probably a separate verdict — "matrix by
exclusion" drawn and counted apart from "matrix by fit" — rather than folding
both into one colour and one fraction. That is a bigger change than a
threshold and would need its own pre-registration, the demo cube, and Gate B.

**Stated before the result.** A fall-back that works is NOT licence to ship a
non-zero default: it changes what "matrix" means on every dataset, so it would
need the demo cube, a Gate B refuter, and a decision from the owner about the
default before any number moves. This increment ends at the measurement.

### The matrix is a verdict by exclusion, so it fails exactly when detection improves — MEASURED 2026-09-16, Gate D target

**Science, live.** `PhaseVectorMatching.swift:769-773`:

```swift
// 2 — the matrix, by exclusion.
if surviving.count < settings.minimumVectors {
    result.verdict = .matrix
```

`minimumVectors` is **2**. So a position is called matrix when *almost
nothing survives matrix removal* — never because the matrix entry actually
explains the pattern. The matrix is scored on its merits in exactly one
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
vector set, which is a different comparison from every other phase's). Gate D
before any edit: diagnosis, refuting observation, prediction, then the
experiment — on `tools/phase-map-probe`, on both datasets, before a number
moves. This entry is the diagnosis's starting point, not its conclusion.

**Distinct from** "A challenged matrix verdict is drawn like one by
exclusion" below, which is presentation — two matrix verdicts drawn the same
grey. This one is the verdict itself.

### The phase-contrast margin cannot lower the step-3 number — REFUTED BY MECHANISM 2026-09-16

`minimumPhaseContrastInvAngstrom` (`PhaseVectorMatching.swift:149`, the
refusal at :840) was built in answer to a refutation and still defaults to 0,
so it reads like an unmeasured lever. It is not one for step 3, and no run was
spent on it: the setting only ever converts a verdict to `.notIndexed`, and
`tools/phase-map-probe/thronsen.swift:127-129` maps `.notIndexed` to −1,
"which counts as mislabelled against every class". A refusal therefore leaves
a wrong position wrong and turns a right position wrong. It can only raise the
mislabelled fraction. It may still be a correct guard for a user; it is not a
step-3 lever, and the NEXT list should not carry it as one.

### `minimumMatchedFraction` does not exist — added 2026-09-16

`PhaseVectorMatching.swift:682` explains why the matrix fit is chosen by
matched count and only then by distance: "Not by mean distance alone: an entry
matching one vector at 0.001 Å⁻¹ would win over one matching nine at 0.01,
which is the same completeness trap `minimumMatchedFraction` closes on the
candidate side." **`minimumMatchedFraction` occurs nowhere in the repo except
that sentence** (`grep -rn` over all `.swift` and `.md`; introduced with the
comment in `cee63e6`). The candidate side is guarded by
`minimumMatchedVectors` and `chanceMatchMultiple`, which are floors on COUNT,
not on the fraction of an entry's accessible vectors that matched — a
different quantity, and not the one the comment claims. The cross-phase winner
at :834 is still `bestPerPhase.sorted { $0.value.score < $1.value.score }`,
mean distance alone, which is exactly the trap the sentence says is closed.
The measured instance is already on the record: at the 110 off-OR edge-on
positions the honest entry matches 6–11 of ~20 survivors (matched fraction
0.20) and loses to a two-vector Friedel pair (0.12). **No number moves from
this entry** — the comment is wrong, not the code — but the comment must not
be left asserting a protection that is not there, and a real
`minimumMatchedFraction` is a candidate instrument once the detection levers
are spent.

### The Al-Mg-Si cube's peak set is not clean enough — added 2026-09-12

**Science.** On `060_STEM SI_…bin_4`, only **39 %** of detected vectors are
explained by the best-fitting Al orientation at one-pixel tolerance, on a
specimen whose matrix is aluminium. Measured by `tools/phase-map-probe` with a
synthetic 2.5 px kernel and default spacing on a 4×-binned 64 px detector, so
this is a statement about the DETECTION, not the matcher. The app's own path —
a measured probe kernel, a fitted origin map, the ellipse — is what the probe
skips. Evidence: `docs/archive/v3/phase-mapping-2026-09-12.md` §"Step 4".
Not blocking: the matcher refuses (99.0 % "not indexed") rather than inventing.

### The β″ zone axis for ⟨110⟩Al data is not chosen — added 2026-09-12

**Known, scoped.** β″ is coherent along its b-axis with a ⟨100⟩Al direction, so
with the beam on ⟨110⟩Al — which is where this cube sits, measured — no variant
is viewed down its needle axis and a [010]β″ library cannot match. Which β″
zone axes a ⟨110⟩Al beam DOES present is a crystallographic question nobody has
answered here; until it is, the UI lets the user type one and the method
refuses when it is wrong, which is the correct behaviour but not the answer.

### Phase mapping's two distance thresholds sit near a cliff — added 2026-09-12, the cliff moved 2026-09-15

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
Not 1.0, where it could never fire. What remains a caution: the best entry
per phase is still chosen by mean distance alone, so a sparse precise match
outranks a dense one — **across phases too** (Gate B 2026-09-15: a two-vector
match at 0.004 beats a ten-vector match of another phase at 0.012) — a
count-aware score is not built, and the pair floor makes two-vector matches
admissible.

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12

**Code hygiene, and it is a trap not a defect.** Twice on 2026-09-12 a newly
added test method was **not discovered by XCTest at all**: eight of nine cases
ran, the ninth never appeared, and the suite reported success. An `XCTFail`
planted in its first line never fired. In the same state a real mutation of the
code under test "survived" — which reads exactly like a blind spot in the test
and sends you looking for a missing assertion that is not missing.

The cause was a stale test bundle:
`Testing failed: … Failed to create a bundle instance representing …`. After
`rm -rf ~/Library/Developer/Xcode/DerivedData` the method was discovered
immediately and the same mutation turned the suite red.

**The rule this buys:** reconcile the case count against `func test` **per
file** when adding tests, not only for the whole suite — `cases: 8 declared: 9`
is the signature. And a mutation that survives on an incremental build is not
evidence until it survives on a clean one. **A third time, 2026-09-14,** in a
session-scratch `-derivedDataPath`: the run after adding one test method ran
20 of 21 in `PhaseVectorMatchingTests`, dropping a pre-existing method the
previous run had listed, with `-quiet` saying nothing; wiped, the same tree
ran 46 of 46. Count by class, with the suffix `grep -o "()' passed on 'My Mac"`. This is the same family as the
2026-09-08 finding that `-only-testing` with a file name runs nothing and exits
0: the harness reporting success while doing nothing.

### The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15
**Known, scoped.** The flag the owner asked for landed 2026-09-15 behind an
explicit "Fit Anyway" button (`decisions.md`; the closed entry with the four
refuted statistics is in `archive/closed-items-2026-09.md`). Residuals:
- **The mark does not survive a session round trip.** `PixelCalibration`
  carries a/b/θ and nothing else, so a restored fit-anyway ellipse reads "From
  session". The sidecar wire format is the owner's (plan §8); a field there is
  a format decision, not a fix. Exports carry no ellipse provenance at all
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

### A challenged matrix verdict is drawn like one by exclusion — added 2026-09-15
**Presentation, live; the science is closed** (`archive/closed-items-2026-09.md`,
"A second matrix grain…"). A position the matrix takes back through `classify`
step 5 gets the same neutral grey as one where removal left too little to
index, and `PhaseMap.phaseCounts` cannot separate the two. The evidence line
does distinguish them; nothing else does. The demo cube's matrix fraction moves
51 % → 74 % because of it, which is correct but unexplained on screen. Owner:
presentation only, so no Gate D.

### The rotation null keeps the field's structure now — what it still cannot do — Gate D 2026-09-15 night
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
- **Power drops at the highest noise:** planted 30° at sd 0.05 is refused
  3 of 12 (0 of 48 at sd ≤ 0.03), against 0 of 60 under the shuffle null.
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
**The owner's own case class:** the demo cube's field is shot noise at
sd ≈ 0.010 on 100 × 100 (measured 2026-09-14); the probe's `A-100` row
certifies **2 of 60** such fields, so "Measured −67.5°" recurs about once in
thirty, not every time. The cube itself has not been re-run through the app.
**Presentation fixed 2026-09-15 late night and SEEN on screen 2026-09-15**
(`archive/v3/drive-2026-09-15.md`): the full refusal sits in the inspector's
Rotation diagnostics in orange, the caption says the marker is the minimum
the fit found and was not written, the status bar carries one line pointing
there. The drive also read a stale word — the sentence still said
"shuffling the scan positions" — fixed the same morning to name the
surrogate, pinned by the test. The Gate B narrative
(2026-09-15 morning) is in `archive/closed-items-2026-09.md`.

### ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15
**Science, live, no fix, cause narrowed to the score itself. One entry for the
whole investigation** — the separate "bank predicts rings the demo cube cannot
contain" entry is folded in here.
**Where it started.** The demo cube's grain A is aluminium exactly on [001] and
the matcher returned a template 3–5° away. An independent refuter established
that the cube's exporter writes reflections at kMax 0.9
(`tools/demo-dataset/export_reflections.swift`) while the bank is built at 1.2
(`AppState.swift`), so the bank predicts two rings the data cannot contain —
and on an IDEAL complete plant the offset is 0.000°. That is inherited from
py4DSTEM, not a port bug: a transcription of theirs picks the same template.
**The "one `tools/` line" (export at 1.2) is refuted by geometry, 2026-09-15:**
a scratch build of the exporter at kMax 1.2 adds twelve Al [001] reflections
({400} at 0.988, {420} at 1.104 Å⁻¹), and at grain A's 12° rotation none of
them lands on the 128-px detector (half-width 0.762, corner 1.086 Å⁻¹). It
would add two {400} spots in grain B's corners and four weak β″ [010] spots,
nothing on [001], so it cannot move the [001] result and is not taken; the
bank predicting rings past the detector's edge is every real detector's
situation, and the matcher's to handle.
**But it is not the whole story**, because on the cube's own detected peaks no
bank kMax fixes it (0.768, the detector's own reach, leaves grain A at 2.2–6.7°
and makes grain C worse), and the same offsets appear on axes with no phantom
rings at all. So the app has never had a number for how accurately it orients,
and this is that number. `tools/acom-groundtruth/orientation-accuracy.py`
(new, diagnostic) plants known zone axes — reflections from the fcc rule by
hand, the zone by `g·n = 0`, the 2D frame by Gram-Schmidt here, so the plant
shares nothing with the code it gates — and sweeps the in-plane rotation across
two azimuthal bins. 136 patterns, Al, shipped settings.
**The bank is a Fibonacci sampling of the fundamental zone, not a list of
low-index axes**, so part of any error is the distance to the nearest entry the
bank actually holds. That floor is measured from the bank the harness reports
and subtracted; what is left is the defect.

| planted | spots | floor | worst | **beyond the floor** |
|---|---|---|---|---|
| ⟨100⟩ ⟨111⟩ ⟨012⟩ ⟨112⟩ | 6–20 | 0.00–1.09° | = floor | **0.00°** |
| ⟨011⟩ | 22 | **0.00** | 1.88° | **1.88°** |
| ⟨123⟩ | 8 | 0.97 | 3.50° | **2.53°** |
| ⟨122⟩ | 6 | 0.79 | 13.61° | **12.82°** |

So the matcher is exactly as good as its bank allows on half the axes tried,
and on the others it returns an answer up to **12.8° further away than it had
to** — on ⟨011⟩, which is a seeded vertex of the bank and therefore present
exactly. **Which answer you get depends on the in-plane rotation**: ⟨122⟩
alternates 0.8° (the floor) and 13.6° as the specimen turns, and ⟨011⟩ is right
at 3 of 17 rotations and 1.88° off at the other 14.
**This is the same family as the self-recovery failure recorded above** and
probably the same cause; it is separated because this one is measured against
planted truth rather than against the templates themselves, and because it
gives the size. It also explains the demo cube's grain B, which is ⟨011⟩ and
came back 7.0° and 3.6° off.
**THE SCORE PREFERS THE WRONG ORIENTATION — it is not the search.** Measured
2026-09-15 by exposing every template's score (`OrientationMatcher.templateScores`,
diagnostic): at its worst rotation each failing axis has the winner beating the
best available bank entry by a real margin — ⟨013⟩ 0.6 %, ⟨011⟩ 3.5 %, ⟨122⟩
4.9 %, ⟨123⟩ 10.0 %. The search finds the true maximum of the score; the score
is simply higher on the wrong template. That is why every knob failed, and it
means the fix is in what the score measures, not in how finely it is sampled.
**EIGHT HYPOTHESES ARE SPENT, each refuted by its own experiment and each
recorded so nobody retries it:** radial binning; the bank's kMax; the intensity
power; the azimuthal deposition rounding (its py4DSTEM-matching fix improves
how OFTEN but not how BADLY, and makes two axes worse); the azimuthal blur
(reducing it makes three axes worse); more azimuthal bins (fixes most cases at
512–1024, so resolution is a factor but not the mechanism); parabolic
interpolation of the correlation peak (changes almost nothing — which is what
proved the sampling is not at fault); and py4DSTEM's own `power_radial`, whose
default is measurably worse.
**THE MECHANISM IS FOUND (2026-09-15), by looking at the pictures instead of
guessing.** `OrientationMatcher.experimentalPolarImage` and the harness's
`dumpTemplates` now expose the experimental polar image and any template's, so
the inner product the score computes can be read. For a ⟨122⟩ plant at 0.35°
where the matcher is 13.6° wrong, the per-ring correlation peaks are:

| | rings 15–22 peak at shift | rings 25–31 peak at shift |
|---|---|---|
| the TRUE template | 57 | **58** |
| the winner | 13 | 13 |

**The true template's inner and outer ring groups disagree by one azimuthal
bin, so no single shift aligns both.** The score is `max over shift of the SUM
across rings`, so the truth is charged for a misalignment it did not have: at
57 the outer group is a bin off, at 58 the inner group is. The winner's rings
all agree, and wins by 4.88 % while being 13.6° wrong. The cause is the
azimuthal ROUNDING, acting on the RELATIVE phase between ring groups rather
than on any ring alone — which is why every hypothesis that looked at one ring,
one knob or one statistic missed it.
**Demonstrated:** with linear azimuthal deposition the true template's rings
converge on shift 57 and it **wins this case**, 0.56852 against 0.56114.
**But it is not a clean fix, and that is the owner's call.** Across the full
136-pattern sweep, against the bank's own floor:

| | wrong answers | total worst-case excess |
|---|---|---|
| shipped (rounding) | 40 / 136 | 18.79° |
| linear deposition | **28 / 136** | 20.10° |

It cuts wrong answers by 30 % and matches py4DSTEM, removing an undocumented
deviation. It also makes ⟨012⟩ and ⟨112⟩ — exact at every rotation today —
wrong at 2 and 4 rotations, and it does **not** touch the headline 12.82° on
⟨122⟩.
**The regression was chased and is NOT what it looked like.** It clusters at
HALF-bin rotations (⟨012⟩ at 1.40° and 4.20°, against a 2.8125° bin), which
looks exactly like the amplitude error of splitting a spot 50/50 between two
bins. So the azimuth was deposited instead as a **Gaussian centred on the exact
fractional bin** — what the radial axis already does, with the separate blur
pass subsumed — which preserves phase AND shape. It gives the same answer:
30 wrong of 136, and ⟨012⟩ and ⟨112⟩ still regress by the same amounts. The
shape hypothesis is refuted; both variants are reverted.
**And that experiment was run, and refutes the explanation.** The pattern
suggested the regression was the bank's own coarseness — every regressing axis
had a non-zero sampling floor, every zero-floor axis improved — so the sweep was
re-run at **1 000 templates**, where the floors shrink. Linear deposition gets
WORSE, not better: **68 wrong of 136 against the shipped 48**, and ⟨111⟩, exact
at every rotation under both schemes at 200 templates, becomes wrong at 10 of
17. The bank-coarseness explanation is dead.
**A second thing fell out of it, and it is worth more than the hypothesis it
killed: MORE TEMPLATES MAKE ACOM WORSE.** Shipped deposition at 1 000 templates
is 48 wrong and 20.83° of excess against 40 wrong and 18.79° at 200. Raising
the bank is the obvious thing a user or a future session would reach for, and
it is the wrong lever — recorded here so nobody spends a day on it.
**Owner: the deposition fix stands as a trade with no explanation for its own
regression** (30 % fewer wrong answers at 200 templates, two exact axes made
sometimes-wrong, worst case untouched). Take it, leave it, or send it back for
a mechanism. Eleven hypotheses are now spent and every one is written down.
**NINE HYPOTHESES WERE SPENT BEFORE THE PICTURES. The whole-image L2
normalisation was the last of them and it is refuted too:** per-ring L2 on both sides makes the total worse
(⟨122⟩ 12.82° → 12.93°, ⟨112⟩ 0.00° → 2.51°, ⟨013⟩ 1.56° → 2.93°). Reverted.
**So the next step is not another knob, and anyone who reaches for one should
read this list first.** What has never been done is to LOOK at the two polar
images for a failing case: dump the experimental image and both templates —
the winner's and the true axis's — for ⟨122⟩ at a rotation where it fails, and
find what the winner has that the truth does not. The score is a number over
those two pictures; nine attempts to guess the difference have failed, and the
pictures are three lines of harness away (`plan.templates` and the matcher's
`expRe`/`expIm` are already `package`). Until someone does that, a fix is a
guess. The honest statement for a user — good to a few degrees on most axes,
up to 13.6° off on ⟨122⟩ (the total, floor included: a user cannot subtract
the bank's spacing), more templates measured worse — is on the ACOM panel
since 2026-09-15 (a static caption with its date and scope, unverified on
screen); the "Best" preset no longer calls 400 templates the finest sampling.

### 26 of 200 ACOM templates do not recover themselves at an off-grid rotation — added 2026-09-14
**Science, live, in shipped code, found by the refuter of the entry above.**
Feed every template its own exact spots back in. At an in-plane rotation that
lands on the 2.8125° azimuthal grid, 0 of 200 fail and the self-score is
exactly 1.0000. At an off-grid rotation, **26 of 200 fail to recover
themselves, by 1.7° to 9.3°**. Confirmed in the Swift harness on a perfect,
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
That is a different experiment: compare the TRUE template's score against the
winner's across many orientations, rather than chasing the winner. Gate D owed
before any change; two hypotheses are already spent.

### py4DSTEM's `power_radial` is absent from the port, with no DEVIATION note — added 2026-09-14
**Code hygiene with a science edge; CLAUDE.md makes the note a hard rule.**
`grep -r "power_radial\|powerRadial\|radialPower" mac4DSTEM/` returns nothing,
yet it sits in the same expression as the `power_intensity` the port does
implement (`crystal_ACOM.py:809/816`), multiplying template weights by shell
radius — which up-weights exactly the outer rings the entry above is about.
`OrientationPlan.swift` carries one DEVIATION note (the sg sign); four more are
owed, all found 2026-09-14: `corr_kernel_size` is py4DSTEM's |sg| membership
cutoff and the experimental image's σ, with **no radial spreading of templates
at all**, where the port spreads both; py4DSTEM's radial axis is discrete
shells at the crystal's unique |g|, the port's is 32 uniform bins over
[0, kMax]; the port subtracts a per-ring mean where py4DSTEM's equivalent is
commented out; and the azimuthal deposition differs as the entry above says.
An existing item, "ACOM omits py4DSTEM's `power_radial` weighting
(2026-08-28)", already names the first of these — this entry is the measured
list around it.

### The zone-axis sweep marks a wrong axis against its own median — Gate D 2026-09-15 night, residuals
**Science, narrowed.** Gate D found why the disc-chance floor could never mark
the owner's ⟨112⟩ at 8 %: on a real crystal a wrong axis explains 11–25 % of
the vectors through SHARED reflections, not chance — measured on planted
⟨110⟩, ⟨112⟩ and ⟨001⟩ aluminium at 2° steps with 30 % of spots missing,
0.004 Å⁻¹ jitter and three spurious peaks per pattern, where every one of
the 49 axes cleared five times disc chance and the median wrong axis sat at
11–16 % (`chance/run1.log`). So `ZoneAxisFit` carries a second null, the
sweep's median explained fraction: true families sat at 4.8–6.8× it, wrong
families at 0.7–1.6×, the bar is 2×, and a row under it reads "no better
than a wrong axis". The disc rule stays for vectors pointing nowhere (sweep
median ~0.5 %, where the median is no null). Pinned by
`testAWrongAxisThatSharesReflectionsIsMarkedBelowTheSweep`, whose control
asserts the defect (⟨112⟩ clears disc chance) beside the fix.
**Trap paid, recorded here because it faked a surviving mutation:** the
filtered `xcodebuild test` runs used to check this test never DISCOVERED it
(22 cases both times, the new name absent — the stale-bundle trap above),
so the bar-to-1 mutation "survived" a test that had not run; the mutation
was demonstrated instead on a scratch harness with the same generator
(27 of 43 wrong axes clear a bar of 1, 0 clear 2, `chance/`), and the fresh
`unit` gate is what discovers the test.
**Gate B (2026-09-15 late night) narrowed it and found the gap that mattered:**
- **"Find Matrix Zone Axis" wrote the winner into the phase model regardless
  of either null** — the marks were presentational only. Now a winner that is
  informative by neither rule is shown and not written, with the reason.
- **The bar is not a clean separator for every truth.** ⟨111⟩, ⟨012⟩, ⟨210⟩
  plants: true 2.7–2.8×, worst wrong 1.0–2.0×. A ⟨122⟩ plant: true 2.8× and
  the ⟨100⟩ family 2.7–2.9×, sometimes above the truth — both rows read as
  informative and the tie caption is the honest thing. A two-grain scan left
  both true families at 5×; degradation to 92 % missing never made the sweep
  rule bind before the disc rule.
- **Fewer than five axes had no median** — with two, the ratio saturated at
  1; unreachable from the app (the sweep is always all 49) and now inert
  below five, pinned by `testATinySweepHasNoMedianNull`. The four mutations
  of the rule are each killed by the sweep test's own assertions; the gated
  `phase-vector-matching` harness never constructs a `ZoneAxisFit`.
**Residuals:** the bar rests on synthetic plants, not on the owner's cube
(not on this machine); the disc model still understates chance about sixfold
for ring-confined vectors. **Unverified on screen.** The 2026-09-14 entry is
in `archive/closed-items-2026-09.md`.

### Contiguous invalid regions fabricate precipitates — blocks wiring
`PrecipitateSegmentation.segment()`'s non-finite guard imputes the finite
median. That survives scattered NaN and **not** a large contiguous invalid
region — the shape `Core/Analysis/StrainMapping.swift:81` actually writes. The
imputed region is a synthetic constant with ~0 ridge response; past a share of
the frame it dominates the median *and* the MAD of `filtered` and collapses the
robust threshold until background noise clears it. Measured on a six-needle
fixture with a masked column band (truth is 6 at every step): 6 objects to 18 %
masked, then **9 at 25 %, 23 at 31 %, 25 at 37 %** — eighteen fabricated
objects at 31 %, each carrying an area and a length, and `area` reaches an
export through `arealDensity`. `valid[i] = false` cannot help: every fabricated
object lies wholly in valid territory. **Do not wire this engine to a product
until this is resolved.** Gate D of its own; the obvious remedy (threshold
statistics over the finite subset) silently breaks the caller-validity contract
at `PrecipitateSegmentation.swift:104-107` unless it excludes non-finite rather
than invalid pixels. Owner: whether to fix or to refuse above a bound.

### Non-finite pixels ON a feature erase it silently
Same engine, same guard, different placement — and `StrainMap.component()`
writes NaN where indexing failed, which is *on* the second phase. Marking a
needle's own pixels invalid deletes it from the result with no signal: 1 needle
marked → 5 objects, 6 marked (126 px, 0.77 % of the scan) → **0 objects**.
Worse at partial coverage: 7 invalid pixels (0.04 %) leave a reassuring count
of 6 while one needle reads **21.6 px instead of 8.2** — wrong by 2.6x. No
imputation strategy recovers this; the information is gone from the input. The
honest fix is to report the imputed count, not to hide it. Owner: report or
refuse.

### The robust-sigma constant and the fill statistic are unpinned
Pre-existing, inherited with the port, found by Gate B. `1.4826 * mad`
(`PrecipitateSegmentation.swift:305`) can be changed to `3.0 * mad` — a +102 %
error in the constant that gives `Settings.thresholdSigmas` its documented
meaning — with every test green, moving mask footprints **-22 %**,
`meanIntensity` **-36 %** and one object's orientation by **23°**. Separately
`medianOf(finite)` can become the arithmetic mean with every test green. Both
are one-token mutants. Fix: one fixture asserting `robustThreshold` lands near
`median + 3 x sigma_known` on known Gaussian noise, and one assertion that
distinguishes median from mean. Not blocking — the engine is unwired.

### Dark-contrast ridges register through their flanks — added 2026-09-14
Found by the 2026-09-14 audit (an independent reader; script not retained).
`ridgeMeasure` (`PrecipitateSegmentation.swift`) keeps only the negative
Hessian eigenvalue and its comment says a dark ridge "never registers". A
dark stripe's smoothed cross-section has two negative-curvature shoulders,
which DO register and close into one ring-shaped object: a −200 dark 40 × 30
stripe on a bright field, `.needles`, gave one object with the right centroid
and `lengthPx` 53.96, `widthPx` 45.0 — the flank spacing, not the stripe.
Every needle fixture in `PrecipitateTests` is bright. Owner: decide whether
dark contrast is in scope; if it is, the measure needs the sign made explicit
and a dark fixture. Not blocking — unwired.

### A negative peak collapses an object to 1 × 1, and NaN next to a maximum passes — added 2026-09-14
Same audit, both unreproduced through the public surface. `PrecipitateSegmentation`
takes `half = 0.5 × peak` for the length/width extent; with `peak < 0` no
member clears it and the object ships as `lengthPx = widthPx = 1`, silently.
`.needles` drops it on the length floor; `.particles` has none. Reaching it
needs a component whose maximum is negative, which the threshold seems to
prevent unless `thresholdSigmas ≤ 0`, which nothing validates. And
`PrecipitateReflections.find` checks `isFinite` on the candidate only; a NaN
neighbour compares false, so a pixel beside a dead detector pixel can be a
local maximum. No fixture holds a NaN in the max pattern. Not blocking.

## Repository review 2026-09-09 — added 2026-09-09

### 119 unverified defect claims, and the adversarial pass that never ran
The whole-repo review produced 259 records and stopped mid-run; the
verification pass was still in flight. Deduplicated to 156 clusters in
[`docs/archive/2026-09-09-review/register.md`](archive/2026-09-09-review/register.md).
Three are fixed, 16 repeat and 8 may repeat the 2026-08-31 review, 8 are
already tracked here, **119 are new and none is verified**. They are claims
with a file and a line, not defects. Do not fix from the register: each one
that can move a scientific number is a Gate D of its own, and this repo has
shipped three confident wrong diagnoses. Triage before v3.0.0 should verify
the release-blocking ones only — a number moves, a clone breaks, the process
dies — and leave the rest listed. Owner: triage order.

### The three redistributed dylibs have no rebuild path
`libhdf5.dylib`, `libaec.0.dylib` and `libsz.2.dylib` are committed binaries.
As of 2026-09-09 `NOTICE` states each one's SHA-256, byte size and declared
`LC_ID_DYLIB` version, the licence texts are in `Licenses/` and ship at
`Contents/Resources/Licenses/` (verified in a built bundle, not assumed), and
`run-tests.sh inventory` fails if a dylib is unnamed in NOTICE or its hash
moves. What is still missing is a way to *make* them: they came from Homebrew
`hdf5 2.1.1` / `libaec 1.1.7` on one machine, and nothing in the repo rebuilds
them. Two consequences the hashes do not fix — a security update means hand
work, and their arm64-only-ness is now load-bearing: it is half the reason the
release is pinned to `arm64` (`tools/lib/release-arch.sh`). The `ARCHS` half of
register `D064` is closed — the pin landed 2026-09-09 and the release path is
gated since 2026-09-11. Owner: whether v3.0.0 needs a rebuild script.

## Accessibility — added 2026-09-09 by the delegated drive

**Does NOT block v3.0.0** (owner, 2026-09-11; `decisions.md`). Deferred to a
far-future release. Kept here in full because it is a live defect, not a closed
one, and because it is not VoiceOver-only: any AX client resolving labels on the
front window trips it, so it blocks any automated driving rig and it crashed the
owner's own session twice on 2026-09-08.


### Reading an accessibility label crashes the app — evidence aged off 2026-09-15, suspect named
**Known, a crash, Gate D owed, and now partly un-reproducible.** Two crash
reports of 2026-09-08 showed `EXC_BAD_ACCESS` at a stack guard page — a stack
overflow — in `AccessibilityNode.accessibilityLabel()` → `labelsToResolve` →
`resolvedRole(forPlatformElement:)` → AppKit `_accessibilityFindRoleFromProtocol`,
both times while an AX client resolved labels on the front window. VoiceOver
does exactly that, so a VoiceOver user very likely cannot use the app at all.
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
the fix is to stop layering a representation over a hand-built element. A
crash report saved out of `~/Library/Logs/DiagnosticReports` the same day
belongs in `docs/archive/`, since this item has now lost its evidence once.

### In-body controls report no accessibility label — the same bug
`Compute Mean / Max`, `Fit Detector Ellipse`, the two image-pane buttons and
every `Advanced` disclosure come back as bare `AXButton` / `AXDisclosureTriangle`
with empty title, description and value, while AppKit-backed toolbar items
(`Hide Sidebar`, `Save to Results`, `Dataset`) and the `Accelerating voltage (kV)`
field report correctly. **This is NOT missing labels in the source** — checked
2026-09-09: they are already `Button("Fit Detector Ellipse")`,
`DisclosureGroup("Ellipse correction")`, `Label("Compute Mean / Max", …)`.
Adding `.accessibilityLabel()` would restate text that is already there, so it
was deliberately NOT done. The emptiness and the crash above are almost
certainly one defect in the same SwiftUI resolution path — the crash happens
while SwiftUI tries to DERIVE a label, and these are exactly the controls whose
label never resolves. Treat as one Gate D, not two fixes.

## Verification debt — added 2026-09-08

### GitHub CI's unit job has been red since the v3.0.0 cut — added 2026-09-14
The `macos-26` runner carries Xcode 26.6, and its type checker times out on
`ContentView`'s file-importer closure ("unable to type-check this expression
in reasonable time") while the owner's Xcode 27.0 compiles it; the last three
runs on `main` (3c4b82c, 9b9949b, 6cb31a3) failed there and nobody read them.
Found by the PR #1 auto-fix. The closure became a typed method on the
`ai-analysis` branch, and Xcode 26.6 got through: the suite then ran on the
runner, 637 / 1 / 4 of 642. Every green gate recorded in `status.md` is a
LOCAL run on Xcode 27.

### The learned-detector parity fixture is a same-runtime claim, and CI has no Neural Engine — added 2026-09-14
**Verification debt.** `testLearnedPathMatchesPythonReference` failed on both
runner jobs of 05ba82a and passed here. Gate D: predicted and measured, the
same test fails on the owner's Mac with the model forced to `.cpuAndGPU` —
the fixture's heatmaps are Neural Engine numbers and the near-threshold picks
round differently off it. The test now skips where `MLComputeDevice` lists no
Neural Engine, saying so; the 98 % bars were NOT loosened. **Refuted-and-held
2026-09-14:** an independent refuter measured the CPU paths — `.cpuAndGPU`
raw picks 346/354 (97.7 %) with 8 extras (2.26 %), `.cpuOnly` 341/354 with 14;
only the two pick bars fail, accepted counts and positions pass — and
confirmed the gate runs (and fails) here when the app is forced off the ANE.
Two corrections: the fixture records compute units `"all"`, not the Neural
Engine by name; and the probe is hardware PRESENCE, so a Neural Engine that
Core ML declines to use (thermal, an unsupported op) leaves the test running
and failing rather than skipping — acceptable, but not what the skip message
implies. Residual: a CPU-written second fixture would turn the skip back into
a check, at the cost of per-path bars. Owner: whether CI should verify this.

### The published v2.5.1 artefact is universal, and Intel users get a broken app
**Not a v3.0.0 blocker — a live defect in what users can download today**
(found 2026-09-11 while closing the archive blocker, which is now fixed;
`archive/closed-items-2026-09.md`). `lipo -archs` on the shipped
`build/release/mac4DSTEM-2.5.1-pre-notarization.zip` executable is
`x86_64 arm64`, while all three embedded libraries are `arm64` alone, and
`Info.plist` invites every macOS 14 machine. `H5Reader.swift:167` **dlopens**
libhdf5 rather than linking it, so an Intel Mac runs the x86_64 slice, launches
normally; DM4/DM3, MIB and EMPAD data still load, because those readers never
touch libhdf5, while every `.h5`/`.emd` open — and every EMD export and sidecar
save (`BraggVectorEMDWriter.swift:2769`) — fails with the named modal alert
"Could not load the bundled HDF5 library" (`H5Reader.swift:44`). **Cause,
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
repeat it. **Owner decision owed:** withdraw or annotate the v2.5.1 download.

### Owed on screen from C4(c) and C7, after the 2026-09-09 drive
Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh,
configurator single-pattern preview, "No preview available") reaching the status
strip, and both Reset confirmations. **Remove IS confirmed** — the 2026-09-09
drive saw `Remove Saved Result?` with a red destructive button and a working
Cancel (`archive/v3/drive-2026-09-09.md`, finding 17). **C7's sidecar reopen is
half-answered**: the calibration round trip works — origin, probe and R–Q
rotation come back as "From session" / "Restored from session" after quit,
relaunch and reopen, and fields never set stay "Not set" (finding 10). The
disk-centre LABEL round trip is still unverified: the rig could not place a
label on the diffraction pane at all (finding 7), which is a Metal/Canvas view
that may simply not take synthesised clicks. That one needs the owner's hand, or
a rig that can. Also unreached, same cause: every `Advanced` disclosure, the
Strain / Orientation / Parallax / ptychography sub-pages, and the WS2 CIF import.

## Release-readiness review 2026-09-11 — added 2026-09-11

Eight dimensions audited by delegated readers, every finding then attacked by an
independent refuter; these are the ones that survived and that **I confirmed
myself from source**. Full dossier is this session's workflow transcript, which
is not retained — so each entry below carries its own evidence and does not
depend on it. **One correction to that review, made 2026-09-11 after the fact:**
its synthesis dismissed a refuter for citing a `website/index.html` "that does
not exist". It does exist — in the sibling `mac4DSTEM/website` repo, where
`index.html:732` does carry the GPL source offer the refuter described. The
synthesis had searched only this repository and said so too strongly, and this
file repeated it. The licence fix still stands on its own ground: GPL-3 wants
the licence text to accompany the binary, which is a different requirement from
the source offer a website can satisfy, and the bundle carried neither before
today.

### The hexagonal IPF colour key is labelled the wrong way round (2026-09-11)
`OrientationResult.swift:477-479` sets green `sqrt(tilt * (1 - fraction))`,
maximal at azimuth 0, and blue `sqrt(tilt * fraction)`, maximal at 30°.
`Crystal.swift:94` builds `latReal[0] = (a, 0, 0)` at γ = 120°, so +x is a₁ =
⟨11-20⟩ and 30° is ⟨10-10⟩. `PaneOverlays.swift:1021/1023` prints `11-20` then
`10-10` across the key, and `:1031` says "0001 red, 10-10 green, 11-20 blue" —
both read as the opposite assignment. **Established:** the colour function and
the two label strings, quoted above. **Not established:** which corner of the
drawn triangle each label sits under, and therefore whether the fix is to swap
the labels or to leave them; that needs the triangle geometry read against the
azimuth convention, and the maps themselves are not in question. If it is a
swap, a reader takes a 30° texture error off a correct map with nothing on
screen disagreeing, on WS₂, MoS₂, graphite, Ti, Zn and Mg. Reported twice before
(register `D020`). **Owner: presentation only, so no Gate D — but it must be
settled against the convention, not by eye, and pinned by a unit test asserting
`ipfColor` at +x names the index the key prints.**

### Single-slice ptychography publishes under a mode its export guard misses
`ResultExport.swift:1627` guards `analysisMode == .ptychography` alone, while
`:1478` handles `.ptychography, .singleslicePtychography` together —
established by reading both. If `runSingleslicePtychography` publishes under
`.singleslicePtychography`, the four iterative branches returning
`objectSamplingRow/ColumnAngstrom`, `engine`, `iterations` and `final_error` are
unreachable, and the phase image gets the scan step as its scale bar instead of
the object sampling — physically independent quantities
(`PtychographyPreparation.swift:110-112`). **Not established:** that the publish
path really uses the distinct case; verify before fixing. No test publishes a
ptychography product. Feature is `Advanced` and refuses on the owner's cube for
memory, so a smaller cube reaches it first. **Owner: Gate D — a scale bar is a
scientific number, and the cause is not yet established.**

### HDF5 runs under one lock now — what that costs and what is still open — fixed 2026-09-15 late night
**Known, a crash closed, a cost accepted.** Every logical HDF5 operation —
each `H5Reader` public method, its open and close, and every
`BraggVectorEMDWriter` entry point — takes `HDF5Serial` (HDF5Types.swift), a
process-wide recursive lock: the thread-safe HDF5 build done from outside,
around operations instead of API calls. The tile-streaming export releases
it before each `await` on the source actor and re-takes it per tile, so the
one path that nests reader inside writer cannot deadlock on it. Instrument:
`tools/hdf5-race-probe` — before, serial 200/200 and concurrent SIGBUS in
the first twenty; after, concurrent **3 of 3 complete** (`hdf5-race-after-
20260915.log`). No Gate D (the cause is the probe's reproducing
observation). **Gate B ran and found the claim "every call" false as
shipped:** `loadResultMap(id:)` and `loadRGBAResultMap(id:)` open the file
themselves, took nothing, and a probe variant driving them crashed
concurrently on the first attempt (SIGSEGV) while the inventory path — the
only one the probe drove — completed. Both are locked now, so is the
export's own `HDF5WriteLibrary.load()` (`H5open` is an API call too), the
probe alternates all three entry points (`hdf5-race-after2-20260915.log`,
3 of 3), and the audit rule is written on the lock: every
`HDF5WriteLibrary.load()` / `HDF5Library.load()` site sits under it. The
refuter also found `HDF5Serial` inheriting the project's main-actor default
(a Swift 6 error in waiting) — now `nonisolated`; no lock held across an
await; no deadlock path; no measurable cost (2.39 s → 2.28 s serial).
**Costs:** a caller blocks its thread for the length of one operation (a
sidecar write can be seconds); the two `dlopen`s stay two; no unit test can
crash-test this, the probe is diagnostic. **The "refuse a second open"
guard stays** as belt and braces. Thread-safety is still asserted by one
2026-08-19 `nm` inspection; `H5is_library_threadsafe` is still called
nowhere.

### The Quantitative badge consults no origin gate at all (2026-09-11)
`AppState.quantitativeStatus(for:units:)` decides the badge from a product's
kind and units alone — verified: **zero** references to `originFitIsSane`,
`originSupportsReciprocalMetrology` or `origin_reference_is_measured`. Observed
on the owner's drive: a strain map badged **Quantitative** on the same screen
where Prepare badged its origin **Not quantitative**, computed against
`origin_reference = apertureCentre`.
**The real defect is larger:** products do not carry the origin they were
computed against. Strain snapshots it and nothing reads it (one consumer,
`ResultExport.swift:516`); DPC snapshots nothing; **ACOM alone is wired**
(`ACOMWorkflow.swift:145-150`). A badge gate cannot work until that is true.
**A fix was written 2026-09-11, REJECTED by Gate B, and reverted** — it changed
no behaviour while five tests passed. Four assumptions it made are false and
must not be repeated. All of it, including the mutation table:
[`archive/2026-09-11-drive/quantitative-badge-gate-b.md`](archive/2026-09-11-drive/quantitative-badge-gate-b.md).
Ships in v3.0.0 as a stated limitation (owner, 2026-09-11), because a fix that
looks like one and is not is worse than the open defect. Gate D and Gate B owed.
### A radius-only aperture drag destroys the fitted origin (2026-09-11)
Latent, found by the Gate D refuter, and **not** what happened on the owner's
drive. `ApertureOverlay.emit` rounds the centre to whole pixels and hands the
WHOLE `Aperture` to `updateAperture`, which tests
`newAperture.centerX != aperture.centerX` (`AppState.swift:3112`). After any
origin fit or restore the live centre is fractional — (69.3133, 54.5009) on
`downsample_Si_SiGe_exp`. So dragging an inner/outer RADIUS handle, never
touching the centre, rounds it by up to 0.5 px, trips the centre-change branch
and destroys `calibration.origin` and `recordedOriginX/Y`. Distinguished from
the owner's incident by magnitude: rounding moves <= 0.5 px, his centre moved
10.884 px. The pinning test the refuter proposes is a hypothesis and must be
broken before it is trusted: restore a calibration holding the sidecar's origin
maps, set the aperture to `meanOrigin`, drive `emit` with an outer-radius-only
change, assert `calibration.origin` survives. Owner: cheap, Gate D (a number
can move).

### "Computed this session" reports what EXISTS, not what was computed (2026-09-11)
This is what the owner actually reported. The two rows are bare predicates —
`product("Origin calibration", done: ...calibration.hasFittedOrigin)` and
`done: ...hasRotation` (`WorkspaceInspector.swift:563-565`) — so a session
restored from a sidecar shows both green having computed nothing. The owner's
session WAS restored (the sidecar reproduces his 9.72 px and 3.74 px exactly),
so his green ticks were restored, not computed, and the tick went grey because
the origin was cleared, not because a computation was undone. The label is the
defect. Owner: presentation only, neither Gate D trigger applies.

### Moving the detector destroys the origin fit with no durable warning (2026-09-11)
Gate D closed: `updateAperture`'s centre-change branch is doing exactly what it
was designed to do (Gate B note, 2026-08-28), and the design is the problem. The
aperture centre silently IS the calibration, and after a fit the aperture sits
on the fitted mean — 10.9 px from the pattern's visual middle on this dataset —
which is precisely what invites a user in an imaging workspace to "correct" it.
The only notice is a transient `statusText`; the undo (`canRestoreFittedOrigin`)
is real but sits inside `DisclosureGroup("Fit diagnostics & advanced
correction")` with `@SceneStorage showsDiagnostics = false`
(`PrepareSettings.swift:30,120-128`) — collapsed by default and the last row of
a different workspace's sidebar, as the 2026-09-01 drive already recorded. The
app gives no indication that moving the detector destroys the origin fit until
after it has. Owner: decide whether a confirmation, a non-transient banner, or
refusing to clear without consent.


### A red real-data gate names the symptom, not the cause (2026-09-09)
`compare.py`'s `fail()` raises `SystemExit`, so a run stops at the first
mismatching field of the first mismatching file. On 2026-09-08 it printed
`diskSampleCandidateCounts` and never reached `diskProbeRadiusPixels`, where
the change was, nor the cubes after it — and the one golden verdict in the log
was read as three, because the harness's own `PASS: <file> <shape> in <t> s`
lines look like verdicts. Wanted: collect every mismatch, fail once. Confirmed
by the Gate D refuter. `comparator-test` gates this file too. Owner: cheap.

### Real-data numbers are pinned by one harness only `all` reaches (2026-09-09)
`tools/real-data-acceptance/run.sh` says `all` "is the only one that reaches
this harness at all". `ba6360d` moved a measured probe radius on 2026-09-05,
`scientific` stayed green three days, and by the time `all` ran, 43 commits
stood between change and symptom — the entry written from it blamed two
innocent ones. Options, uncosted: add the harness to `scientific` (which
already reads the cubes), or gate science-lane commits on it by hand.
Main-only: `ba6360d` postdates v2.5.1, so no shipped build carried it.

### The acceptance harness pins peak COUNTS, never positions (2026-09-09)
Gate D refuter: `AcceptanceReport` (`main.swift:6-22`) has no coordinates, so a
change moving every peak while preserving the count is invisible. On `ba6360d`
all 36 `downsample_Si_SiGe_exp` peaks shifted 0.005-0.02 px and one
`calibrationData_bullseyeProbe` peak was SUBSTITUTED — (114.2198, 194.8632) ->
(140.6368, 196.8596), ~26 px — count unchanged at 11, harness silent
(`drift/refuter/peak-position-diff.txt`). Likely two near-threshold
noise peaks trading places (the noise item below), not a defect; the defect is
that the gate cannot tell. Owner: a checksum needs a tolerance — a design pass.

### The one-peak warning is below the fold, and Strain unlocks without it (2026-09-09)
Driven on `polycrystal_2D_WS2.h5` (`archive/v3/drive-2026-09-09.md`, finding 16;
shot `B33-ws2-detect-done.png`). `Detect All Disks` completed to a green status
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
BEFORE the two count rows (`MapSettings.swift`); unverified on screen. Still
open, and the harder half: `Strain` moved from `!` to enabled on a
median-1 result, because readiness gates on Bragg vectors EXISTING, not on being
usable. The driving agent first reported this as "nothing distinguishes it from
a healthy run"; that overstated it and the review corrected it — recorded so the
next reader does not re-derive the wrong version. Owner: presentation plus a
readiness question; no Gate D (mechanism established by reading the two call
sites, no number moves).

### Bullseye disk detection accepts noise — two of three fixes landed 2026-09-05, drive owed
Owner playthrough 2026-09-01 (`calibrationData_bullseyeProbe.h5`). Gate D on
py4DSTEM truth (`tools/bragg-spacing-probe/bullseye-kernel-truth.py`): (1) the
probe-size estimator reads the ring-shaped probe at 7.4 px where the ring ends
at ~10–12; (2) the trench kernel at THOSE radii leaves the beam never
brightest — at the true radii it works as well as flat, so (2) is (1) in
another guise; (3) correlation noise is 2–5 % of the beam peak, so the 0.5 %
default keeps ~130 noise peaks/position. LANDED: flat mode + Use File's
Probe, parity 878/878 and 164/164 with py4DSTEM's flat route (`status.md`).
OPEN: (1), an outer-edge probe size for structured probes (it also feeds the
origin window — its own Gate D). Owner: drive Map ▸ Bragg disks on the file
with Flat + Use File's Probe at Min relative intensity ~0.05.

### Origin-fit gate has two unresolved holes (2026-09-05)
(a) closed 2026-09-05: `probeSize` refuses (nil, `probeNotMeasurable`) when
no finite pixel is above zero or no mass clears the threshold; non-finite
pixels are skipped at every step; the median matches `np.median` for even n
(`ProbeSizeTests`; the refuter's +inf escape closed, two mutants caught).
(b) Which statistic gates `originFitIsSane` is open: full-scan RMS (current)
cannot see bias; the robust/kept-set residual tried 2026-08-28 was reverted —
it passes a 15 px-displaced fit at 9.94 px. (c) The trimmed fit is blind to
spatially clustered failure and contamination ≥ 50 % (a 40 px-off quarter of
the scan gives 100 % kept, 20.6 px error; an exactly bimodal residual zeroes
the MAD guard). Owner: a design pass — no statistic proposed yet separates
displacement from contamination. `docs/q-calibration-design.md`.

### The origin's coarse block seed lands on the wrong blob on noisy cubes (2026-09-05)
Gate B refuter (`q-calibration-design.md` §9,
`tools/origin-fit-diagnostics/origin-kernel-twin.py`): against py4DSTEM's
Gaussian-argmax seed, the app's block-sum seed puts 28/169 positions of
`downsample_Si_SiGe_exp`, 29/195 of `Particle_1` and 2/169 of `COPL` more
than 1 px away — unchanged by the iterated window, which cannot leave a
wrong block (a DEVIATION recorded in the kernel header). Clean cubes: 0.
Trap: the plane fit's trimming hides most of these, so the fitted origin
looks fine while `excludedFraction` carries them. Owner: a design pass on
the coarse step (Gaussian-filtered seed, or a coarse-to-fine window) before
the origin-fit holes (b)/(c), which it would move.

### CIF import can silently accept a wrong crystal (2026-09-01)
(a) A non-P1 declaration with a PARTIAL ops list still imports the wrong
cell (`verifyFamily` can pass it — Gate B refuter escape E2, 2026-09-01,
recorded not fixed; the missing/identity-only case is guarded). Trap: needs
a 230-entry IT-number→group-order table the importer deliberately lacks —
cheap mitigation, new scope. (b) closed 2026-09-05: the ACOM recipe step
records `material_fingerprint` (`CrystalModel.contentFingerprint`, FNV-1a
over cell, symmetry and basis) for imported models and `resolveMaterial`
refuses by name when the session's same-named import differs; pre-key
records still resolve by membership (`ReplayPlanTests`, `CIFImportTests`).
Owner: (a) unclaimed, Gate B when picked up.

### ACOM orientation/export coverage gaps (2026-08-31)
Found in W4b Gate B; the shipping numbers are believed correct but nothing
gated would catch a regression. (a) Exported Euler angles are labelled
py4DSTEM/orix-compatible but differ by frame rotation `P` — median 38.55°
misorientation if compared naively; math right, label wrong. (b) The
projection convention (`OrientationPlan.project`) is verified three
independent ways, but every gated ACOM harness builds its own peaks through
the function it tests, so two frame-mutation bugs stay green — no analytic,
non-self-referential fixture exists yet. (c) The exported orientation matrix
can decouple from the reported template index unnoticed. (d) Unpinned: an
additive radial offset, the reliability distinctness test, `intensityPower`.
Owner: (a) relabel-vs-convert decision then Gate B; (b)–(d) Gate B.

### Q-calibration scale defects on real crystals (2026-09-02)
(a) closed 2026-09-05 by Gate D + B (`q-calibration-design.md` §8): the
per-position minimum was the same spoke at 99 % of WS₂ positions — a 0.26 px
origin-fit offset, which a symmetric cluster MEAN cancels; the cluster reads
18.902 px against 18.901 from the independent 11-20 shell; `estimate` now
averages the same-shell cluster (14 mutations, 79 harness checks). Residual,
folded into (b): on a single crystal with a 2.4 % Friedel-pair asymmetry
(sim_Au) the band truncates clusters and neither estimator is shown to be
truth. (b) The reference-shell pick has no l-filter or visibility filter; on
2H-WS₂ it selects (0002), which a [0001]-zone specimen never shows —
predicted mis-scale 2.26×, silent; at that scale the correlation score
HALVES while median `reliability` RISES, so no fix may lean on reliability
to choose between scales. Owner: (b) its own design pass.

### Twisted bilayer graphene finds only the beam at defaults, at either reference (2026-09-05)
Observed (`det-experiment-20260905.log`): 10 201 positions, one accepted
peak each, with `relativeToPeak` 0 AND 1 — so the relative threshold is not
what removes the disks; the funnel is one local maximum before any threshold
(probe r 25.3 px, spacing 16, edge 5 on a 128 px detector). Not diagnosed:
whether the 25-px synthetic kernel's correlation has a single maximum, or
the edge boundary/spacing swallow the ring at ~38 px. Owner: unclaimed; a
Gate D with the per-pattern funnel on one position.

### #18 — training-dataset campaign can't reproduce the app's Si_SiGe strain (2026-09-02)
Mechanism resolved: the campaign's fitted mean origin is ~7 px off centre
(non-quantitative fit), which poisons `estimateLatticeBasis`'s clustering
scale; the app's own gate rejects that fit and falls back to the true
detector centre. Latent app-side risk: a genuinely off-centre beam with
`meanOrigin` nil would fail the same way. Two candidate fixes, neither made
(science changes, own Gate B): floor `minRadius` at the probe radius or
scale it with fit quality; or have the campaign adopt the app's origin
gating. Full diff in the archive.

### No automated visual baseline (2026-08-17)
Every acceptance run is numeric-only; the owner driving the app is the only
evidence anything "looks right" — say who drove it and when. Driving has
caught defects with every harness green (colormap control missing, readiness
row self-contradicting, three more in the clean-account run, five sessions
running in September). The retired checklist's trap notes are in
`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`. Never seen on
screen: the six `status.md` rows marked unverified, light appearance, every
divider, a real load cancel, the bounded promote run. Owner: C3, one sitting.

### macOS 14–25 is supported and has never been run there (2026-09-04)
Floor lowered 2026-09-04 (`decisions.md`): `MACOSX_DEPLOYMENT_TARGET` 14.0 in
all four configurations, `Package.swift` `.macOS(.v14)`; two cosmetic symbols
behind `#available` (`ToolbarSpacer`, `.pointerStyle(.columnResize)`); macOS
13 is unreachable (`@Observable`). Established by building at 15.0, 14.0 and
13.0. Published as macOS 14+ from v2.5.1: a true statement about the
artefact's floor, not a claim every version was exercised. **The live gap:
no machine or VM here runs below 26**, so 14–25 is compile-verified and never
executed; a VM would close it and needs ~40 GB. `tools/package-test`'s floor
assertion is derived from the project, so it no longer flags a floor change.

### Residency `.automatic` cannot be re-measured without a second machine (2026-08-19)
Dropped by decision (v2 S3), not dormant — do not set
`ResidencyAdmission.measuredWorkingSetFraction`. The three checked-in
training cubes top out at working-set ratio 0.19 on this machine; no knee
exists in that data. A second-machine sweep is the only thing that could
reopen it, and if two machines disagree the rule needs a second term.

### An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07)
Agent drive, C3 (`drive/shots-c3/b2-qr-unset-bug.png`): on the COPL
cube (Q pixel scale green "From file 0.156828"), typing `0.2` into Prepare's
Manual field entered nothing (this locale wants `0,2`; the period was dropped
silently), and Return on the now-empty field flipped the row to "Not set /
Reciprocal dimensions remain in pixels" and the scale bar from `0.5 Å⁻¹` to
`5 px`. `0,25` typed afterwards worked live. Two things to establish before a
fix (Gate D): why a period is rejected rather than parsed, and whether an empty
manual entry should clear the file value or restore it. Owner: `/diagnose`.

### C3 drive leftovers: presentation observations (2026-09-07)
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
Still unprovoked: staleness (f), and "Fit Detector Ellipse" on the demo ending
in "residual is too large (0.247)".

### Two diagnostic harnesses gate nothing (2026-09-02)
`tools/bragg-spacing-probe/` and `tools/residency-sweep/` both need
gitignored multi-GB data and stay diagnostics only — not a gap to close,
a standing limit to remember before citing them as coverage.

### Learned detector above 256 px: the probe channel's anchor (Gate B, 2026-09-08)
`LearnedDiskDetector.detectAll` crops the probe channel clamped-centred for
every window while the pattern windows sit at `windowOrigins`, so on a
detector above 256 px the probe and the pattern do not share one anchor —
the opposite of every training input (`simulate.py` "the SAME anchor for
both"). The >256-px path has no Python reference (`evaluate.py` never tiles);
its tests are Swift against Swift. Nothing shipped is above 250 px. Owed: one
synthetic >256-px detector scored under clamped-centred vs per-window-anchored
probe placement before the windowed path is quoted as measured.

### #30 — origin calibration over a NAS runs at ~3 MB/s (2026-08-06)
Investigation owed; nobody has measured it since.

## Known, scoped, not blocking

### Parallax and ptychography are unrunnable on the owner's Mac (2026-09-11)
Owner drive, `051_STEM_SI_preprocessed_unfiltered_bin_4_20260629.h5` — a
128x128 scan of 64x64 patterns, **268.4 MB** as f32. Both Advanced Phase
features refuse:
`Parallax KDE needs about 8,16 GB, above the 1,07 GB working limit` and
`Single-slice ptychography needs about 11,55 GB, above its 1,07 GB limit`.
**The refusals are correct behaviour** — they name the number, the limit and the
remedy ("Reduce the factor or crop/bin the dataset first"), and nothing was
computed against a bad budget. Two of the app's failure paths are therefore
driven and good.
**What is NOT established** is whether the estimates are right: 8-11 GB of
working set for a 268 MB cube is a 30-40x ratio, and nobody has checked whether
that is the algorithm's true cost or an over-estimate that refuses work the
machine could do. That is a Gate D of its own (a number governs whether a
feature runs at all), not a tuning knob to raise.
Consequence for the release: Parallax and single-slice ptychography ship
**undriven on real data** and must be described that way in the release notes.
The owner has postponed testing them to a machine with more memory; blocking a
release on hardware he does not have is open-ended, so this is scoped, not
blocking (owner, 2026-09-11).


### Fabricated provenance on pre-2026-08-18 sidecars (2026-09-02)
`AppState.swift:2854,2867` do `snapshot.loadSpecification ?? .fullExtent` —
a sidecar saved from a cropped view before that attribute existed is now
asserted full-extent rather than unknown. Both prior reproducers were
overwritten by later driving sessions; demonstrating it again needs a
synthesised sidecar, not a training-set one. Unowned, belongs with the
trust fixes.

### DM4Reader silently reads the whole file into RAM off non-local volumes (2026-09-02)
`.mappedIfSafe` (`Core/Data/DM4Reader.swift:97`) declines to map on any
volume failing `MNT_LOCAL && !MNT_REMOVABLE` (confirmed by S9b: every
external disk, every disk image even on internal SSD, all smbfs) and
silently falls back to a full anonymous-memory read — held for the whole
session. `H5Reader`/`VendorRawReaders` are immune (hyperslab/seek reads).
No fix landed; `.alwaysMapped` trades this for a SIGBUS risk if the
volume disappears mid-read. Needs a CI fixture (a disk image on the internal
disk reproduces `MNT_REMOVABLE` with no external hardware). **The original
2026-08-18 8 GB-machine death that motivated this is still NOT explained** —
the mechanism is real and worth fixing but not established as that
incident's cause. Owner: a later session, Gate B.

### The sidecar reader has D003's missing guard too — not fixed (2026-09-09)
`BraggVectorEMDWriter.swift`'s attribute reads carry the same defect D003 fixed
in `H5Reader.swift`: `H5Aread` reads a whole attribute into a buffer sized for
one value. This is the 2026-08-31 review's `core-data-01` (**confirmed, high**
— "assume scalar variable-length storage without checking the file type or
extent"), which D003 has now supplied the runtime evidence for, and the new
register's `D029`/`D053`. Left alone deliberately: the owner scoped this
session to D002 and D003 only. The fix is the same three lines —
`H5Aget_space` plus `elementCount(spaceID:) == 1` — and the measurement is
already done (24 bytes into 8; 32 into 9). Owner: a v2.5.x patch session.

### Ptychography pads both object axes unlike py4DSTEM — deliberate (2026-09-09)
py4DSTEM's `_calculate_scan_positions_in_pixels` pads BOTH position axes by
`region_of_interest_shape[0]/2` (`object_padding_px = (float_padding,
float_padding)`, then `[0][0]` and `[1][0]` — both index 0). This app pads each
axis by its own half-extent, which differs only on a non-square detector. Kept
as it was when D002 ported the rest of that function, and carried as an inline
`DEVIATION`: correcting py4DSTEM's quirk was outside D002's scope and would
have moved a number nobody asked about. Open question, not a defect: whether
py4DSTEM intends it. Owner: decide when ptychography is next driven.

### Scan-fastest DM4 detector pair may be transposed — Gate D owed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps the tags as
`[Rx, Ry, Qy, Qx]`, a pattern 480 wide × 448 tall. DM's convention, which the
same code applies to the scan pair (survey `Spectrum Image Rect` 202 × 895 px
= 17 wide × 77 tall confirms it) and to detector-fastest files, is x first:
dim 3 = 448 = width. Nothing in the 2026-09-05 commit justifies the
asymmetry; its fixture was generated from the code's own model. A transposed
pattern silently flips strain axes and the R–Q rotation. Owed: the owner
reads the pattern's width and height in GMS. If 448 wide: flip
`DM4Reader.scanFastestStrides` and the scan-fastest shape line, then pin a
checksum from ncempy's raw array on the real file. Residual: honour newer
GMS's `Meta Data.Data Order Swapped` tag (LiberTEM reads it first).

### The open/promote unwind is sixfold, and Cancel can vanish mid-load (2026-09-04)
Six begin/finish brackets, not three: `openFileAsync`, `commitPendingLoad`,
`promoteToFullExtent`, plus `selectDataset`, `openManualPath` and
`openDemoFixture` with no cancel handling at all. The old hazard 1 is
refuted — no suspension point sits between the last cancellation check and
`finishDatasetLoading` on any path (`AppState` is main-actor isolated,
`project.pbxproj:492`). Hazard 2 is worse than recorded:
`finishDatasetLoading` (`AppState.swift:2800`) unconditionally nils
`datasetLoadCancellation` and clears `isLoadingDataset`, both of which
`canCancelDatasetLoad` (`:1162`) depends on — with two loads in flight the
FIRST tail to finish disarms Cancel for the second. Unification alone is not
the fix; no fixture exercises these branches, and that is the precondition.
Owner: whichever session next touches any of the six.

### Promote/replay residuals (2026-09-02)
(a) Owner design question: should promote carry the scan position across,
or land at (0,0) as today? (b) Fitted origin maps are crop-sized and dropped
by the full-extent restore's shape check, so a promoted recipe recorded
against "calibrated origins" refuses — expected behaviour, not a bug. (c)
Parallax/ptychography are deliberately NOT in the replay record (not
bit-reproducible); folding them in is its own session. (d) A user-initiated
analysis mid-replay steals the Cancel control from the replayed step. (e)
Per-kind replay contracts live in three places (record/parse/apply) held
together by tests, not structure — co-locate per kind when the next kind is
added.

### Recents/window-state edge cases, both low priority (2026-09-02)
Each window's `AppState` holds its own `RecentDatasets` snapshot over one
`UserDefaults` key, so a second window's save can clobber the first's
entry (single-window use, the shipped reality, is unaffected). Separately,
`openRecent`'s failure path removes a dead entry from the list but leaves
"Reopen" dead-ending in "No recoverable dataset." Both unclaimed.

### Legacy `.icns` tops out at 256 px — reopened 2026-09-07 (the floor is 14)
Called moot on 2026-09-04 because the floor was 26; the floor is 14 since
v2.5.1 (`decisions.md`, 2026-09-04), so the reasoning inverts. On macOS 26+
Get Info, Quick Look and large Finder icon views render from the `.icon`
source; below 26 they render from the legacy `.icns`, whose largest
representation is 256 px, so a 512/1024 px icon view shows an upscaled icon
there. Cosmetic; never observed (no machine here runs below 26). Fix: a full
legacy PNG set (16–1024 px, @1x/@2x) in the `.icns`. Owner: unclaimed;
verify on the first report from an older system, or in the VM above.

### Resident/streaming residuals (2026-09-02)
`releaseResident()`'s "freed" claim is asserted by a derived byte count,
never a measured one — a leaked `MTLBuffer` is invisible to every test.
`TiledDiskDetection.detectAll` still stages each tile into a fresh
`MTLBuffer` (out of S18's bounded staging-copy elimination). Resident
cancellation is 2.5× coarser than streaming (one indivisible dispatch) —
academic until something under `mac4DSTEM/` requests `.resident`, which
nothing does today.

### Toolbar Cancel button renders wrong during a run — cosmetic, not blocking (2026-09-04)
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

**Amended 2026-09-12.** The status bar's own Cancel was a `.controlSize(.mini)`
version of the same mistake and is now a borderless `xmark.circle.fill`, so
this toolbar item is the ONLY Cancel left with a rendering complaint against
it. What that fix established and this entry can now use: `.mini` sets a 9 pt
label (measured) and a `Text`-labelled button is a flexible child that a tight
row squeezes — the `C…` collapse was reproduced at 1080 pt. The remedy that
worked there is the same glyph-plus-`.help()` pair; the owner's call on whether
the toolbar wants it is still owed, and is now a smaller question than it was.


### Sidecar/session UX residuals (2026-09-02)
Recents-row location labels unverified on screen (F1.1c). A sidecar
retarget made before any save survives only until the next dataset
change. Repeating "Save Session Sidecar As…" can prefill a doubled
`.h5.h5` suffix. Pre-S4 calibration-only sidecars remain unrecognisable
(extension/open-panel-filter half is an owner decision). The configurator's
beam proxy has no "load anyway" override (owner question; unifying it with
`CalibrationReReference`'s gate is a deliberate non-unification,
`Session/SessionGates.swift`).

### DPC's banner contradicts its badge — entry corrected 2026-09-04
Three claims here were wrong. **Mechanism:** the fall-through is `.relative`
(`AppState.swift:761`), not `.quantitative` — only named families are
quantitative (`:759`). Still true: it pattern-matches strings and consults no
calibration readiness, while `idpcPhysicalCalibration` consults three gates.
**Carrier:** not XMP — the PNG `Description` JSON chunk and the status burned
into the caption's pixels (`ResultExport.swift`). **Headline:** iDPC's badge
and banner AGREE; the contradiction is `PhaseSettings`' always-shown
qualitative banner over `dpc_magnitude` / `dpc_angle`, which
`quantitativeStatus` calls quantitative. Before any fix: status is frozen at
publish and at persist and preferred over re-derivation on restore, so a
change corrects neither existing sidecars nor exported PNGs, and there is no
version field to migrate on. Owner: the trust-fixes session; a judgement call.

### Misc unclaimed, low priority (2026-09-02)
Load-cancel: F1.1d (cancel a real load on screen) never driven; resident
buffer/cropped-view teardown unpinned. #17a: the wider pane-arrangement
question (design decision, reverted on sight once). Detector-bounds
convention sweep: whether other tests use an index convention for
continuous positions besides the one already fixed, nobody has checked.
HDF5 multi-dataset axis order is assumed (`[ry,rx,qy,qx]`), not checked —
only Ry↔Rx/Qy↔Qx transpositions would be silent, and the app names the
dataset it picked. `MAC4DSTEM_ACOM_SCALE_OVERRIDE`: the sidecar keeps the
estimate scale, not the override scale the map was matched at (design call).
Virtual-detector mask boundary (`r² < rOut²` vs `<=`) is unpinned against
analytic truth. #31 `validationIssues` is O(n²) in a SwiftUI view body. #32
`isSymmetry`'s bijection check has no fixture coverage.

### The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04)
`NSGenericException` from `_postWindowNeedsUpdateConstraints`, through
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. **The
rule, demonstrated 2026-09-04: nothing inside a split's hosted content may
repeatedly change its own minimum size.** SwiftUI's split machinery loops on
it, and `NavigationSplitView` and `.inspector` are splits too. `.fixedSize()`
on text whose string changes is the easiest way to do it by accident, and it
only fires on a dataset big enough for an operation to tick — every
demo-fixture launch was clean and a real one died. Two sites, both in the
status bar, both fixed. Full diagnosis and the refuted `HSplitView`
conjunction: commits `e608dbd`, `27de9bb`; the S17 record is archived.
Residuals: n=1 each way against a fault once called intermittent; the
inspector's Performance rows still tick per second. Owner: unclaimed.

### `PaneSplit` residuals from the refuter (2026-09-04)
(a) header overflow and (c) the divider resetting to centre are closed and
were seen on screen 2026-09-07 (`shots-c3/a3b-narrow.png`, `a4b-divider-back.png`).
(b) **The image floor lapses
below 2× itself**: the fraction saturates at 0.5 under ~360 pt of usable
width, and UI declares no detail-column minimum where the retired AppKit UI
had `SplitViewPolicy.detailMinimum` = 360. SwiftUI offers no detail-column
minimum short of the window's own floor, and announcing one from inside the
split is the constraint-loop shape; recorded, not made. Owner: with the
owner's drive (C3).


### Manual Q and R pixel scale cannot be corrected once entered — fixed in code, drive owed (2026-09-04)
Owner, on `downsample_Si_SiGe_exp.h5`: enter a manual Q or R pixel size, the
row turns green and the field disappears with it. A wrong R scale silently
rescales every real-space axis, scale bar and export, so this is a trust
defect. **Code fix 2026-09-05** (second cut; the first locked a restored
session value and an imported Q, and committed two red tests against
itself): `PrepareSettings.shouldShowManualScaleEditor` keeps R editable
always and Q editable for every provenance except measured-in-app, with the
hover text naming the value an entry replaces; Prepare and ExportSheet share
it, three unit tests pin it. Owed: the owner drives both surfaces and sees
the fields stay visible and editable after the row is green.

### `calibration.*` identifiers exist twice while the export sheet is open (2026-09-04)
`ExportSheet` re-renders the readiness rows, so `calibration.readiness`,
`calibration.item.*`, `calibration.rScale.filenameConflict` and
`calibration.action.originProbe` are each emitted by both it and
`PrepareSettings` while the sheet is up. Harmless today — nothing queries them
at runtime — but it would defeat any future UI test that addresses a readiness
row by identifier. The old app had the same collision. Owner: unclaimed.

## Code hygiene

### `tools/free-space.sh` still spells shared path knowledge three times (2026-09-04)
Fixed 2026-09-04, the misreporting half: it prints the two volumes the
preflight gates (`$ROOT`, `$TMPDIR`), answers "will the gate run?" against the
8 GB floor, and surveys the regenerable roots outside its two (DerivedData,
`ModuleCache.noindex`, `CodingAssistant`, `.build`). Report-only;
`guard_path()` untouched, and `build/release` (notarized, stapled images)
prints as PROTECTED. Residual: the temp prefix is spelled by producer and
reaper separately and the MCP root is hardcoded (the 50 untagged
`mktemp -d` sites were tagged `mac4dstem-<harness>` in C2, 2026-09-07). A
`tools/lib/` constants file is deliberately NOT taken — every gate sources
through `run-tests.sh` under `set -euo pipefail`, so a bad line there kills
the whole harness. Owner: whoever next touches `run-tests.sh`.

### Acceptance-gate test-infrastructure residuals (2026-09-02)
`real-data-acceptance/run.sh` sources `tools/lib/sources.manifest` since C2
(2026-09-07). Its empty-glob SKIP exits 0, so a machine with
zero datasets passes the gate; whether it should consult `expected.json` is
open. The 15 s acceptance budget gates the 4 pinned datasets only —
pin-or-refuse vs the advisory `UNPINNED` line is an open call. `abs_tol=1e-3`
on virtual-image fields exceeds `polycrystal_2D_WS2`'s whole dynamic range
(5.3e-4); not tightened, but the fixture carries a WS₂-magnitude case so the
boundary is testable. Comparator: `rel_tol` on `diskProbeRadiusPixels` is
inert below 50 px; `if not actual:` is unkillable by any mutation. The runner
aborts at the first red harness, so it cannot say how many are red.

### `.fixedSize()` in `UI/`, audited 2026-09-04 — one armed site, contained
12 bare call sites against the constraint-loop rule above (an unanchored grep
says 16; four are comments *about* it — use `grep -rn '^\s*\.fixedSize()'`).
**One is armed**: the zoom badge (`ImagePanes.swift:587`, inside
`zoomModeBadge`): `ZoomPan.liveZoom` is written on every magnify event, the
digit count moves (×9.9 → ×10.0 → ×100.0), the value is unclamped mid-pinch,
and the badge appears and disappears across ×1.0 — a `.fixedSize()` child
inserted and removed repeatedly in one gesture. The rest are literals or
change once per published product. **Not fixed, deliberately:** a reserved
slot closes the string-width channel and NOT the appears/disappears one.
**Not urgent:** `PaneSplit` gives each pane `.frame(width:)`, which
terminates its minimum, and none of the 12 is in the one `.safeAreaInset`
where both crashing sites lived. Owner: with `PaneSplit` residual (a).

### Harness type replicas of `Aperture` (2026-09-02)
Every runner sources `tools/lib/sources.manifest` since C2 (2026-09-07; the
inventory fails one that does not). What remains: `Aperture` is declared in
`App/AppState.swift`, and scientific harnesses carry their own copies that
would still compile and pass if the app's gained a field — it belongs in
`Core/`. The app build is the only real gate for actor isolation
(`tools/load-spec-test` compiles nonisolated; the manifest's isolation flags
buy visibility, not enforcement). Owner: the next `AppState` extraction (C5;
the first, the fit overlays, landed 2026-09-07).
