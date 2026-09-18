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

## v3.1 origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay + clustered case owed

`OriginMaps.originValidity: [Bool]?` carries the robust trim's per-position `kept` mask (disclosure only, no fitted number moves; ADR 033, `docs/v3.1-calibration-preregistration.md`).
**Status:** D4 count landed (`PrepareSettings.positionsUsedValue`, unit-tested M4) but **unverified on screen**. Step-3 trim-sweep PASSED on 4 cubes: excluded 0.6–15.7 %, `maxGap` 1–5 — Si-SiGe (15.7 %, scattered) vs sim_Au (10.6 %, `maxGap 5`, clustered) exclude alike but differ spatially. D1/D2 stay at defaults, overrule on sight.
**Owed:** the spatial validity overlay (origin fit over the scan grid, excluded positions greyed via `DisplayedProduct.validityMask`) is a larger follow-on, not built. Owner: unclaimed.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

## Owner drive 2026-09-17 — added 2026-09-17

### Sidecar save "could not remember access" was a dev cdhash mismatch; the live residual is the message — CONFIRMED 2026-09-17
2026-09-17 00:26:37: bookmarking the just-saved sidecar threw "The file couldn't be opened". Cause, from the
unified log (`docs/archive/audit-2026-09-16/sidecar-bookmark-cdhash-20260917.log`): `ScopedBookmarkAgent`
returned -67034 `errSecCSStaticCodeChanged` because the ad-hoc Debug bundle in DerivedData was rebuilt under
the running instance. **Confirmed a dev artifact, not a product bug**: after a fresh build nobody rebuilt under,
Save persisted and the sidecar restored (owner reproduction, log 00:47:43). H1 (sandbox extension) and H3
(wrong URL) refuted; no Gate D (mechanism proven by a reproducing observation). **Residual FIXED 2026-09-17:** `AppState.errorDetail` names the domain, code and underlying error
(where -67034 lives); applied to the sidecar-grant and the recent-file "could not remember access"
messages. Test `ErrorRoutingTests.testErrorDetailNamesDomainCodeAndUnderlyingCause`, broken first
(bare `localizedDescription` → red on domain/code/underlying, `bf2-mut-20260917.log` exit 65; real
and final exit 0). Item closed.

## Deviation-note audit 2026-09-17 — added 2026-09-17

Read-only fan-out over 43 Core/ ported sources (CLAUDE.md hard rule: port deviations get
an inline `DEVIATION` note). Two files got a class-a note inline where a same-file
justification already existed untagged (`DiskDetection.swift`, `OrientationMatcher.swift`),
plus `ProbeKernel.swift` and `StrainMapping.swift`. Five class-b gaps were found. **Four were
pure documentation gaps and got their inline `DEVIATION` note 2026-09-17** (each verified
against source, re-checked by an independent refuter): `EllipseCalibration.fitAmorphousRing`
(LM start point differs), `ParallaxPreprocessing` probe angles (milliradian storage, converted
back to radians in every science consumer), `OrientationPlan` per-ring mean (py4DSTEM's is
commented out AND coarser — a whole-image mean, not per-ring), `ScatteringFactors` (no
`units="VA"` branch). The fifth is a behaviour deviation, not a doc gap, and stays open:

### Parallax default bin schedule runs the finest bin once; py4DSTEM's runs it twice — Gate D diagnosed 2026-09-17, fix owed

`ParallaxAligner.defaultBinSchedule` (`ParallaxAlignment.swift:152-166`) returns `[4,2,1]` for a diameter-5 disk; py4DSTEM's `reconstruct` default (`num_iter_at_min_bin=2`, `parallax.py:1141,1278-1281`) appends one repeat of the finest bin → `[4,2,1,1]`, so every product gating on `isComplete` (`ParallaxAberrationFitting:134`, `AberrationCorrection:82`, `SubpixelReconstruction:96`, `DepthSectioning:99`) computes one refinement pass short.
**Diagnosed 2026-09-17** (refuting observation confirmed: `errorHistory` holds one bin-1 entry, no `numIterAtMinBin` knob exists). **Not yet run:** the head-to-head experiment (py4DSTEM's `BFReconstruction.reconstruct(reset=True)` vs the port over `[4,2,1]`, reporting max-abs `totalShifts`/`alignedBF`/final-error diffs). **Trap:** `tools/parallax-alignment-test/reference.py:354-357` hard-codes the schedule without the repeat, so the green test can't catch this.
**Science, Gate D before any `ParallaxAlignment` change.** Owner: unclaimed.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

## T1 [0 -4 1]: the not-indexed pairs are per-peak detection noise, not origin or reference — measured 2026-09-17

**Resolved by direct measurement (independently refuted):** the 252 not-indexed T1 positions each leave 2 survivors after matrix removal (52.1 % of 6358) forming one real `|q| ≈ 0.462–0.470 Å⁻¹` Friedel pair (the {200} ZOLZ reflection, `|g|=0.4668`) that sits 2.5–5.2° off antiparallel (`|u+v|` = 0.021–0.043, just over the 0.02 pair radius) — so `containsFriedelPair` returns false and the floor-3 rejects them. The T1 reference length is correct; do NOT change it.
**Gate D experiment (run 2026-09-17):** a per-position direct-beam origin sits 0.04 px (0.0007 Å⁻¹) median from the global origin (stable, not wandering) and recovers only 24 of 252 (10 %) — **the residual is per-PEAK centroid noise on the weak {200} spots (~0.5–1 px), not a common-mode origin error.**
**py4DSTEM head-to-head (2026-09-17):** py4DSTEM's own ACOM+`CrystalPhase` on the same peaks labels 100 % of T1 positions Al — validates the matrix-removal design, not a lever to adopt.
**Remaining levers, each its own Gate D:** better centroiding of the weak spots, loosen the pair-antiparallel tolerance (recovers ~half at rising Al-false-positive/0.015-cliff cost), or accept detection-limited T1 recall. Owner: which lever, if any.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

## resultexport-split, prepared and parked — added 2026-09-17

Audit 3.2 row 6: `Support/ResultExport.swift` (1 939 lines before this session, 12 of 27 funcs untested) is being split by export kind, in small green-boundary commits, each verified before the next.
**Landed, self-verified only — NOT Gate B-reviewed (STOP before self-approval):** `Support/ResultExport+Rendering.swift`, the pure rendering helpers with zero `AppState` dependency, diffed byte-identical against the pre-split backup except three `private`→internal widenings. Build exit 0 zero warnings, 6 rendering/provenance unit tests pass, `inventory` AppState+ResultExport **7045 (was 7314)** — the moved 269 lines exactly accounted. unit 689/0/2=691.
**Parked — the actual wire-format-risk portion:** four candidate files (`+SessionSidecar`, `+ScientificBundle`, `+Image`/`+DataCube`, `+Provenance`) covering the HDF5-adjacent functions the four named parity harnesses genuinely exercise. `sessionPixelCalibration` must stay single-sourced in ONE new file, not duplicated.
Owner: assign a session with Gate B support, or authorize continuing here with a refuter.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

## braggvector-emd-writer-split, prepared and parked — added 2026-09-17

Audit 3.2 row 7. `Core/Data/BraggVectorEMDWriter.swift` (2 890 lines) is the actual EMD/HDF5 wire format — high science risk. One zero-behavior-risk step landed; the writer logic itself (`H5Fcreate`/`H5Dwrite`) is untouched.
**Landed:** `Core/Data/BraggVectorEMDTypes.swift` — the pure data-model types, no HDF5 call, diffed byte-identical against the pristine backup (exit 0), no access-level changes needed. Wired into both `tools/lib/sources.manifest`'s `export` group and `project.pbxproj`'s exception-set list. Both build paths verified (`itemJ-build1.log`, `itemJ-core.log`, exit 0). All six harnesses that compile this file pass, several with an actual py4DSTEM h5py round-trip read (`itemJ-parity-harnesses.log`, all six `EXIT=0`). unit 689/0/2=691, inventory exit 0.
**Parked — the writer itself:** splitting `BraggVectorEMDWriter`'s read/write functions BY DATASET KIND needs mapping which function writes which EMD dataset, every new file kept `nonisolated` (verified by a cold app build, not `core`), the same pbxproj+manifest wiring per file, and an `h5diff` byte-identical check.
Owner: assign a session with Gate B support, or authorize continuing here with a refuter.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

## Phase mapping, landed unvalidated 2026-09-12 — added 2026-09-12

### Step 3's 2026-09-16 increments — the record is archived, these are the live residuals

Full narratives, tables and logs:
[`archive/v3/step3-2026-09-16.md`](archive/v3/step3-2026-09-16.md).

- **The matrix is still a verdict by exclusion** (`PhaseVectorMatching.swift`,
  `surviving.count < minimumVectors`), and the cross-phase winner is still chosen by mean
  distance alone with no completeness guard. Both are open; the next increment is the T1
  reference, which is 617 of the 1024 refusals and is already known wrong in detail.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Step 3 ran on a stride-3 subsample and is OUTSIDE their band — measured 2026-09-15

**Result: OUTSIDE their band at every setting tried.** Shipped defaults 98.26 %; a 10 %
threshold 26.40 %; 1 / 2 / 3 / 5 % with the reach 25.91 / 26.18 / 26.24 / 26.32 %
(`thronsen-*-20260915.log`). That, and T1's last 22 %, are what remains. Until the band is
reached a phase fraction off this map is not a measurement and every product still says
`validation: "none"`.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The matrix is a verdict by exclusion, so it fails exactly when detection improves — MEASURED 2026-09-16, Gate D target

`PhaseVectorMatching.swift:769-773`

`minimumVectors` is **2**. So a position is called matrix when *almost nothing survives
matrix removal* — never because the matrix entry actually explains the pattern. Gate D
before any edit: diagnosis, refuting observation, prediction, then the experiment — on
`tools/phase-map-probe`, on both datasets, before a number moves.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

### Phase mapping's two distance thresholds sit near a cliff — added 2026-09-12, the cliff moved 2026-09-15, a candidate built 2026-09-17

The best entry per phase is still chosen by mean distance alone, so a sparse precise match outranks a dense one — **across phases too** (Gate B 2026-09-15: a two-vector match at 0.004 beats a ten-vector match of another phase at 0.012 Å⁻¹) — no count-aware score is built.
**A candidate built and measured 2026-09-17, PARKED:** `PhaseVectorSettings.completenessAwareCrossPhaseRanking` (off by default) reranks the cross-phase winner by matched count first, mean distance as tiebreak; unit-tested directly, broken-first. On the demo cube (`tools/phase-map-probe --truth --completeness-guard`) the confusion matrix is **byte-identical with the flag on or off** (Matrix 97.0 %, indexed 204 positions, all recall rows 100 %) — proves no regression, not yet an improvement; Thronsen isn't a valid second measurement (T1 reference already known wrong).
Owner: Gate D on real data that exercises the trap, then a refuter, before this ever ships true.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12

Twice on 2026-09-12 a newly added test method was **not discovered by XCTest at all**: eight of nine cases ran, the ninth never appeared, and the suite reported success. Rule: reconcile the case count against `func test` per file — `cases: 8 declared: 9` is the signature; a mutation surviving an incremental build is not evidence until it survives a clean one.
**Related trap, found 2026-09-17:** a test appended "at the end of the file" can land in the WRONG class. `ProductWorkflowTests.swift` holds three `XCTestCase` classes; a test inserted before the file's final `}` landed in `PhaseSplitTests` instead of `ProductWorkflowTests`, and `-only-testing:...ProductWorkflowTests/<name>` reported **"TEST SUCCEEDED" having run zero test cases** — silently green.
Rule this buys: `grep -n "^final class\|XCTestCase"` the target file before inserting near "the end", and grep the run log for the test's own name after adding it, not just the exit code.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

### The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15

**Known, scoped.** The flag the owner asked for landed 2026-09-15 behind an explicit "Fit
Anyway" button (`decisions.md`; the closed entry with the four refuted statistics is in
`archive/closed-items-2026-09.md`).

- **The mark does not survive a session round trip.** `PixelCalibration` carries a/b/θ and
  nothing else, so a restored fit-anyway ellipse reads "From session". The sidecar wire
  format is the owner's (plan §8); a field there is a format decision, not a fix.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### A challenged matrix verdict is drawn like one by exclusion — added 2026-09-15
**Presentation, live; the science is closed** (`archive/closed-items-2026-09.md`,
"A second matrix grain…"). A position the matrix takes back through `classify`
step 5 gets the same neutral grey as one where removal left too little to
index, and `PhaseMap.phaseCounts` cannot separate the two. The evidence line
does distinguish them; nothing else does. The demo cube's matrix fraction moves
51 % → 74 % because of it, which is correct but unexplained on screen. Owner:
presentation only, so no Gate D.

### The rotation null keeps the field's structure now — what it still cannot do — Gate D 2026-09-15 night

- **Power drops at the highest noise:** planted 30° at sd 0.05 is refused 3 of 12 (0 of 48
  at sd ≤ 0.03), against 0 of 60 under the shuffle null.

**The owner's own case class:** the demo cube's field is shot noise at sd ≈ 0.010 on 100 ×
100 (measured 2026-09-14); the probe's `A-100` row certifies **2 of 60** such fields, so
"Measured −67.5°" recurs about once in thirty, not every time. The cube itself has not
been re-run through the app.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### ACOM returns a zone axis up to 12.8° beyond what its bank forces — MEASURED 2026-09-15

**Science, live, no fix; the cause is narrowed to the SCORE, not the search.** The matcher
returns a template up to 12.8° beyond what its bank's own sampling forces, worst on ⟨122⟩;
the winner outscores the truth by 0.6–10 %. Exact on about half the axes. **The one
experiment that has never been run**, and the only one worth doing next: dump the
experimental polar image and BOTH templates — the winner's and the true axis's — for a
failing ⟨122⟩ case, and look at what the winner has that the truth does not.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### 26 of 200 ACOM templates do not recover themselves at an off-grid rotation — added 2026-09-14

Feed every template its own exact spots back in. At an in-plane rotation that lands on the
2.8125° azimuthal grid, 0 of 200 fail and the self-score is exactly 1.0000. At an off-grid
rotation, **26 of 200 fail to recover themselves, by 1.7° to 9.3°**. That is a different
experiment: compare the TRUE template's score against the winner's across many
orientations, rather than chasing the winner. Gate D owed before any change; two
hypotheses are already spent.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### py4DSTEM's `power_radial` is absent from the port, with no DEVIATION note — added 2026-09-14

`grep -r "power_radial\|powerRadial\|radialPower" mac4DSTEM/` returns nothing, yet it sits
in the same expression as the `power_intensity` the port does implement
(`crystal_ACOM.py:809/816`), multiplying template weights by shell radius — which up-
weights exactly the outer rings the entry above is about. An existing item, "ACOM omits
py4DSTEM's `power_radial` weighting (2026-08-28)", already names the first of these — this
entry is the measured list around it.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The zone-axis sweep marks a wrong axis against its own median — Gate D 2026-09-15 night, residuals

**Residuals:** the bar rests on synthetic plants, not on the owner's cube
(not on this machine); the disc model still understates chance about sixfold
for ring-confined vectors. **Unverified on screen.** The 2026-09-14 entry is
in `archive/closed-items-2026-09.md`.

### Contiguous invalid regions fabricate precipitates — blocks wiring

`PrecipitateSegmentation.segment()`'s non-finite guard imputes the finite median. That
survives scattered NaN and **not** a large contiguous invalid region — the shape
`Core/Analysis/StrainMapping.swift:81` actually writes. **Do not wire this engine to a
product until this is resolved.** Gate D of its own; the obvious remedy (threshold
statistics over the finite subset) silently breaks the caller-validity contract at
`PrecipitateSegmentation.swift:104-107` unless it excludes non-finite rather than invalid
pixels. Owner: whether to fix or to refuse above a bound.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

What is still missing is a way to *make* them: they came from Homebrew `hdf5 2.1.1` /
`libaec 1.1.7` on one machine, and nothing in the repo rebuilds them. Owner: whether
v3.0.0 needs a rebuild script.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

## Accessibility — added 2026-09-09 by the delegated drive

**Does NOT block v3.0.0** (owner, 2026-09-11; `decisions.md`). Deferred to a
far-future release. Kept here in full because it is a live defect, not a closed
one, and because it is not VoiceOver-only: any AX client resolving labels on the
front window trips it, so it blocks any automated driving rig and it crashed the
owner's own session twice on 2026-09-08.


### Reading an accessibility label crashes the app — evidence aged off 2026-09-15, suspect named

Two crash reports of 2026-09-08 showed `EXC_BAD_ACCESS` at a stack guard page — a stack
overflow — in `AccessibilityNode.accessibilityLabel()` → `labelsToResolve` →
`resolvedRole(forPlatformElement:)` → AppKit `_accessibilityFindRoleFromProtocol`, both
times while an AX client resolved labels on the front window. VoiceOver does exactly that,
so a VoiceOver user very likely cannot use the app at all. A crash report saved out of
`~/Library/Logs/DiagnosticReports` the same day belongs in `docs/archive/`, since this
item has now lost its evidence once.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### In-body controls report no accessibility label — the same bug

`Compute Mean / Max`, `Fit Detector Ellipse`, the two image-pane buttons and every
`Advanced` disclosure come back as bare `AXButton` / `AXDisclosureTriangle` with empty
title, description and value, while AppKit-backed toolbar items (`Hide Sidebar`, `Save to
Results`, `Dataset`) and the `Accelerating voltage (kV)` field report correctly. Treat as
one Gate D, not two fixes.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

## Verification debt — added 2026-09-08

### RotationCalibration's py4DSTEM parity leg exposes an (Rx,Ry)-vs-(col,row) frame class — Gate D, added 2026-09-17

`tools/rotation-parity-test` transcribes py4DSTEM's curl grid search from the pinned source and runs it on the same field Swift fits. They disagree: on a planted 37.2° field, Swift returns (−37.2°, transpose=false); the numpy transcription under the natural `(Rx,Ry)`=(row,col) reading returns (+37.2°, transpose=true) — same magnitude, flipped sign and transpose, the signature of a coordinate-frame difference, not a numerical bug.
**Not diagnosed:** which side (if either) is wrong, or whether `(Rx,Ry)` means (row,col) or (col,row) in py4DSTEM's own storage. Trap: do not resolve by tuning the numpy reference until it agrees with Swift.
Owner: `/diagnose`, before any change to `RotationCalibration.swift`; the harness ships with this leg informational (not gated) — the source-contract assertion is what gates today.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.


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

`testLearnedPathMatchesPythonReference` failed on both runner jobs of 05ba82a and passed
here. The test now skips where `MLComputeDevice` lists no Neural Engine, saying so; the 98
% bars were NOT loosened. Residual: a CPU-written second fixture would turn the skip back
into a check, at the cost of per-path bars. Owner: whether CI should verify this.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The published v2.5.1 artefact is universal, and Intel users get a broken app

`lipo -archs` on the shipped `build/release/mac4DSTEM-2.5.1-pre-notarization.zip`
executable is `x86_64 arm64`, while all three embedded libraries are `arm64` alone, and
`Info.plist` invites every macOS 14 machine. Every `.h5`/`.emd` open — and every EMD
export and sidecar save (`BraggVectorEMDWriter.swift:2769`) — fails with the named modal
alert "Could not load the bundled HDF5 library" (`H5Reader.swift:44`). **Owner decision
owed:** withdraw or annotate the v2.5.1 download.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Owed on screen from C4(c) and C7, after the 2026-09-09 drive

Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh,
configurator single-pattern preview, "No preview available") reaching the status strip,
and both Reset confirmations. The disk-centre LABEL round trip is still unverified: the
rig could not place a label on the diffraction pane at all (finding 7), which is a
Metal/Canvas view that may simply not take synthesised clicks. That one needs the owner's
hand, or a rig that can.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

## Release-readiness review 2026-09-11 — added 2026-09-11

Eight dimensions audited by delegated readers, every finding attacked by an independent refuter; the entries that follow are the ones that survived and were confirmed from source. Full dossier is that session's workflow transcript, not retained — each entry below carries its own evidence.
**One correction, made 2026-09-11 after the fact:** the synthesis dismissed a refuter for citing a `website/index.html` "that does not exist" — it does exist, in the sibling `mac4DSTEM/website` repo (`index.html:732`, the GPL source offer). The licence fix still stands: GPL-3 wants the licence text to accompany the binary, a different requirement from the source offer a website can satisfy, and the bundle carried neither before that day.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

### The hexagonal IPF colour key is labelled the wrong way round (2026-09-11)

**Established:** the colour function and the two label strings, quoted above. **Not
established:** which corner of the drawn triangle each label sits under, and therefore
whether the fix is to swap the labels or to leave them; that needs the triangle geometry
read against the azimuth convention, and the maps themselves are not in question. **Owner:
presentation only, so no Gate D — but it must be settled against the convention, not by
eye, and pinned by a unit test asserting `ipfColor` at +x names the index the key
prints.**
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Single-slice ptychography publishes under a mode its export guard misses

`ResultExport.swift:1627` guards `analysisMode == .ptychography` alone, while `:1478`
handles `.ptychography, .singleslicePtychography` together — established by reading both.
**Not established:** that the publish path really uses the distinct case; verify before
fixing. No test publishes a ptychography product. **Owner: Gate D — a scale bar is a
scientific number, and the cause is not yet established.**
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### HDF5 runs under one lock now — what that costs and what is still open — fixed 2026-09-15 late night

**Costs:** a caller blocks its thread for the length of one operation (a
sidecar write can be seconds); the two `dlopen`s stay two; no unit test can
crash-test this, the probe is diagnostic. **The "refuse a second open"
guard stays** as belt and braces. Thread-safety is still asserted by one
2026-08-19 `nm` inspection; `H5is_library_threadsafe` is still called
nowhere.

### The Quantitative badge consults no origin gate at all (2026-09-11)

**The real defect is larger:** products do not carry the origin they were computed
against. Strain snapshots it and nothing reads it (one consumer,
`ResultExport.swift:516`); DPC snapshots nothing; **ACOM alone is wired**
(`ACOMWorkflow.swift:145-150`). A badge gate cannot work until that is true. **A fix was
written 2026-09-11, REJECTED by Gate B, and reverted** — it changed no behaviour while
five tests passed. Ships in v3.0.0 as a stated limitation (owner, 2026-09-11), because a
fix that looks like one and is not is worse than the open defect. Gate D and Gate B owed.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### A radius-only aperture drag destroys the fitted origin (2026-09-11)

`ApertureOverlay.emit` rounds the centre to whole pixels and hands the WHOLE `Aperture` to
`updateAperture`, which tests `newAperture.centerX != aperture.centerX`
(`AppState.swift:3112`). So dragging an inner/outer RADIUS handle, never touching the
centre, rounds it by up to 0.5 px, trips the centre-change branch and destroys
`calibration.origin` and `recordedOriginX/Y`. Owner: cheap, Gate D (a number can move).
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

The aperture centre silently IS the calibration, and after a fit the aperture sits on the
fitted mean — 10.9 px from the pattern's visual middle on this dataset — which is
precisely what invites a user in an imaging workspace to "correct" it. The only notice is
a transient `statusText`; Owner: decide whether a confirmation, a non-transient banner, or
refusing to clear without consent.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

Driven on `polycrystal_2D_WS2.h5` (`archive/v3/drive-2026-09-09.md`, finding 16; shot
`B33-ws2-detect-done.png`). Still open, and the harder half: `Strain` moved from `!` to
enabled on a median-1 result, because readiness gates on Bragg vectors EXISTING, not on
being usable. Owner: presentation plus a readiness question; no Gate D (mechanism
established by reading the two call sites, no number moves).
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Bullseye disk detection accepts noise — two of three fixes landed 2026-09-05, drive owed

LANDED: flat mode + Use File's Probe, parity 878/878 and 164/164 with py4DSTEM's flat
route (`status.md`). OPEN: (1), an outer-edge probe size for structured probes (it also
feeds the origin window — its own Gate D). Owner: drive Map ▸ Bragg disks on the file with
Flat + Use File's Probe at Min relative intensity ~0.05.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Origin-fit gate has two unresolved holes (2026-09-05)

(b) Which statistic gates `originFitIsSane` is open: full-scan RMS (current) cannot see
bias; the robust/kept-set residual tried 2026-08-28 was reverted — it passes a 15 px-
displaced fit at 9.94 px. (c) The trimmed fit is blind to spatially clustered failure and
contamination ≥ 50 % (a 40 px-off quarter of the scan gives 100 % kept, 20.6 px error; an
exactly bimodal residual zeroes the MAD guard). Owner: a design pass — no statistic
proposed yet separates displacement from contamination. `docs/q-calibration-design.md`.

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

(a) Exported Euler angles are labelled py4DSTEM/orix-compatible but differ by frame
rotation `P` — median 38.55° misorientation if compared naively; math right, label wrong.
(b) The projection convention (`OrientationPlan.project`) is verified three independent
ways, but every gated ACOM harness builds its own peaks through the function it tests, so
two frame-mutation bugs stay green — no analytic, non-self-referential fixture exists yet.
Owner: (a) relabel-vs-convert decision then Gate B; (b)–(d) Gate B.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Q-calibration scale defects on real crystals (2026-09-02)

(b) The reference-shell pick has no l-filter or visibility filter; on 2H-WS₂ it selects
(0002), which a [0001]-zone specimen never shows — predicted mis-scale 2.26×, silent; at
that scale the correlation score HALVES while median `reliability` RISES, so no fix may
lean on reliability to choose between scales. Owner: (b) its own design pass.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

Still unprovoked: staleness (f), and "Fit Detector Ellipse" on the demo ending in
"residual is too large (0.247)".
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

**What is NOT established** is whether the estimates are right: 8-11 GB of working set for
a 268 MB cube is a 30-40x ratio, and nobody has checked whether that is the algorithm's
true cost or an over-estimate that refuses work the machine could do. That is a Gate D of
its own (a number governs whether a feature runs at all), not a tuning knob to raise.
Consequence for the release: Parallax and single-slice ptychography ship **undriven on
real data** and must be described that way in the release notes.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Fabricated provenance on pre-2026-08-18 sidecars (2026-09-02)
`AppState.swift:2854,2867` do `snapshot.loadSpecification ?? .fullExtent` —
a sidecar saved from a cropped view before that attribute existed is now
asserted full-extent rather than unknown. Both prior reproducers were
overwritten by later driving sessions; demonstrating it again needs a
synthesised sidecar, not a training-set one. Unowned, belongs with the
trust fixes.

### DM4Reader silently reads the whole file into RAM off non-local volumes (2026-09-02)

`.mappedIfSafe` (`Core/Data/DM4Reader.swift:97`) declines to map on any volume failing
`MNT_LOCAL && !MNT_REMOVABLE` (confirmed by S9b: every external disk, every disk image
even on internal SSD, all smbfs) and silently falls back to a full anonymous-memory read —
held for the whole session. **The original 2026-08-18 8 GB-machine death that motivated
this is still NOT explained** — the mechanism is real and worth fixing but not established
as that incident's cause. Owner: a later session, Gate B.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The sidecar reader has D003's missing guard too — not fixed (2026-09-09)

`BraggVectorEMDWriter.swift`'s attribute reads carry the same defect D003 fixed in
`H5Reader.swift`: `H5Aread` reads a whole attribute into a buffer sized for one value.
This is the 2026-08-31 review's `core-data-01` (**confirmed, high** — "assume scalar
variable-length storage without checking the file type or extent"), which D003 has now
supplied the runtime evidence for, and the new register's `D029`/`D053`. The fix is the
same three lines — `H5Aget_space` plus `elementCount(spaceID:) == 1` — and the measurement
is already done (24 bytes into 8; 32 into 9). Owner: a v2.5.x patch session.

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

`Si-SiGe.dm4` stores its scan pair fastest; the reader maps the tags as `[Rx, Ry, Qy,
Qx]`, a pattern 480 wide × 448 tall. A transposed pattern silently flips strain axes and
the R–Q rotation. Owed: the owner reads the pattern's width and height in GMS. If 448
wide: flip `DM4Reader.scanFastestStrides` and the scan-fastest shape line, then pin a
checksum from ncempy's raw array on the real file.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The open/promote unwind is sixfold, and Cancel can vanish mid-load (2026-09-04)

Hazard 2 is worse than recorded: `finishDatasetLoading` (`AppState.swift:2800`)
unconditionally nils `datasetLoadCancellation` and clears `isLoadingDataset`, both of
which `canCancelDatasetLoad` (`:1162`) depends on — with two loads in flight the FIRST
tail to finish disarms Cancel for the second. Unification alone is not the fix; no fixture
exercises these branches, and that is the precondition. Owner: whichever session next
touches any of the six.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

**Amended 2026-09-12.** The status bar's own Cancel was a `.controlSize(.mini)` version of
the same mistake and is now a borderless `xmark.circle.fill`, so this toolbar item is the
ONLY Cancel left with a rendering complaint against it. The owner's call on whether the
toolbar wants it is still owed, and is now a smaller question than it was.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

**Headline:** iDPC's badge and banner AGREE; the contradiction is `PhaseSettings`' always-
shown qualitative banner over `dpc_magnitude` / `dpc_angle`, which `quantitativeStatus`
calls quantitative. Before any fix: status is frozen at publish and at persist and
preferred over re-derivation on restore, so a change corrects neither existing sidecars
nor exported PNGs, and there is no version field to migrate on. Owner: the trust-fixes
session; a judgement call.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### Misc unclaimed, low priority (2026-09-02)

Load-cancel: F1.1d (cancel a real load on screen) never driven; resident buffer/cropped-
view teardown unpinned. #31 `validationIssues` is O(n²) in a SwiftUI view body. #32
`isSymmetry`'s bijection check has no fixture coverage.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

### The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04)

**The rule, demonstrated 2026-09-04: nothing inside a split's hosted content may
repeatedly change its own minimum size.** Two sites, both in the status bar, both fixed.
Full diagnosis and the refuted `HSplitView` conjunction: commits `e608dbd`, `27de9bb`; the
S17 record is archived. Residuals: n=1 each way against a fault once called intermittent;
the inspector's Performance rows still tick per second. Owner: unclaimed.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

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

Owner, on `downsample_Si_SiGe_exp.h5`: enter a manual Q or R pixel size, the row turns
green and the field disappears with it. A wrong R scale silently rescales every real-space
axis, scale bar and export, so this is a trust defect. Owed: the owner drives both
surfaces and sees the fields stay visible and editable after the row is green.

### `calibration.*` identifiers exist twice while the export sheet is open (2026-09-04)
`ExportSheet` re-renders the readiness rows, so `calibration.readiness`,
`calibration.item.*`, `calibration.rScale.filenameConflict` and
`calibration.action.originProbe` are each emitted by both it and
`PrepareSettings` while the sheet is up. Harmless today — nothing queries them
at runtime — but it would defeat any future UI test that addresses a readiness
row by identifier. The old app had the same collision. Owner: unclaimed.

## Code hygiene

### The audit's refactor list, rows 4–13, is the open hygiene queue — 2026-09-16

Rows 1–3 and 10 landed in `e415929`. **Row 8's `axisDelta` pair closed 2026-09-17** (full record `docs/archive/closed-items-2026-09.md`); `nextPow2` stays open on purpose (merging FFT1D/FFT2D forces FFT1D into ~5 dependency-closed manifest groups). **Row 5's `PtychographySettings` extraction landed 2026-09-17** (`App/PtychographySettings.swift`, broken-first contract tests, `docs/status.md`).
**Still open:** row 4 (a shared harness helper, Gate B on it — a shared `fail` can green 46 harnesses at once); rows 6–7 (`Support/ResultExport.swift` / `Core/Data/BraggVectorEMDWriter.swift` splits, both started 2026-09-17, still parked — see the "resultexport-split" and "braggvector-emd-writer-split" entries above); row 12 (the >1 000-line harness mains). **Row 9 is a do-not:** five different `median` bodies in Core stay separate until a Gate D shows they should agree (ADR 015).
**Row 5 (the AppState seams) is CLOSED 2026-09-18:** all seven seams landed — the full seam-by-seam log, decisions and gate numbers live in `docs/appstate-seams-plan.md` and are not duplicated here. AppState.swift 5476 → 1474 lines; it is no longer the repo's largest file (`Support/ResultExport.swift` is, at 1601). **Seam 7** (the load pipeline placement — `App/AppState+Open.swift`/`+Promote.swift`/`+Replay.swift` — plus its owner `Session/PromotionRun.swift`) landed a genuine regression caught before commit, not on inspection: the moved `commitPendingLoad` collapsed its peek-then-clear guard into one `promotionRun.take()`, so a refused commit (a beam-excluding crop) silently dropped the configurator's pending load instead of leaving it open for correction. Caught by `PromotionCommitTests.testCommitRefusalPreservesThePendingLoadForCorrection` (red before the fix, green after); fixed with an inline `DEVIATION` note. Gates: build 0, unit 741/0/2=743 (743 `func test` reconciled), inventory 0 — `AppState.swift` no longer the largest file; simplicity debt carried forward: replace the scattered manual result-version bumps with one standard invalidation API.
Evidence and blast radii: `docs/archive/audit-2026-09-16/REPORT.md` §3.2. Owner: whoever picks a row.
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

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

12 bare `.fixedSize()` call sites exist against the constraint-loop rule above (`grep -rn '^\s*\.fixedSize()'`). **One is armed:** the zoom badge (`ImagePanes.swift:587`, `zoomModeBadge`) — `ZoomPan.liveZoom` is written on every magnify event, the digit count moves (×9.9 → ×10.0 → ×100.0) unclamped mid-pinch, and the badge appears/disappears across ×1.0, inserting/removing a `.fixedSize()` child repeatedly in one gesture. The rest are literals or change once per published product.
**Not fixed, deliberately:** a reserved slot closes the string-width channel, not the appears/disappears one. **Not urgent:** none of the 12 sits in the one `.safeAreaInset` where both crashing sites lived.
Owner: with the `PaneSplit` residual (a).
Detail: `docs/archive/open-items-detail-2026-09-18.md`.

### Harness type replicas of `Aperture` (2026-09-02)
Every runner sources `tools/lib/sources.manifest` since C2 (2026-09-07; the
inventory fails one that does not). What remains: `Aperture` is declared in
`App/AppState.swift`, and scientific harnesses carry their own copies that
would still compile and pass if the app's gained a field — it belongs in
`Core/`. The app build is the only real gate for actor isolation
(`tools/load-spec-test` compiles nonisolated; the manifest's isolation flags
buy visibility, not enforcement). Owner: the next `AppState` extraction (C5;
the first, the fit overlays, landed 2026-09-07).
