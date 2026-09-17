# Open-items detail moved 2026-09-18

Bodies moved verbatim from docs/open-items.md to hold the 12-line rule; the live stub in that file is the entry of record.

## v3.1 origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay + clustered case owed

`OriginMaps.originValidity: [Bool]?` carries the robust trim's per-position `kept` mask
(previously only the scalar `excludedFraction` survived). Disclosure only, no fitted number
moves; wire type `PixelOriginMaps` untouched (D3 deferred), so a restored session reads `nil`.
Gates, break-first, and the adversarial review that caught a production-carry test gap: ADR 033,
`docs/v3.1-calibration-preregistration.md`. **Owed:**
- **D4 count landed** (`PrepareSettings.positionsUsedValue`, unit-tested M4) — **unverified on
  screen**. The spatial **validity overlay** (origin fit over the scan grid, excluded positions
  greyed via `DisplayedProduct.validityMask`) is a larger follow-on, not built.
- **Step-3 PASSED** (`trim-sweep`, 4 cubes, shipped default): excluded 0.6–15.7 %, `maxGap` 1–5 —
  Si-SiGe (15.7 %, scattered) vs sim_Au (10.6 %, `maxGap 5`, clustered) exclude alike but differ
  spatially, which the scalar cannot see and the mask can (hole (c)). Dramatic clusters still synthetic.
- **D1/D2 at defaults, overrule on sight:** `[Bool]?` aligned to `fittedX/Y`; `false` = interpolated,
  not measured; the re-reference transforms drop it with `excludedFraction`.

### Parallax default bin schedule runs the finest bin once; py4DSTEM's runs it twice — Gate D diagnosed 2026-09-17, fix owed
`ParallaxAligner.defaultBinSchedule` (`ParallaxAlignment.swift:152-166`) returns e.g. `[4,2,1]`
for a diameter-5 disk; py4DSTEM's `reconstruct` default (`num_iter_at_min_bin=2`,
`parallax.py:1141,1278-1281`) appends one repeat of the finest bin → `[4,2,1,1]`. **Refuting
observation:** were the port matched, `isComplete` (`:74`, `completedBins == alignmentSchedule`)
would fire only after a second bin-1 pass and `errorHistory` would hold two bin-1 entries — it
holds one, and no `numIterAtMinBin` knob exists anywhere (grepped). The second pass is a real
iteration, not a no-op: py4DSTEM rebuilds `G_ref` from the updated `recon_BF` and appends another
error entry. Every downstream product gates on `isComplete` (`ParallaxAberrationFitting:134`,
`AberrationCorrection:82`, `SubpixelReconstruction:96`, `DepthSectioning:99`), so all compute one
refinement pass short. **Predicted:** a small additional shift refinement toward py4DSTEM's
converged state — direction not reversal, magnitude a property of the dataset (measure, don't
infer). **Experiment (harness only, no Core fix):** py4DSTEM-dev is vendored and the 9-image
stack is generated in-process, so run py4DSTEM's `BFReconstruction.reconstruct(reset=True)`
head-to-head against the port driven over `[4,2,1]`, reporting max-abs `totalShifts`/`alignedBF`/
final-error diffs. **Trap:** `tools/parallax-alignment-test/reference.py:354-357` hard-codes the
schedule WITHOUT the repeat, so the green test agrees with the port by construction and cannot
catch this — add the `num_iter_at_min_bin` hstack to its contract list. **Science, Gate D before
any `ParallaxAlignment` change.** Owner: unclaimed.

## T1 [0 -4 1]: the not-indexed pairs are per-peak detection noise, not origin or reference — measured 2026-09-17

The earlier question — "do the two observed T1 spots form a Friedel pair, or two different-length
families 0.454/0.479?" — is **resolved by direct measurement** (independently refuted). Three ways:

1. **The reference** (`PhaseReferenceLibrary.build` output for `Thronsen.t1` at `[0,-4,1]`, groups
   by `|g|` within 0.001 Å⁻¹): **0.0575, 0.2334, 0.4546, 0.4668, 0.4703, 0.4933, 0.700, 0.703,
   0.733, 0.753, 0.788 Å⁻¹.** The extra groups (0.0575, 0.4546, 0.4703) are `l=4k±1` near-ZOLZ
   reflections the flat-Ewald slab admits ONLY because this is a long c-axis cell — `1/|r_uvw|` =
   0.041 < the 0.05 slab (`PhaseReferenceLibrary.swift:454-465` flags exactly this), projected to
   reduced lengths. So the reference is OVER-complete near 0.45-0.49 (four candidate lengths where
   crystallography has two). Does not match `thronsen.swift`'s unpinned header (0.233…0.679).
2. **The real data** (`tools/thronsen-dataset` subsample, shipped defaults): T1 positions mostly
   leave exactly 2 survivors after matrix removal (52.1 % of 6358); all 252 marked "not indexed"
   failed at eligibility (100 % "nothing-cleared", 0 % "cliff-refused").
3. **The survivors' geometry** (new read-only `phase-map-probe` block, same data): at the 252
   not-indexed T1 positions the two survivors are **one `|q| ≈ 0.462–0.470 Å⁻¹` family** — the
   {200}-type ZOLZ reflection (independent `docs/archive/v3/t1-zolz-2026-09-17.py`: exact {200}
   `|g|=0.4668`, ±pair
   (2,0,0)@18.6°/(−2,0,0)@198.6°), NOT two families 0.454/0.479; within-pair lengths agree to
   ≤ 0.006. They ARE a Friedel pair but sit **2.5–5.2° off antiparallel** (`|u+v|` = 0.021–0.043,
   all just over the 0.02 pair radius), so `containsFriedelPair` returns false, the floor stays 3,
   and 2 survivors can never clear it. **So: one real 0.467 Friedel pair, the reference length is
   correct (do NOT change the T1 reference), and the rejection is a tolerance, not crystallography.**
   Consistent with the 59 % recall the floor-2 exception already buys — centred pairs pass, these
   marginal ones fall just outside.

**Gate D experiment RUN 2026-09-17** (`phase-map-probe --t1-origin-experiment`; sanity: `classify`
with the global origin reproduces all 252 not-indexed): a per-position direct-beam COM origin
(independent of the T1 spots) sits **0.04 px (0.0007 Å⁻¹) median from the global origin** — the beam
is stable, not wandering — and leaves the best surviving-pair `|u+v|` essentially unchanged
(0.0266 → 0.0261 Å⁻¹), recovering only **24 of 252 (10 %)** as T1. **So the off-antiparallel residual
is NOT a common-mode origin error; it is per-PEAK centroid noise on the two weak {200} spots**
(~0.5–1 px each), refuting the origin hypothesis — per-position origin is not the fix. When a pair
does clear 0.02 it correctly indexes as T1 (24/24), so reference and matcher are sound; the limit is
detection precision on weak reflections. Remaining levers, each its own Gate D: reduce per-peak noise
(better centroiding of the weak spots), loosen the pair-antiparallel tolerance (recovers ~half at
rising Al-false-positive and 0.015-cliff cost), or accept a detection-limited T1 recall. Owner:
which lever, if any.

**py4DSTEM head-to-head, run 2026-09-17** ([`archive/v3/py4dstem-t1-comparison-2026-09-17.md`](archive/v3/py4dstem-t1-comparison-2026-09-17.md)):
fed py4DSTEM's own ACOM + `CrystalPhase` NNLS the SAME detected peaks, it labels **100 % of T1
positions Al** (T1-dominant 0 %, even where mac4DSTEM indexes T1). Verified real: T1's reference is
correct, ACOM finds ~the right orientation, and T1 explains every peak (6/6) vs Al's 4 — but
py4DSTEM's intensity-weighted residual prefers Al (7.4 vs 9.5) because it never removes the matrix and
the strong Al {200} reflections carry ~all the intensity. A confident mislabel where mac4DSTEM abstains
— it validates the matrix-removal + position-based design, not a lever to adopt.

## resultexport-split, prepared and parked — added 2026-09-17

Audit 3.2 row 6 (`docs/archive/audit-2026-09-16/REPORT.md`): `Support/ResultExport.swift`
(1 939 lines before this session, 12 of 27 funcs untested) split by export kind, in small
green-boundary commits, each verified before the next. **One landed, self-verified — NOT
Gate B-reviewed, per this item's own rule (STOP before self-approval).**

**Landed:** `Support/ResultExport+Rendering.swift` — the pure rendering helpers
(`captionTextHeight`, `publicationFigure`, `applyColormap`, `burnScaleBar`, `cgImage`,
`savePNG`, `writePNG`, `pngProperties`), zero AppState instance-state dependency (every
function `static`/`nonisolated static`; the one that needs a live `AppState` takes it as an
explicit parameter). Verified: the moved body is line-for-line identical to the original
except three `private` → internal-visibility widenings the split requires (`applyColormap`,
`cgImage`, `savePNG` — still called from the original file, `private` no longer reaches
across files) — checked by diffing the extracted range against the pre-split backup, not
asserted. Build exit 0, zero warnings (`itemI-build2.log`). The 6 rendering/provenance unit
tests that exercise this code pass (`itemI-rendering-tests.log`). The four named parity
harnesses (bragg-export, preprocessing-export, reduced-export, scientific-bundle) also
pass (`itemI-parity-harnesses.log`) but — stated plainly — **do not exercise this file at
all**: they source the manifest's `export` group, which is `Core/Data/BraggVectorEMDWriter.swift`
and its dependencies, never `Support/`. That is exactly why this piece was chosen first: it
carries no HDF5/wire-format risk, so there was nothing for those harnesses to catch either
way. `inventory`: AppState + ResultExport **7045 (was 7314 at HEAD)**, the moved 269 lines
exactly accounted for. unit 689/0/2=691 (`unit-itemI-final.log`).

**NOT attempted — the actual wire-format-risk portion, left for the owner's session with
Gate B support:**
- `saveCurrentResultToSessionSidecar`, `selectSavedSessionResult`, `loadSavedSessionResult`,
  `applySelectedSavedControls`, `removeSavedSessionResult`, `saveSessionSidecarAs`,
  `adoptSessionSidecar`, `saveCalibrationToSessionSidecar` → a candidate
  `ResultExport+SessionSidecar.swift`.
- `exportScientificBundle`, `scientificBundleMaps`, `scientificBundleOmissions` → a candidate
  `ResultExport+ScientificBundle.swift`.
- `exportCalibratedDataCube`, `exportResultImage`, `exportedImageProvenanceRecord`,
  `orientedRGBA`, `exportDiffractionImage`, `exportDiskCentreLabels`, `toggleDiskCentre` →
  candidate `ResultExport+Image.swift` / `+DataCube.swift`.
- `sessionPixelCalibration` (with `originFitProvenance`/`strainFrameProvenance`, read from
  both the scientific-bundle and session-sidecar paths — **must stay single-sourced in ONE
  new file**, not duplicated, per this item's own rule) → a candidate `ResultExport+Provenance.swift`.

Each of those DOES interact with HDF5 writing and the four named harnesses genuinely
exercise it — that is where a transcription error could silently corrupt what py4DSTEM
reads back, and why it is parked rather than rushed. Same method as the landed piece
(exact-range extraction, diff against a pristine backup, private→internal only where a
cross-file call requires it, full unit + the four harnesses + inventory each step), but
each step needs its own Gate B refuter, not a self-review. Owner: assign a session, or
authorize continuing here with a refuter available.

## braggvector-emd-writer-split, prepared and parked — added 2026-09-17

Audit 3.2 row 7. `Core/Data/BraggVectorEMDWriter.swift` (2 890 lines) is the actual EMD/HDF5
wire format — high science risk, "a byte moved is a file py4DSTEM misreads." One
zero-behavior-risk step landed; the writer logic itself (the `H5Fcreate`/`H5Dwrite` calls)
is untouched.

**Landed:** `Core/Data/BraggVectorEMDTypes.swift` — the pure data-model types the export
pipeline passes around (`ScalarResultMap`, `RGBAResultMap`, `SessionResultStorage`,
`SessionResultDescriptor`, `SessionSidecarInventory`, `SessionSidecarSnapshot`,
`CalibratedDataCubeExportOptions`, `CalibratedDataCubeExportSummary`, `DataCubeDerivation`
including its `compose`/`jsonString`). No HDF5 call anywhere in this range — every type is a
value type with no I/O. Verified: `diff` against the pristine pre-split backup on the exact
extracted range, exit 0 — truly byte-identical, no access-level changes needed this time
(everything here was already `package`, visible cross-file without modification). Wired into
**both** places CLAUDE.md's hard rule and this item's own text name: `tools/lib/sources.manifest`'s
`export` group (alongside `BraggVectorEMDWriter.swift`) and `project.pbxproj`'s
`PBXFileSystemSynchronizedBuildFileExceptionSet` membership list for the `mac4DSTEM` target
(the "2026-08-17 silent-drop class" this item's brief named by name — a Core/ file absent from
that second list compiles into the SPM package but silently NOT into the app target). Both
build paths verified separately: the app build (`itemJ-build1.log`, exit 0) and
`tools/run-tests.sh core` — `swift build` of the DSTEMCore/DSTEMSession packages, the OTHER
path that would have silently diverged from a missed manifest entry (`itemJ-core.log`, exit 0).

**All six harnesses that compile this file pass** (this time a real check, unlike
`resultexport-split`'s first step — these six DO exercise `BraggVectorEMDWriter.swift`):
bragg-export-test, preprocessing-export-test, reduced-export-test, scientific-bundle-test
(the four named in this item's brief), plus sidecar-result-test and sidecar-error-detail-test
(`itemJ-parity-harnesses.log`, all six `EXIT=0`) — several of which assert an actual py4DSTEM
h5py round-trip read of the written file, which is the strongest evidence a pure code move
changed nothing: the bytes on disk are unreachable from a relocated type declaration in the
first place, but the harnesses confirm it anyway rather than resting on that argument alone.
unit 689/0/2=691, inventory exit 0 (`unit-itemJ-final.log`, `inv-itemJ.log`).

**NOT attempted — the writer itself, left for the owner's session with Gate B support:** the
`BraggVectorEMDWriter` enum's actual read/write functions (starting where this extraction
stopped, `Core/Data/BraggVectorEMDWriter.swift:4` post-split). Splitting BY DATASET KIND per
this item's own instruction needs: (a) identifying which functions write which EMD dataset
(BraggVectors peaks, calibration, the reduced DataCube, the scientific bundle's `RealSlice`
maps — read the file's own `// MARK:`-equivalent structure, which this session did not yet
map function-by-function); (b) **keeping every new extension file `nonisolated`** — this
item's own explicit warning: "default isolation is MainActor; a lost `nonisolated` is a real
off-main-HDF5 defect only the app build catches," not something `swift build`/`tools/run-tests.sh
core` would catch (bare `swiftc`/SPM default to nonisolated already, so only the app target's
`MainActor`-by-default build proves the annotation is doing real work — verify with a cold app
build specifically, not just `core`); (c) the SAME pbxproj + manifest wiring this step just
demonstrated, repeated per new file; (d) `h5diff` the written sidecar before/after, byte-identical,
per this item's own suggested verification, on top of the harnesses' py4DSTEM round-trip checks.
Owner: assign a session with Gate B support, or authorize continuing here with a refuter.

### Phase mapping's two distance thresholds sit near a cliff — added 2026-09-12, the cliff moved 2026-09-15, a candidate built 2026-09-17

What remains a caution: the best entry per phase is still chosen by mean distance alone,
so a sparse precise match outranks a dense one — **across phases too** (Gate B 2026-09-15:
a two-vector match at 0.004 beats a ten-vector match of another phase at 0.012) — a count-
aware score is not built, and the pair floor makes two-vector matches admissible.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

**A candidate built and measured, 2026-09-17, PARKED — Gate D + the owner's refuter
still owed before any merge.** `PhaseVectorSettings.completenessAwareCrossPhaseRanking`
(off by default) reranks the cross-phase winner in `classify` step 3 by matched count
first, mean distance as the tiebreak only — the same rule `fitMatrixOrientation` already
uses for candidate zone axes in this same file. Mechanism isolated and unit-tested
directly (`PhaseVectorMatcher.crossPhaseWinsOver`, `PhaseVectorMatchingTests.swift`,
broken-first): with the flag on, a hand-built (2 matched, 0.004 Å⁻¹) vs (10 matched,
0.012 Å⁻¹) pair correctly flips winner. **Measured on the one dataset with ground
truth** (`tools/phase-map-probe --truth`, new `--completeness-guard` flag): the demo
cube's confusion matrix is **byte-identical with the flag on or off** (Matrix 97.0 %,
indexed 204 positions, every recall row 100 %) — this dataset does not contain a
position where two candidate phases both clear their eligibility guards with the
loser matching more vectors, so it can prove no regression but cannot yet prove an
improvement. Thronsen is not a valid second measurement here: its T1 reference is
already known wrong in detail (`docs/status.md` handoff), which confounds any
before/after comparison of a DIFFERENT knob. Owner: Gate D on real data that exercises
the trap, then a refuter, before this ever ships true.

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — added 2026-09-12

Twice on 2026-09-12 a newly added test method was **not discovered by XCTest at all**:
eight of nine cases ran, the ninth never appeared, and the suite reported success. **The
rule this buys:** reconcile the case count against `func test` **per file** when adding
tests, not only for the whole suite — `cases: 8 declared: 9` is the signature. And a
mutation that survives on an incremental build is not evidence until it survives on a
clean one.
Detail: `docs/archive/v3/open-items-detail-2026-09-16.md`.

**A related trap, found 2026-09-17: a new test appended "at the end of the file" can land
in the WRONG class.** `ProductWorkflowTests.swift` holds three `XCTestCase` classes
(`ProductWorkflowTests`, `TaskReadinessTests`, `PhaseSplitTests` — file-scoped grouping, not
one class per file). A test inserted before the file's final `}` landed inside
`PhaseSplitTests`, not `ProductWorkflowTests` where its subject matter belonged; `-only-
testing:mac4DSTEMTests/ProductWorkflowTests/<name>` then reported **"TEST SUCCEEDED" having
run zero test cases** — no "Test case … passed" line at all, silently green. The rule this
buys: `grep -n "^final class\|XCTestCase"` the target file before inserting near "the end",
and after adding a test, grep the run log for the test's own name, not just the exit code —
a suite that starts and reports success without ever naming your test ran nothing.

### RotationCalibration's py4DSTEM parity leg exposes an (Rx,Ry)-vs-(col,row) frame class — Gate D, added 2026-09-17
`tools/rotation-parity-test` (new gated harness; closes "`RotationCalibration.swift`
has no gated parity harness", `docs/archive/closed-items-2026-09.md`) transcribes
py4DSTEM's curl grid search from the pinned source (`phase_base_class.py`'s
"Transpose unknown, rotation unknown" branch) and runs it on the same field Swift
fits. They disagree: on a planted 37.2° field, Swift returns (−37.2°, transpose=false),
the numpy transcription under the natural `(Rx,Ry)` = (row, col) axis reading returns
(+37.2°, transpose=true) — same magnitude, flipped sign and transpose, the signature
of a coordinate-frame difference, not a numerical bug. Not diagnosed: which side (if
either) is wrong, or whether `(Rx,Ry)` means (row,col) or (col,row) in py4DSTEM's own
storage. Trap: do not resolve this by tuning the numpy reference until it agrees with
Swift — that is fitting the fixture to the code under test. Owner: `/diagnose`, before
any change to `RotationCalibration.swift`; the harness ships with this leg informational
(not gated), the source-contract assertion is what gates today.

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

### The audit's refactor list, rows 4–13, is the open hygiene queue — 2026-09-16
Rows 1–3 and 10 landed in `e415929`. **Row 8's `axisDelta` pair closed 2026-09-17**
(`CrystalModel.swift`/`CIFImport.swift`, full record `docs/archive/closed-items-2026-09.md`)
— `nextPow2`, `positiveModulo`, `wrapped`, `checkCancellation`, `finiteDouble` and
`admits` are still open within that row, deliberately: `nextPow2` was excluded on purpose
(merging FFT1D/FFT2D forces FFT1D into ~5 dependency-closed manifest groups, the silent-
compile-break the manifest guards). **Row 5's PtychographySettings extraction landed
2026-09-17** (`App/PtychographySettings.swift`, the seam's own contract test —
`AppState` holds it without forwarding properties — and a settings-survive-a-dataset-
reopen test, both broken-first; `docs/status.md`). Still open otherwise, in the audit's
order: a shared harness helper (row 4, Gate B on the helper — a shared `fail` can green
46 harnesses at once), the NEXT `AppState` seam (row 5 continues — one per session),
`Support/ResultExport.swift` and `Core/Data/BraggVectorEMDWriter.swift` splits only with
byte-identical output evidence and a refuter (rows 6–7 — **both started 2026-09-17**, see
"resultexport-split, prepared and parked" and "braggvector-emd-writer-split, prepared and
parked" below), and the >1 000-line harness mains (row 12).
**Row 9 is a do-not:** five different `median` bodies in Core stay separate
until a Gate D shows they should agree (ADR 015). Evidence and blast radii:
`docs/archive/audit-2026-09-16/REPORT.md` §3.2. Owner: whoever picks a row.

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
