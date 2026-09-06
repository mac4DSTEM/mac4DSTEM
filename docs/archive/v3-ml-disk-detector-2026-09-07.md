# The AI/ML branch, 2026-09-07 — the day's evidence, verbatim from the status handoff

Archived at the 2026-09-07 closeout (the live handoff carries the state and
the pointers; this file carries the numbers and the story of how each verdict
converged). Branch `ml/disk-detector`, commits `e0e0dc8` … `0a38efc`, none
pushed. Retained logs: `References/training_runs/disk-detector-2026-09-07/`
(owner-local). Read `docs/status.md` for what is live; this is history.

**Step 3 verdict, corrected 2026-09-07 (morning review of the overnight
run; branch only, nothing pushed, `main` untouched; numbers are §3a
"Step 3 — evidence" in `v3-plan.md` and the retained logs it names):**

1. **Step 3 is NOT passed. Last night proved the pipeline, not the detector.**
   What stands: the simulator and committed fixture (proven, broken four
   ways), a U-Net trained twice, nine Core AI assets + Core ML insurance
   pixel-checked against PyTorch, hashed, and timed on the Neural Engine at
   0.36 ms per pattern. What the overnight verdict got wrong, each checked in
   the code or a retained log this morning: (a) **the 2× ceiling was measured
   against the wrong baseline** — the 0.602 ms stand-in is the serial
   single-core detector on 24 synthetic patterns; the app has no Metal disk
   detection, its scan path (`DiskDetection.detectAll`) runs that detector on
   all 8 cores, so on the same cube the classical wall clock is ~5 s per
   65 536 against the net's 24 s: about 4–5× over, not 0.6× under;
   (b) **the training target teaches the lattice, not the visible disks** —
   extinct reflections (rendered at 0–2 %) stay in the truth list and get a
   full-amplitude bump (`simulate.heatmap_target`), the likely driver of the
   ~65 background proposals per real position; (c) **refinement rejects
   nothing** — `evaluate.refine` snaps every candidate and returns it, no
   acceptance rule, no duplicate merge; (d) the "real" training backgrounds
   are azimuthal medians, texture-free by construction, so the net never saw
   the texture it fires on; (e) the step 3 numbers came from PyTorch
   heatmaps, not the exported asset; (f) threshold 0.9 keeps fixture raw
   recall 1.000 (`run2/evaluate/evaluate-thr0.9.json`), so "the fixture wants
   0.3" was false and the threshold question is moot: 0.9.
2. **The increment ran 2026-09-07 afternoon (run3; logs under
   `References/training_runs/disk-detector-2026-09-07/`, README "2026-09-07
   revisions").** Targets now carry each disk's visibility (extinct and faint
   reflections no longer teach the lattice); real backgrounds keep their
   texture with the disks and beam cut out; width 12 (275 k parameters, 4×
   fewer); 20 000 steps in 73 min, the schedule annealed: validation recall
   0.963 / precision 0.78 against visible disks, fixture recall 1.000. The
   evaluation now scores the EXPORTED asset (Neural Engine, `--asset`) with an
   acceptance rule after refinement (edge exclusion, non-maximum suppression at
   minPeakSpacing by net score). **Bullseye, 143 positions, net minus classical
   per position (re-run after Gate B with the corrected acceptance rule,
   `run3-evaluate-gateB-thr0.{9,6}.log`):** at 0.9 median 0 (−10…+4; 416 vs
   442 peaks, 349 matched, NO pair beyond 0.5 px, 70/143 positions differ —
   the PNG shows the net taking disks the 5 % cut drops and skipping the ring
   side-lobes the classical detector accepts, while missing some faint disks
   the classical finds); at 0.6 median 0 (max +5; 501 vs 442); before the fix
   the same runs read 436 / 1 pair beyond 0.5 px and, at 0.6, +2 median with
   707 peaks — the difference is the fabricated positions. WS₂ as stored: net
   equals classical exactly (the beam only, both). Fixture after refinement
   0.967 / 0.244 px at every threshold (refinement decides), accepted 241 for
   153 eligible, precision 0.61.
   **The ceiling, from Swift on the same 2 100 bullseye patterns
   (`scan-bench-run5…8-gateB.log`, four Release runs after Gate B):**
   classical `detectAll` on 8 cores 0.105–0.113 ms/pattern (7–7.4 s per
   65 536); the width-12 `heatmap` asset through the CoreAI framework,
   input construction included, 0.13–0.156 ms/pattern; **the learned
   `detectAll` end to end, double-buffered so the CPU correlation overlaps
   the Neural Engine, 0.212 ms/pattern = 1.87–1.99× the classical** — at
   the ceiling, not under it; serial it was 2.3–2.6×. The overnight "0.6×"
   and the morning "0.89× / ≤ 1.9× by addition" are both withdrawn.
   **Owner's decisions (2026-09-07 afternoon):** threshold later, the
   ceiling accepted at "≤ 1.9×" (the measured end-to-end is 1.87–1.99×: the
   owner should know the accepted number is now the measured edge), the
   detector before any second model — `decisions.md`.
3. **On "reuse the platform for other models" (proposed 2026-09-07: precipitate
   segmentation, diffraction embeddings, ACOM shortlists, quality masks,
   PACBED thickness).** What is reusable today is the Python side: simulator
   pattern, train → export → ANE, the export checks. The app side — model
   loading, batching, provenance hash, reviewable predictions, sidecar
   labels — is step 4 and does not exist. Recommended: finish ONE model
   through step 4 before a second Python prototype, because step 4 is where
   the shared infrastructure gets built and Gate B'd. Per-pattern uses
   (embeddings, shortlists, masks) inherit the 0.3 ms-per-pattern cost and
   need their own ceiling; per-image uses (precipitate segmentation on
   virtual images) need labels, not the Neural Engine. The precipitate chain
   is already in `v3-plan.md` ("The precipitate chain"). Owner decides.
4. **Step 4, slice 1, landed on the branch 2026-09-07 late afternoon (owner's
   decisions: ≤ 1.9× accepted, threshold later, the detector before any second
   model; verdict in `decisions.md`).** `Core/ML/LearnedDiskDetector.swift`
   (DSTEMCore; macOS 27 behind `#if canImport(CoreAI)` + `@available`): loads
   the asset with the Neural Engine preferred, hashes it (`export.py`'s
   `sha256_tree`), normalises the three channels exactly as
   `simulate.model_inputs`, runs batches of 32, picks 3×3 maxima above the
   threshold in Swift, and hands candidates to the classical detector's new
   `correlation()` / `refine()` entry points (snap to the correlation maximum,
   the parabolic step, edge rule, non-maximum suppression at minPeakSpacing by
   net score, cap) — `detectAll(cube:…)` returns `BraggVectors` with
   `detector_class: learned` and the weights hash in provenance. The asset
   lives in `Models/DiskDetector/` (564 KB + its record) — NOT under
   `mac4DSTEM/`, where Xcode's automatic model compilation fails for the
   macOS 14 target; it is loaded as a raw file at runtime, bundling is the
   next slice. `mac4DSTEMTests/LearnedDiskDetectorTests` (3 cases) proves the
   normalisation against Python (≤ 2e-3), the committed asset's hash, and the
   whole Swift path against Python's picks and accepted peaks on the fixture
   (`tools/disk-detector/fixture/swift/`, 804 KB, from
   `write_swift_fixture.py`); broken three ways (channels swapped, peak test
   loosened, no snap) and each caught — the loosened peak test slipped past the
   first version, which measured recall only; an extra-picks bound now catches
   it. Unit gate NOT run (exit 69: 6 GB free against the 8 GB floor); the
   detector test classes run directly, 20/0 before Gate B
   (`test-diskdetection-contract-20260907.log`), 8/0 for the two learned
   classes after it (`test-learned-gateB4-20260907.log`).
   **Gate B ran (refuter's report in `gateB/`; its findings applied, its
   remedies re-broken by it before adoption):** (1) REAL DEFECT, shared by
   Swift and the Python reference so the fixture test was green on it — a
   candidate whose 5×5 snap lands on a correlation flank got py4DSTEM's
   parabola evaluated off-maximum, fabricating positions up to 28 px off (10
   of the fixture's 255 accepted peaks); fixed on both sides by py4DSTEM's
   own precondition (the snapped pixel must be an 8-neighbour maximum, else
   the candidate is rejected — "refinement rejects" is now a real rule),
   `fixture/swift/expected.json` regenerated (241 accepted), the bullseye
   numbers above re-run; (2) `detectAll` had NO test — the refuter's padded,
   multi-batch scan test is adopted (`LearnedDiskDetectorGateBTests`, four
   cases: NMS by net score, the cap, the maximum precondition, `detectAll`
   vs the direct path shifted by the crop origin), each re-mutated and
   caught; (3) four `DEVIATION` notes vs `get_maxima_2D` added to `refine`;
   (4) the quoted 0.123/0.110 benchmark numbers had been overwritten by a
   later run — the bench now stamps every output file; (5) `detectAll` had
   never been timed: 23× the classical at first (`NDArray(scalars:)` walks
   the generic Sequence, 83 ms per batch — replaced by memcpy through the
   views), 2.3–2.6× serial, 1.87–1.99× double-buffered (above).
   **Owed:** the UI option (`DetectorClass`), progress/cancel, the
   disagreement map, sidecar labels; patterns smaller than 128 px (returns
   nil) and larger ones reduced to the 128-px window about the probe centre
   (disks outside it are never proposed — the 250-px bullseye cube included;
   provenance says so); bundling the asset; the Xcode placement view. Three
   tooling traps:
   every new `Core/` file must be added to the app target's exception list in
   `project.pbxproj` (the app takes Core through the package, the synchronized
   group would compile it twice); the Python Core AI runtime and the Swift
   framework each fail to load on the ANE after the OTHER has written
   `~/Library/Caches/coreai-cache` — move the cache aside whenever switching;
   and never build an `NDArray` with `init(scalars:shape:)` on the hot path.
5. **Step 4, slice 2, landed on the branch 2026-09-07 evening (owner: "finish
   slice 2 first"; three parallel subagents, one build).** The learned
   detector is an OPTION in the app, off by default, macOS 27 only, and
   everything learned stays in `Core/ML/` (now two files), `Session/
   LearnedDetection.swift` (the one owner of the new state: detector class,
   threshold, the full-size probe image every kernel generation now records,
   the loaded detector, the last classical and learned runs), `Models/`, and
   the tests. `AppState` gained the owner handle only and lost a stored
   property (`braggPeakCount` is derived now); `runDiskDetection` branches on
   the class inside the same cancellable, detached, epoch-guarded structure
   (`LearnedDiskDetector.detectAll(data:…)` streams scan-row tiles exactly
   like the classical orchestrator); the Bragg map's on-screen provenance now
   carries the detector's own keys (`detector_class`, the weights hash);
   `runDiskDisagreement()` publishes the per-position count difference
   (learned − classical, `disk_disagreement`, diverging colormap) with a
   summary in the status bar. UI: one `Detector` picker in the disk
   configurator (`disk.detectorClass`), and only when Learned is chosen a
   threshold field, the model's hash, and `Compare with Classical`. The
   `.aimodel` is copied into the bundle as a plain folder resource (a
   synchronized-folder placement triggers Xcode's model compile, which fails
   for the 14.0 target). Tests: `LearnedDiskDetectionScanTests` (the count
   map, the IDs, the tiled scan against the resident call on a 4×4 fixture
   scan); five detector classes 23/0 (`test-slice2.log`); the tiled test
   broken once for real (tile offset dropped → 1 failed,
   `mutation-slice2-tile-offset.log`). **Unverified on screen** — the owner's
   drive: the picker, a learned run on the bullseye cube, the disagreement
   map, the inspector's provenance. **Owed:** Gate B on slice 2's `Core/ML`
   additions at the merge (one real mutation and the author's reasoning so
   far); sidecar labels (slice 3); the unit gate (disk floor); detectors
   below 128 px (the Al-Si-Mg cube is 64 px — the learned option returns a
   failure there, the classical path is unaffected).
6. **The owner's drive of slice 2 (2026-09-07 17:00–17:17, bullseye cube,
   file probe flat r = 7.4 px, min relative 5 %, the app's other defaults:
   spacing 7, edge 10):** the first learned run failed at the asset load
   with the runtime's generic error. Gate D on it: the sandbox refuted (a
   sandboxed probe with the same bytes in its bundle loads and runs), a
   second path in one container refuted (cache hit), and the owner's
   experiment confirmed the cause — the test host runs inside the app's
   container and had cached the asset from the repo path, which the
   sandboxed app cannot read; clearing
   `~/Library/Containers/com.mac4dstem.mac4DSTEM/Data/Library/Caches/coreai-cache`
   fixed it. Landed: the load purges that cache once and retries, and every
   Core AI step is named with its error code (`0cc91de` + this commit).
   Then: classical 101 289 peaks in 150 s (median 4 per pattern, range 1–70 —
   positions AT the 70 cap exist), learned 24 026 in 78 s (median 3, range
   0–11), disagreement 6 023 of 8 400 positions, learned − classical median
   −1, range −69…+6, the blue blobs on the map being the classical's
   capped positions. Both runs are IO-bound in the app (the cube streams;
   the bench's 0.1–0.2 ms/pattern is compute only) — a separate item. Two
   things the drive decided: (a) the learned detector sees only the central
   128 px of a 250-px detector, so the outer ring is partly out of reach and
   the count difference is not a verdict on the net — **owner decision:
   bin larger detectors 2× (disks shrink below the training range) or tile
   the crop (4× cost)**; (b) the owner could not judge candidates before a
   full scan — landed: with Learned selected the live rings on the current
   CBED come from the learned detector at the current threshold, and the
   picker and threshold re-run the overlay. Unverified on screen.
7. **Tiling landed (2026-09-07 evening; owner: "tiling for now, retraining
   in the docs").** A detector larger than 128 px is covered by a grid of
   128-px windows (overlap one disk diameter, ≥ 24 px; `windowOrigins`), each
   through the same pipeline, merged per position by refined intensity at
   minPeakSpacing, capped; provenance `learned_windows`, `learned_window_
   origins`. Tests: the grid formula and the merge (pure), a 256-px aligned
   two-pattern cube reaching both corners (exact), and a 232-px 2×2 cube with
   real content in the overlaps equal to the per-window direct path merged
   (exact; a first version compared against the isolated patterns and lost
   15/120 — the U-Net's receptive field reaches past the 24-px strip, so a
   neighbour's content moves borderline scores: the model, not the tiling).
   14/0/0 across the three learned classes (`tiling/test-tiling-mine6.log`);
   the shift-back broken once → 2 failed (`tiling/mutation-shift-rowcol.log`).
   **The ceiling with tiling, from Swift (`scan-bench-250.log`, 525 bullseye
   patterns at the full 250 px, 3×3 = 9 windows):** classical `detectAll`
   0.72 ms/pattern (250-px FFTs), learned end to end 2.03 ms/pattern =
   **2.81× — over the 2× ceiling at this detector size**, while finding 5.66
   peaks per pattern against the classical's 3.84 (the whole detector is in
   reach now; at 128 px it stays 1.90×). **Owner decision:** accept 2.8× for
   large detectors (both are far under the streaming time in the app), or
   fund a 256-px retrain (one pass; `README` "Retraining"). Also landed: the
   Core AI cache clash root cause and its fix — a cached specialisation in a
   sandboxed container goes stale (the test host wrote it; the app's own
   entry aged the same way) and then loads instantly but refuses its
   function; `AIModelCache.default.deleteEntries(for:)` clears it in-process
   and persists, `deleteAll` did not, and the failed model must be released
   before the retry; the tests now load the asset from the bundle, the URL
   the app uses, so app and test host share one entry. The precipitate
   specification is `docs/ai-ml/precipitates.md`; the retraining recipe is
   the detector README's "Retraining — when and how".
8. **"Everything code" (owner, 2026-09-07 night; four parallel subagents, one
   build, my check).** Code-complete on the branch, NONE of it verified on
   screen, Gate B owed on every new `Core/` piece at the merge:
   (a) **detector step 5, the labels** — `Session/DiskLabelStore.swift` (the
   sidecar owns them as one JSON attribute `mac4dstem_disk_labels`, preserved
   across rewrites by an additive change to `BraggVectorEMDWriter`; loaded on
   dataset activation), `App/AppState+DiskLabels.swift`, `UI/DiskLabelRows`
   in the learned block: confirm/reject the learned candidates at the current
   position, save, export to `~/Documents/mac4DSTEM/disk-labels/` for the
   fine-tuning loop (the owner copies into the gitignored
   `tools/disk-detector/labels/`); (b) **precipitates v1**
   (`docs/ai-ml/precipitates.md`) — `Core/Analysis/Precipitates/`
   (reflection finder on the Max pattern, off-lattice test when a basis is
   given; needle/particle segmentation: background flattening, Hessian ridge
   measure, robust threshold, 8-connected components, per-object length /
   width / orientation / area, edge flag; density with the refusal rule),
   `Session/PrecipitateProduct.swift`, `App/AppState+Precipitates.swift`
   (propose reflections → place the virtual detector on one → segment the
   shown scan image → density), `UI/PrecipitateSettings` in the Imaging
   inspector; `PrecipitateTests` 8/0 on a drawn fixture (needles at 37.2° and
   127.2° among others, edge cases, particles, the 64-px reflection fixture).
   The first length measure (4·√λ of the moments) read the drawn needles
   1.5× too long; the extent along the principal axis still read the short
   ones 8 px long (the ridge filter's spread past the tips); the extents are
   now taken on the flattened IMAGE over the half-maximum footprint — the
   test caught both, which is what it is for; (c) **diffraction groups,
   classical v1** (brief §6) — `Core/Analysis/DiffractionEmbedding.swift`
   (streamed binning, PCA by deterministic subspace iteration with
   Rayleigh–Ritz, no LAPACK, k-means++), `Session/DiffractionGroupsProduct`,
   `App/AppState+DiffractionGroups.swift` (`diffraction_groups` and
   `diffraction_similarity` products), `UI/DiffractionGroupsSettings` in the
   Imaging inspector; `DiffractionEmbeddingTests` 4/0 on a three-family
   fixture, the k-means assignment broken once → 1 failed
   (`mutation-embedding-groups.log`). Whole run: 45 test cases across the
   new and the detector classes plus the sidecar/gate classes, 0 failed
   after the length fix (`test-everything.log`, `test-precipitates3.log`).
   Owed: the owner's drive of all three; Gate B on the precipitate and
   embedding maths; recipe replay for the new runs (`recordReplayStep` is
   private to `AppState.swift`); the ridge measure is not elongation-
   selective (round sharp blobs respond too — the spec's open filter choice).
9. **The AI Analysis workspace (owner, 2026-09-07 night: "the advanced tools in
   their own room", "make sure the main app is clean").** A sixth sidebar
   workspace between Phase and Results (`WorkspaceArea.aiAnalysis`, ⌘5;
   Results is ⌘6 now) with three tasks — Precipitates, Diffraction groups,
   Learned disks — the same two panes as Imaging, its own inspector
   (`UI/AIAnalysisSettings.swift`, which also holds `LearnedDiskRows`), and
   a toolbar action per task (Segment / Group Patterns / Detect All Disks,
   the last forcing the learned class). The main app is clean of the AI
   features again: Imaging is back to its pre-AI state, Bragg disks carries
   no Detector picker and its action always runs the classical detector, and
   the learned live rings appear only inside AI Analysis. Products still
   land in Results with their provenance. Build clean; 22/0/0 on the
   precipitate, embedding, learned and classical-contract classes
   (`ai-workspace/test2.log`). Original app files touched by the whole
   AI/ML branch, for the record: `ProductWorkflow.swift`, `AppState.swift`,
   `mac4DSTEMApp.swift` (the ⌘ numbers), `WorkspaceView/Sidebar/Inspector`,
   `ImagePanes` (an empty-pane hint), `ResultExport` (fallback metadata for
   the three product kinds), `BraggVectorEMDWriter` (one preserved
   attribute), `DiskDetection.swift` (additive), `MapSettings.swift` (a
   comment), `LayoutPolicy`/`WorkspaceView` (the status bar). Unverified on
   screen.
10. **Housekeeping done 2026-09-07:** the status bar (owner's drive, 2026-09-07 evening: the
   run-time strip was cramped — the percentage wrapped to one character per
   line, the message to two lines): the message is one truncating line, the
   percentage has a `LayoutPolicy` slot like the metrics line (the fixed
   widths there are deliberate — the constraint-loop crash in
   `open-items.md` — and were never the problem; the two texts WITHOUT a
   width policy absorbed the whole squeeze), and the app/cube/residency facts
   hide while an operation runs. Presentation only, unverified on screen. the AGPL `yolov8n.mlpackage` (committed
   and pushed 2026-09-05 in the Sources build phase, referenced by no Swift
   file) is removed from the tree and the project; it stays in public
   history unless `main` is rewritten. The machine (8 GB) crashed once at
   12:26 when training ran alongside an ANE timing; run one heavy thing at a
   time. The Swift Core AI runner exists as `tools/disk-detector/scan-bench/`.
   Not done: Xcode's placement view; `run-tests.sh benchmark` is the serial
   CPU number and is not the baseline (scan-bench is).

## 2026-09-06 evening — the polish run

**A note on the dates.** The machine clock and git say this work happened on
**2026-09-06** (`73f5eb5` 22:12, `c5489ac`/`65fb084` 22:35, `b61ea73` 23:27,
CEST). The docs written the same afternoon — this file's name, the
"2026-09-07 closeout" it records — are dated a day ahead. Same day, two
labels; the evening's session is dated 2026-09-06 in the live docs.

Retained logs, owner-local and gitignored,
`References/training_runs/disk-detector-2026-09-06-polish/`: `drive-learned/`
(9 steps, bullseye, 16 captures), `drive-precipitates/` (11 steps, Al-Si-Mg,
22), `drive-groups/` (9 steps, WS₂ polycrystal, 8), `diagnosis-20260906.md`
(the read-only Gate D pass over D1–D5), `fix-a|b|c/` (the batches, their
break-first logs and Gate D records), `gateB/` (numpy twins, 13 mutations),
`core-gate-20260906.log`, and **re-drive: see `re-drive/re-drive.md`** (in
progress when this was written). The drives were **evidence, not
acceptance** — an agent drove with CGEvent clicks and per-window
`screencapture`; the owner's drive stays owed and every fix is unverified on
screen.

**Learned disks, six defects** (`drive-learned/`): no live rings at 0.90 /
0.70 / 0.50 at three positions (`03a`–`03c`); labels recording "0 candidates"
(`06-labels.png`); the full scan freezing the UI at 0 % with the clock stuck
at 2:04, 847/847 main-thread samples in `detectAll` → `dispatch_apply`
(`04-mainthread-sample.txt`); the picker overridden, so `Compare with
Classical` could never be enabled without leaving the room; four SIGSEGVs on
AX traversal (D4 below); an export help text promising `~/Documents/…` while
the sandbox writes the container (`07-save-export.png`). Held: the
disagreement map, the sidecar surviving quit and relaunch
(`08-after-relaunch.png`), no AI control in the classical rooms (`09-*.png`).
At Min relative 5 % (not the 0,5 % default): classical 58 236 peaks, learned
44 745, 6 618 of 8 400 positions differing; 8.2–10.8 against 54.8
positions/s — **~5× slower end to end** at 250 px on this loaded 8 GB
machine, where the bench says 2.81× compute-only.

**Precipitates, eleven defects, ten fixed** in `c5489ac` (`drive-precipitates/`):
the silent refusal before a Max pattern (`03a`); a hint naming a control this
room lacks (`02`); "24 off the matrix lattice" with no lattice basis (`03d`);
**P4, no reflection markers on Max / Mean / Current — NOT fixed** (`03c`: no
overlay exists to widen, so it is a new drawing); "Place detector" flipping
the task and blanking the inspector (`04`); the objects table's first 23 rows
rendering as reflection rows (`06a`–`06c`); "0 on edge" against "5 on the
edge" (`08`); a density outliving its calibration (`07`); Segment segmenting
its own label image on a second press (`11a`); nothing about the count
reaching Results (`09b`); cosmetics. Held: the 8.2 px reflection's dark-field
lit exactly one needle family (`04b`); 44 objects, 5 on edge, ≈ 8 s,
orientations −33°…−52°; density by hand, 39 / (330 × 330 × 1.53934²) nm⁻² =
1.511e-4 and 38 → 1.473e-4.

**Diffraction groups, seven defects, all presentation**, fixed in `73f5eb5`
and `65fb084` (`drive-groups/`): the main-thread freeze (698/698 samples in
`DiffractionEmbedding.compute`, 155–301 s, Cancel inert); the literal
"Diffraction groups (k)" name; no provenance shown anywhere; the similarity
reference never named and silently nilled by a rerun; a stale readout under
changed controls; a hint that can never render; the button/toolbar verb
mismatch. Held: k=4 sizes 2455 / 7372 / 4231 / 2326 summing to 16384, their
polygons reproducing the annulus dark-field taken at load; k=8 splitting the
7372-position group without disturbing the others at unchanged 79.4 %
explained variance; an identical rerun reproducing sizes, order and labels
(`08-rerun-determinism.png`); an honest similarity bar (−0.7738 … 1, cosine).

**The Gate D predictions.** *A2 (learned scan on the main thread) — held*:
predicted the progress callback would fire on main from inside
`Task.detached`, measured "5 of 5 calls";
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` made `detectAll` MainActor-
isolated because `nonisolated` on the class does not reach a member declared
in another file's extension. The groups half has **no experiment of its own**
— the re-drive's progress bar is its observation. *P6 (the first 23 rows) —
one account refuted*: id collision predicted the block starts at candidate id
1 (r37, c49) with objects resuming at #24; "emitted twice" predicted id 0
(r39, c48) and all 44. The captures show r37, c49 and #24. The refuter's note
stands — the unit "experiment" asserts the drive's own cardinalities and no
app-code mutation can move it, so **the captures are the evidence**. *C1 (the
eigensolver) — held, and too generous*: an eigenpair residual was predicted to
fail on HEAD and failed on all eight components (0.058–0.568 against 1e-6),
component 0 included. *C3 (+33 % width on diagonals) — held*: the drawn bar's
pixel-centre span is 2.9751 px for a 3.0 px bar at 37.2° and `widthPx` gave
3.7205, so the cause is the "+1" end-to-end convention, not the ridge filter
or the half-maximum level; four options, the owner's. *D4 (four SIGSEGVs in
`AccessibilityNode.accessibilityLabel`) — nothing established*: the four
`.ips` filenames cited exist nowhere on disk (a second agent searched), no
crash frame has been read, the branch's UI diff against `main` adds only
`.accessibilityIdentifier`, and the implicated Advanced-detection section is
pre-existing. No hypothesis is recorded, deliberately; a re-observation with a
retained report is owed, and the cheap discriminator is a bisect against
`main`.
