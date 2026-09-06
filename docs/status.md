# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | tagged 2026-09-02, never built; superseded, the tag stays as the pre-consolidation anchor | `CHANGELOG.md` |
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect (`open-items.md`), and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

## Where the UI stands

The v2.5 consolidation train and the presentation pass over the AppKit
window are finished and archived, with the window itself:
[`docs/archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md).
What that train left behind is the shape the app has now — `DSTEMCore` and
`DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`,
`ProductWorkflow.readiness`, `ACOMSession`, five workspace sidebars.

| Step | State | What it left behind |
|---|---|---|
| Bullseye: flat measured-kernel mode + the file's probe as a kernel source | done 2026-09-05, Gate D diagnosed, Gate B passed with findings applied, **unverified on screen** | `ProbeKernel.flat` = py4DSTEM `get_probe_kernel_flat` (normalise, Fourier-shift the centre to the corner; DEVIATION: a non-finite pixel counts as zero), `ProbeKernelMode` on every kernel and in both provenances, `.fileProbe` with `probePath`; `FourDDataSource.probeCandidates`/`readProbe` read the legacy (Qx, Qy, N) and the modern (2, Qx, Qy) `Probe` layouts, slice 0 either way. Parity on the bullseye file: 878/878 and 164/164 peaks with py4DSTEM's flat route at two thresholds, both sides pinned to (125, 125) (`scratchpad/parity/compare-0.05.log`, `-0.1.log`); the kernel at the app's own probe centre matches to 3e-6 (refuter's `refute-bullseye/flat/compare-pristine2.log`). Refuter's findings applied: two mutations survived every shipped check — an unwrapped frequency index (passed the integer-centre fixture and the parity) and a dropped conjugation (correlation became convolution; every radially symmetric check blind) — now caught by the fractional-centre/conjugate-transform fixture (`flat_kernel_fractional_centre`, 4.5e-8 / 6.7e-7) and an asymmetric unit test; the modern Probe layout was refused, now read (`p3` fixture); the UI defaulted to the trench, now flat; the stated mechanism corrected (the trench fails at the ESTIMATOR'S radii, not on bullseye probes as such). Mutations retained: five (mut2), four (mut3), two unit-suite (`unit-mutation-M1-20260905.txt`), all caught. Unit 485/0/1 (486 cases, MCP, `unit-mcp-flatkernel2`). `AppState` gained `generateFileProbeKernel`; nothing moved out. Not exercised by any check: the AppState glue itself (an x/y swap there would be invisible) |
| Detection threshold: the one-peak warning names the knob; the default is measured, not moved | done 2026-09-05, **unverified on screen** | `DiskDetectionScanSummary` carries the run's `parameters`; the median ≤ 1 warning names Min relative intensity (value, reference peak, both remedies) instead of "spacing or thresholds". One test, failing first on the old text (MCP log 18:22, passing 18:24). `AppState` touched at one call-site argument only — no responsibility moved out, said plainly. The `relativeToPeak` 0 → 1 default question is REFUTED by measurement on six training cubes (`det-experiment-20260905.log`, closure in `closed-items-2026-09.md`): WS₂ 1 → 45 peaks/position where ~13 are disks, sim_Au 3 918 and MgO 12 357 positions at the 70 cap — the reference collapses wherever the second peak is weak. Default unchanged; item closed. New observation: twisted bilayer graphene finds one peak at either reference (`open-items.md`). Unit 479/0/1 (480 cases, MCP route, `unit-mcp-detection-20260905.json`) |
| Origin measurement: the CoM window iterates and never cuts the beam's edge | done 2026-09-05, Gate D pre-registered (prediction met to 0.001 px), Gate B passed with findings applied | `measureOrigin` recentres its window on its own estimate (≤ 4 passes) in max(r·rscale, r + 1.5 px); DEVIATION from py4DSTEM's single pass noted in the kernel. WS₂ at the shipped rscale: 63.986 → 63.7375 against an independent 63.738. The refuter's numpy twin over ten training cubes: new values within 0.02 px of a wide-window reference on every clean cube, the old ones 0.25–0.8 px off; the shift depends on the beam's place in the block grid, not disk size (`q-calibration-design.md` §9, which corrects the "~0.3 px, small beams only" claim). `origin_measurement_truth` at 0.02 px (six mutations, the bounding-box clip survived 0.05 px); two-spec P4 equivariance tightened 0.65 → 0.001 px. Every origin-derived number can move, up to ~0.8 px mean on the training set — a v2.6.0 change |
| Q-calibration (a): the same-shell cluster mean replaces the per-pattern minimum | done 2026-09-05, Gate D pre-registered, Gate B passed with the mechanism corrected | `KnownCrystalQCalibration.estimate` averages the innermost shell's equivalents (band = derived separation capped at 8 %), both shells; `sameShellPeaksPerPosition` reports k. WS₂: cluster 18.902 px vs 18.901 from the independent 11-20 shell; the minimum was one spoke of a 0.26 px origin-fit offset (new open item). sim_Au: the reference shell is item (b)'s problem and Friedel pairs differ 2.4 %, so no truth claim there. `q-calibration-gate-test` 79 checks, 14 mutations; the scratch experiment harness and the refuter's dumps are in the scratchpad |
| Science lane: probe refusal, ACOM origin snapshot, selected-area fixture, CIF fingerprint | done 2026-09-05, Gate B passed with findings applied | `probeSize` → nil, `OriginCalibrationError.probeNotMeasurable`, finite-only at every step, `np.median` parity; `ACOMRunSemantics.originProvenance`; `selected_area_diffraction_partial_rows` with `2^scan` values and a 1 × 2 region (ten mutations, refuter's row-reversal included); `CrystalModel.contentFingerprint` recorded as `material_fingerprint`, `resolveMaterial` refuses a different CIF under a shared id. Refuter report and every mutation log in the scratchpad; closures in `closed-items-2026-09.md` |
| UI-review label findings (b)(d)(e)(f), minors, `PaneSplit` (a)(c) | done 2026-09-05, **unverified on screen** | Pattern statistics named for what is on screen (`PatternSourceLabel`); comparison panels carry a `Colorbar` (range, units, zero mark, masked swatch); cursor readout at four significant digits; ONE staleness verdict (`TaskProductState`, `ProductWorkflow.productState`) on the sidebar, the inspector and the strain/ACOM maps; scale bar never prints a unitless sampling as px (`ScaleBar.footerSampling`); no kernel → cross markers, not a 3 px circle (`PeakOverlayGeometry.radius` is optional). Both pane headers are `ViewThatFits` with an overflow menu; the divider fraction is `@SceneStorage`. Six unit tests, each broken first |
| DM4 Gatan STEM-SI import | fixed 2026-09-05, reviewed and reworked the same day; owner's GMS observation and re-drive owed | Empty positional labels resolve by physical sibling index (ncempy's rule, confirmed against ncempy on the real file); calibration domains distinguish detector-fastest from scan-fastest storage. `Si-SiGe.dm4` discovers as scan 77 × 17, detector 448 × 480, uint16, 2 nm / 0.06208537 1/nm — the roles are proven by the units and the survey rectangle; **the detector pair's x/y order is not** (`open-items.md`, Gate D). Review rework: full-cube read 19 s → 0.94 s (blocked transpose), undecidable units open the file without pixel sizes instead of refusing it, detector-fastest DM4 reports `.scanOnly` pushdown again, py4DSTEM's TitanX roll recorded as unported. Probe log `scratchpad/dm4-probe-20260905.log`. **Evening:** the `realslices` refusal its own harness check demanded (`read_v0_12.py:373-388`) was never in the reader — a legacy strain stack opened as a cube with a 4-px detector; the rule now names both v0.12 slice collections and `datacube-discovery-test` is green again |
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert (`open-items.md`, the constraint-loop entry), which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **unverified on screen** | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| The output log moved off `AppState` | done 2026-09-04, **unverified on screen** | `ActivityLog` (`App/ActivityLog.swift`) owns the strip's buffer: the filter, the no-repeat rule, the 300-line cap and the stamp, on an injected clock. `AppState` 495 → 494 stored properties. `@Observable` on it is load-bearing — with the annotation removed, five of its six tests still pass and the strip silently stops updating, which is why `ActivityLogTests` asserts the chain with `withObservationTracking` (the repo's first). Toggling the log from the status bar is the five-second check |
| Saved-session sidecar contents moved to the LEFT sidebar | done 2026-09-04, **unverified on screen** | `Section("Saved session sidecar")` is gone from `WorkspaceInspector`; the sidecar filename, Calibration, BraggVectors, the saved-result rows, Apply Saved Controls and Change…/Ignore… render in `WorkspaceSidebar`'s `Section("Session")`. Info keeps only the unreadable / does-not-fit sections — the explanation half of the split. Builds clean with no warnings and no test names the moved identifiers, which is also the limit of what any gate can say: this is placement, and only the owner's eyes close it. One judgement call to overrule or keep — Remove is now the result row's context menu, not a second visible row per result (`open-items.md`) |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| DM4 harnesses | **`dm4-robustness-test` exit 0 (8 checks), `load-spec-test` exit 0 — 2026-09-05**, logs `scratchpad/dm4-robustness-20260905.log`, `scratchpad/load-spec-20260905.log`; four mutants each failed the robustness harness first (`closed-items-2026-09.md`). The full `scientific` gate was not rerun: these two are the harnesses that compile the changed reader. |
| `run-tests.sh unit` | **485 passed / 0 failed / 1 skipped, 486 cases, SUCCEEDED — 2026-09-05 late evening, bullseye tree**, XcodeBuildMCP `test_macos` (`scratchpad/unit-mcp-flatkernel3-20260905.json`); the script route refuses below 8 GB free. Same day: 479/0/1 detection threshold (`unit-mcp-detection`), 478/0/1 origin kernel (`unit-mcp`), and the earlier `run-tests.sh` runs 478/0/1, 477/0/1, 472/0/1, 463/0/1. Two unit-suite mutations retained (`unit-mutation-M1-20260905.txt`). |
| `run-tests.sh scientific` | **43 harnesses, exit 0 — 2026-09-05 late evening, the bullseye kernel + probe-source tree**, `scratchpad/scientific-bullseye3-20260905.log`, `PYTHON=$HOME/miniconda3/envs/py4dstem/bin/python`. Two refusals before it on the same tree: exit 69 at 3.9 GB free against the 4 GB science floor (cleared by `free-space.sh --clear`: 1.1 GB of MCP test products), then `calibration-test` failing to compile because the new probe API returned `DiffractionPattern`, a type that harness does not include — narrowed to `[Float]`. Earlier the same evening: 43/exit 0 on the origin kernel (`scientific-origin3`), after two red harnesses fixed (`datacube-discovery-test`, `peak-overlay-test`). |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-06, clean tree at `c2fa3c1` (`scratchpad/inventory-20260906.log`): gated 45, diagnostic 9, cold-start set **1 295** (from 996: the learned-detector pre-registration §3a written at full length by owner instruction, 2026-09-06), live markdown 4 780 (from 4 468, same cause). No new files. Previous: 2026-09-05 late evening, dirty tree, `scratchpad/inventory6-20260905.log`. |
| `tools/package-test/run.sh` | **exit 0 — 2026-09-04.** Clean-builds a hardened Release and audits the artefact: nested signatures, sandbox/read-write/bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version `2.5 (4)` with the deployment floor — both DERIVED from the project. The floor assertion and its success message were both literal `26.0` and both wrong after the floor moved; the message said "macOS 26 floor" while passing against 14.0 |
| `run-tests.sh all` | **exit 0 — 2026-09-04, post-release tree** (458 passed / 0 failed / 0 skipped, 44 harnesses, `real-data-acceptance` and `package-test` included). The release-tree attempt exited 1 at `real-data-acceptance`; that sidecar instance was diagnosed and closed as a stopgap then, and the wider discovery class was subsequently closed on 2026-09-05. Two recorded traps hit again: the background task's exit code was 0 while the gate's own `GATE_EXIT` line said 1, and the unit count read one short because an xcodebuild timestamp interleaved mid-test-name — reconciled against the source file's method count, never assumed |

## The v2.5.0 / v2.5.1 release night

Both shipped 2026-09-04; the plan, its two self-corrections and the artefact
provenance are
[`docs/archive/v2/release-2026-09-04.md`](archive/v2/release-2026-09-04.md).
The live facts are the Releases table above and `CHANGELOG.md`.

## Handoff (rewritten 2026-09-07 on the branch `ml/disk-detector`, after the overnight run of §3a steps 1–3)

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
5. **Housekeeping done 2026-09-07:** the AGPL `yolov8n.mlpackage` (committed
   and pushed 2026-09-05 in the Sources build phase, referenced by no Swift
   file) is removed from the tree and the project; it stays in public
   history unless `main` is rewritten. The machine (8 GB) crashed once at
   12:26 when training ran alongside an ANE timing; run one heavy thing at a
   time. The Swift Core AI runner exists as `tools/disk-detector/scan-bench/`.
   Not done: Xcode's placement view; `run-tests.sh benchmark` is the serial
   CPU number and is not the baseline (scan-bench is).

v2.5.1 is published and verified from its own download link. Both repos are
pushed; the site says macOS 14+ and serves the build that can honour it. Push
state is not recorded here — it went stale twice in two commits; ask git.

**Read this first: item 1 is the owner's and `/pickup` cannot take it.** An
agent should say so and start at item 2.

1. **Your drive. (OWNER ONLY.)** Nothing beyond Prepare, Imaging and Strain &
   ACOM has been looked at since the AppKit retirement, and five sessions
   running have found defects by driving that every gate was green through.
   Bugs enter via `/diagnose`. Worth going at first: Phase's stages, the load
   configurator's crop drags, the Results comparison row, the colorbar popover,
   and every divider — the pane split is hand-built and **no gate can see a
   column's width** (falsified, `open-items.md`). Still unverified on screen:
   a cropped save → quit → reopen (S1's crop restore), and **right-clicking a
   saved result in the sidebar's Session section to find Remove** — the rows
   themselves the owner drove and approved, the context menu nobody has opened.
2. **Two owner observations, both on `Si-SiGe.dm4` and Prepare**
   (`open-items.md`): open the file in GMS and read the pattern's width and
   height (the detector-pair Gate D item), and drive the manual Q/R fields
   after their rows turn green, in Prepare and in the export sheet.
3. **Drive the UI-review fixes and the pane headers** (`open-items.md`):
   the four label findings, the two minors, the compressible headers and the
   remembered divider all landed 2026-09-05 with tests and no screen time.
4. **The science lane, one item at a time.** Landed 2026-09-05, each
   through Gate B with an independent refuter whose findings were applied
   and re-broken: the origin-fit guard's hole (a), the ACOM origin-provenance
   snapshot, the selected-area mask fixture (`closed-items-2026-09.md`) and
   the CIF id collision (b). Also landed: Q-calibration (a), the
   minimum-radius bias, by a pre-registered Gate D on `polycrystal_2D_WS2`
   and `sim_Au` and a Gate B whose refuter corrected the mechanism (an
   origin-fit offset, now its own open item) and added two fixture checks
   (`q-calibration-design.md` §8). Also landed the same evening: the origin
   measurement's 0.26 px offset that the Q-calibration refuter found
   (`q-calibration-design.md` §9). Next, in order:
   the detection-threshold item, closed by measurement (the default flip
   floods noise). Bullseye disk detection: two of three fixes landed (flat
   measured-kernel mode, the file's probe as a kernel source; parity with
   py4DSTEM's flat route), the probe-size under-read on ring-shaped probes
   stays open, and the owner's drive of the bullseye maps closes the item.
   **The learned detector, `v3-plan.md` §3a: steps 1–3 ran overnight
   2026-09-06/07 on the branch `ml/disk-detector`** (simulator + committed
   fixture proven and broken four ways, `run-tests.sh inventory` exit 0 with
   `disk-detector` gated; U-Net trained 80 min + a 55-min anneal; nine Core AI
   assets + Core ML insurance, pixel-checked and timed on the idle machine;
   step 3 numbers on the fixture and both real cubes). **Next: step 4 slice 2 on the
   branch — the detector option in the UI with provenance, progress and the
   disagreement map, then the sidecar labels (Gate B on slice 1 done
   2026-09-07); the full discipline returns at the merge. The
   cross-feature direction is `docs/ai-ml/README.md`.** ACOM coverage
   (a) is an owner decision, relabel or convert; Q-calibration (b) and the
   origin-fit holes (b)/(c) as design passes. A landed number change cuts
   v2.6.0.

**macOS 14–25 is compile-verified and has never been executed.** The floor is
14 in the build and published as such; every machine here is 26. A VM would
close it and needs ~40 GB. Until then the first report from an older system is
the real test — both README and site ask for the macOS version.

**The rule bought the hard way** (`open-items.md`, the constraint-loop entry):
nothing inside a split column may repeatedly change its own minimum size.
`.fixedSize()` on text whose string changes is the easiest way to do it by
accident, and it only shows on a dataset big enough for an operation to tick.
All 12 bare `.fixedSize()` sites in `UI/` are audited and contained.

**Two traps that bit again on release night, both already documented.** A
BACKGROUND TASK reported exit 0 while the gate's own `GATE_EXIT` line said 1 —
read the gate's line, never the wrapper's. And the unit count read one short
twice because an xcodebuild timestamp interleaved mid-test-name; reconcile
against the suite's method count in source, never assume a test vanished.

**Driving, and its two limits.** `open -n <Debug app> --args --demo-fixture`,
`screencapture -x -o -l <window id>` (per-window needs no consent). The app's
defaults live in its sandbox container and TCC blocks writing them; synthetic
keystrokes only land while the window is frontmost. Fastest loop: the owner
drives and pastes the result.

## Owed to the owner

- **Drive the rebuilt app** (above) — two things unverified on screen.
- The §10g decisions and plan §8 (sidecar wire format).
