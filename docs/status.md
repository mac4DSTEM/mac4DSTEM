# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from dated runs.

**What a log name in these rows is** (settled 2026-09-09). Names like
`unit-c7s2-20260908.log` identify the run a number came from. They are not
paths a reader can open: session logs live in the gitignored session
scratchpad and are not retained past the session. They were written with a
`scratchpad/` prefix until 2026-09-09, which promised a file that was already
gone in all 24 cases; the prefix is removed so a name reads as a name. What a
reader reproduces is the gate, not the log — `tools/run-tests.sh` is the only
thing that knows the harness count. Evidence a reader must be able to open is
committed under `docs/archive/`, and the inventory gate fails on a repo-rooted
path a truth doc cites and does not have. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | named 2026-09-02, never built, superseded by v2.5.0; a local tag exists on this machine and was never pushed, and none will be (C0 (4), `decisions.md` 2026-09-07) | `CHANGELOG.md` |
| v3.0.0 | **released 2026-09-11**, version/build 3.0.0 / 6 — the learned disk detector, the flat/file probe kernel, and the first build that is arm64 alone. Built from `3c4b82c` with `Developer ID Application: Paul Lobpreis (3B8SMSSAX4)`; app notarization `e9a64b93-c63f-462f-a423-fa2ef56eeb31`, DMG `5205d722-712c-4c5a-bbbc-35d117dbb0f7`, both **Accepted** and stapled, `spctl` accepted on both, `source=Notarized Developer ID`. DMG SHA-256 `cf2259a3016db7d32f9805db724b358cf23b153bab2d547839dcd9e9bd651b89`, **5 030 916 bytes** — *smaller* than v2.5.1's 6 157 051 because the Intel slice is gone. Verified by mounting the image: the app inside is `arm64` alone across the executable and all three embedded dylibs, 3.0.0 (6), `LSMinimumSystemVersion 14.0`, `LICENSE` and `NOTICE` both present, stapled ticket validates. **Record the post-staple hash, not the one `make-dmg.sh` prints** — stapling rewrites the image, and the pre-staple hash was `95b53779…fb1e`. Gated on `all` exit 0 (46 harnesses, 573/0/2 = 575) and `inventory` exit 0 on the same tree. Known limitations are stated in `CHANGELOG.md` rather than left to be found | `CHANGELOG.md` |
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect (`open-items.md`), and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

The release night of 2026-09-04 (plan, two self-corrections, artefact provenance) is [`archive/v2/release-2026-09-04.md`](archive/v2/release-2026-09-04.md).

## Where the UI stands

The v2.5 consolidation train and the presentation pass over the AppKit
window are finished and archived, with the window itself:
[`docs/archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md).
What that train left behind is the shape the app has now — `DSTEMCore` and
`DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`,
`ProductWorkflow.readiness`, `ACOMSession`, five workspace sidebars.

| Step | State | What it left behind |
|---|---|---|
| Clicking an Imaging pane selects it again | done 2026-09-11, **no Gate D** (neither trigger: presentation only, and the cause was established from `decisions.md` and `archive/consolidation-plan.md` §4(5), not guessed). **Driven and confirmed by the owner the same day** — he reports it good; the three gesture-composition checks named in the request (detector drag, scan scrub, ROI handles) were put to him and he reported no problem. Reverses two recorded decisions: 2026-09-04 retired the pane focus model and C4(c) cut the click path as review finding #5. Reversed because the review's premise was wrong about the platform — selection driving the inspector is the Xcode/Keynote idiom, and the confusion it was blamed for (nothing showing WHAT was selected) had already been fixed by the accent outline the owner asked for in the same week | `SelectsPaneOnClick` in `UI/ImagePanes.swift` — a `simultaneousGesture(TapGesture())` on each pane so it composes with the detector drag, the scan scrub and the ROI handles rather than swallowing them, and a tap rather than a zero-distance drag so a drag passing over a pane cannot steal the selection. Writes `activePane` directly, the idiom the ROI handles already use, keeping it out of `AppState`'s measured budget |
| D002 and D003, the register's two standing CRITICALs | done 2026-09-09, **Gate D on both** (both triggers each: a scientific number can move and no cause was established); an independent refuter **overturned one claim and narrowed another**. Evidence [`archive/2026-09-09-review/d002-d003-gate-d.md`](archive/2026-09-09-review/d002-d003-gate-d.md). D002: ptychography built an axis-aligned raster and never read `rotationRad`/`transpose`, although `ParallaxPhysicalCalibration.resolve` refuses to build without a rotation — measured bit-identical positions at 0° and 30° on a NON-square crop, against 11.16 object pixels (17.6 for the full convention) on a scan spanning 35.2. Now ports py4DSTEM's `_calculate_scan_positions_in_pixels`; the axis mapping was checked, not assumed (py4DSTEM's axis 0 is this app's COLUMN). D003: `H5Aread` reads a whole attribute into a one-value buffer — 24 bytes into 8, 32 into 9, `H5Aread` returning SUCCESS every time, stack corruption confirmed by sentinel probe; a 3-element `Q_pixel_size` silently yielded `qSize 0.25`. **The crash claim was overturned**: it crashes one prebuilt binary 40/40 and a fresh build of the same sources survives 40/40, so it is allocator-layout luck, not reproducible. Reachability is real by reading but no real writer of a multi-element `units`/`name` was found — stated as unproven. **Gate B PASSED 2026-09-11** and was not a formality: 25 mutations, and **four survived** — the scan step could be hard-coded to 1.0, squared, the reciprocal sampling hard-coded, and the origin ignored, each leaving the whole gate green, because all seven cases ran at scanSampling 1.0 / qSampling 0.05 and nothing read an amplitude. Closed by case 7 (37.2 deg, transpose, both samplings unique) and an analytic origin invariant; the refuter's own remedy for the origin was **rejected as vacuous** after being tested and replaced. The axis-mapping comment was refuted as a non-sequitur citing py4DSTEM's transposed branch and is rewritten on the gradient pairing. The port itself reproduces py4DSTEM's real `AffineTransform` to zero at float32 precision. Gates: `all` **exit 0 2026-09-11** (`all-gateb-20260911.log`, `GATE_EXIT=0` on its own line), 46 harnesses, zero FAIL, unit 571/0/2 = 573 = `func test` in source. | `PtychographyPreparation.swift` rotates/transposes/clips positions with an inline `DEVIATION` for the padding; `H5Reader.attributeIsScalar` guards all three attribute readers; `sources.manifest` compiles `PtychographyPreparation.swift` in a gated harness for the first time (closes `tools-gates-05`); `singleslice-ptychography-test` **+8 position cases with 21 planted wrong conventions**, plus an analytic origin invariant (an integer origin shift must equal a circular shift of the resampled amplitudes) that is the only thing reading an amplitude from `prepare` and the only executable statement that `originQX` names the ROW; `datacube-discovery-test` +`d1_multielement_attributes.h5`. Gate D's mutation table said five mutations where **four** distinct transformations exist — a wrong rotation sign and a transposed axis mapping are the same edit here, which is why both reported an identical 17.600004; corrected in the evidence doc |
| The 2026-09-09 review: 11 clusters fixed and gated, 259 records deduplicated | done 2026-09-09, **no Gate D** (neither trigger: git plumbing, a CI checkout depth, a build setting, licence texts, greps and docs — no scientific number can move, and every cause is proven by a reproducing observation). Eleven register clusters closed, each fixed AND held by a new `run-tests.sh inventory` check, each with a negative control run after the fix. **D001** the shipping Core ML model spec was never committed — `.gitignore:33` `*.mlmodel` matched it beneath the `!…mlpackage` negation, because re-including a directory does not re-include the files under it; reproduced exactly, the asset tree hashes `0f53d270…b641ab` here (the record's number) and `62b0215f…0f003` without the spec, which is what every clone and the CI `unit` job compute. **D007** the CI `inventory` job could never pass — `actions/checkout` clones at depth 1, `git show HEAD^:…` failed into `\|\| true`, and the whole 7 509 lines read as growth; reproduced in a real `--depth 1` clone, the read now refuses a base it cannot resolve, and the job takes `fetch-depth: 2`. **D009 + D014** `NOTICE` promised licence texts that were in no bundle and in no clone: the two upstream texts are now in `Licenses/`, ship at `Contents/Resources/Licenses/`, and NOTICE states each dylib's SHA-256, size and declared version. **D064** `ARCHS` was `arm64 x86_64` against arm64-only dylibs; pinned to `arm64`. **D114** `releasing.md`'s "free of Homebrew paths" was too strong — no load command carries one, but `libhdf5.dylib` still holds the Homebrew build stamp, which is how its 2.1.1 identity is now established from the binary. **D109** the "AppState stored properties 491" metric counted function locals and computed properties; it counts type-scope declarations (166) and says so. **D051 + D112** every evidence citation and three stale pointers. Also: `inventory` exited 1 on the clean tree on status.md's own "Nothing is uncommitted" — a negated claim matching the positive-claim grep. **Verified, not assumed:** Debug and Release builds both exit 0, `lipo -archs` on the Release binary is `arm64` alone, and both licence texts and the model spec are in the built `Contents/Resources/`; `LearnedDiskDetectorTests` **8/8 passed, 0 skipped** under the new project settings, `testCommittedAssetHashMatchesItsRecordAndTheFixture` among them. **Two traps paid here.** A `grep -v` added for message polish returned 1 under `pipefail` and aborted the gate function printing nothing — found only because the negative control was re-run after the polish. And the Xcode 26 test line is `Test case 'ClassName.testX()' passed`, without the `-[Target.` prefix: the old reconciliation grep counts 0 and the run looks empty when it is green | Six checks in `inventory()`, no new tool directory — that function already is the repo's own review. **Bundled folder references:** every file under a pbxproj `lastKnownFileType = folder` (`Models/DiskDetector`, `Licenses`) must be tracked, named with the ignore rule that swallowed it. **Redistributed binaries:** every committed dylib is named in NOTICE, its SHA-256 there matches the file, and no load command carries an absolute path. **Truth-doc paths:** a backticked path rooted at the repo or at `mac4DSTEM/` must exist; only tokens with an extension or a trailing slash are judged, so `UI/ContentView` as a type name does not fire. Three exemptions with their reason in the comment: plans and designs name what does not exist yet, `CHANGELOG.md` names what existed at a past version, `scratchpad/` is gitignored by design. Plus the C5 base-ref guard and the negated-claim fix. New files: `Licenses/HDF5-LICENSE.txt`, `Licenses/libaec-LICENSE.txt` (verbatim upstream, and the app must carry them), and [`docs/archive/2026-09-09-review/`](archive/2026-09-09-review/register.md) — **259 records, 174 defect claims, 156 clusters**: 11 fixed, 16 repeats and 8 possible repeats of the 2026-08-31 review, 8 already tracked, **113 new and unverified** |
| Four small fixes from the drive | done 2026-09-09, **no Gate D** (neither trigger: a plist declaration, a save-panel seed string, one view's row order, one caption moved; no scientific number can move). One new test, **broken first** by a mutant that keeps the extension — exit 65, then exit 0 on the real code, `HDF5Types.swift` reverted `cmp`-identical (`drift/seed-{mutant,real}.log`). Signed build exit 0. **`Size (f32)` is now `Size as float32` in both places.** A FIFTH fix was proposed and DROPPED on inspection: adding `.accessibilityLabel()` to the in-body controls would restate titles they already carry in source — the AX emptiness and the crash are one defect in SwiftUI's label resolution, so that is one Gate D, not six modifiers | `mac4DSTEM/Info.plist` declares `CFBundleDocumentTypes` for h5/hdf5/emd/dm4/dm3/mib at `LSHandlerRank Alternate` (`raw`/`xml` deliberately excluded — too generic to claim); `INFOPLIST_FILE` set on both app configurations while `GENERATE_INFOPLIST_FILE` stays YES. **Verified in the BUILT Info.plist, not assumed**: every generated key survives, `LSMinimumSystemVersion` still **14.0** — the whole point of v2.5.1. `SessionSidecarFormat.savePanelSeedName(for:)` drops the extension `NSSavePanel` re-appends, ending `.mac4dstem.h5.h5` on first save; the helper lives in `Core` so `ResultExport.swift` changed one line and did not grow. `MapSettings` renders `summary.warnings` BEFORE the count rows, so the median ≤ 1 warning is no longer below the fold. Info's orphaned "Reloads the whole cube" sentence and its duplicate `PromoteRunCaption` moved to the button they describe, in Settings. **All four unverified on screen** — the owner drives | 
| The delegated drive, two personas, and the app-path measurement | done 2026-09-09; **no code changed, findings only** (owner: drive + triage this session, fix next). Driven from the shell via Accessibility — the computer-use MCP was denied twice, from a subagent AND the main session, so the OS dialog refused, not the agent. A Sonnet agent drove; screenshots reviewed here. 87 shots, 18 findings, evidence `archive/v3/drive-2026-09-09.md`, toolkit `drive/drive.sh` (menu / clickwin / shot). **Reviewed, not relayed**: the agent's headline — WS2's 1-peak-per-pattern result "presented as success with nothing to distinguish it" — was CORRECTED here against its own screenshot (the funnel, an amber warning and `summary.warnings` all render; the defect is that the warning block sits below the fold and Strain unlocks anyway). Reached: every workspace, both detectors, a real 248 111-peak Si_SiGe run, the A/B compare, Remove's confirmation, the sidecar round trip. Not reached, all one cause — synthesised clicks do not register on disclosures, sidebar sub-pages or the Metal diffraction pane: every `Advanced` section, Strain/Orientation/Parallax/ptychography, the CIF import, disk-centre labelling, and Phase E's four failure paths | Three findings no persona was needed to surface, all new: **reading an accessibility label crashes the app** (two crash reports, identical stack — VoiceOver would crash it, Gate D owed); in-body controls carry **no accessibility label** while toolbar items do; and **no `CFBundleDocumentTypes`**, so a `.h5` cannot be double-clicked open — the root cause of the proxy-icon papercut. Plus: the one-peak warning is below the fold, `Size (f32)` sits under `dtype uint64` unexplained, and there is no glossary for probe kernel / ACOM / R–Q rotation. Confirmed GOOD and worth keeping: the origin fit reports `Fit RMS 9.72 px … exceeds probe radius; recalibrate before quantitative use` instead of going green, A/B compare REFUSES to diff incompatible units, the neural-net ETA tracks and cancels cleanly with `no peaks were published`, and the sidebar distinguishes "from earlier analysis" from "Computed this session" | 
| The `all` gate's candidate-count drift, diagnosed and closed | done 2026-09-09, **Gate D** (both triggers: a scientific number moved and the cause was not established); an independent refuter reproduced every link and **overturned two claims**. Cause: `ba6360d` (2026-09-05) corrected `probeSize`'s median to `np.median`'s even-count rule, so the pinned goldens were three days stale — the app is the correct side. **No code changed**; `expected.json` re-pinned and `calibrationData_bullseyeProbe.h5` newly pinned. `all` **exit 0** (`v3-gate/all-20260909.log`, `GATE_EXIT=0`), 46 harnesses, unit 571/0/1 = 572 cases against 572 `func test`. Bisect `ba6360d^` exit 0 / `ba6360d` exit 1; causal control — reverting only the median line restores both radii bit-for-bit, revert `cmp`-verified; independent numpy twin 2.0076250 / 7.1286265 (float64) against HEAD to 1.3e-7 / 8e-7 (`drift/e4-probe-truth-20260909.log`). One new test, broken first by a `sorted[n/2]` mutant (exit 65, the ONLY test to fail — the six existing `ProbeSizeTests` were blind to the rule). Nothing on screen; nothing to see | The four Si_SiGe fields and a fifth pinned cube in `tools/real-data-acceptance/expected.json`; `ProbeSizeTests.testProbeSizeUsesNumpysEvenCountMedianForTheTrustedBand` pins the even-count rule below the `all` gate, where nothing pinned it before. **Refuted and recorded** (`archive/closed-items-2026-09.md`): two of five cubes drifted, not one of four — the unpinned bullseye cube moved invisibly, and the session's own diff tool shared the gate's blind spot; and "the final science output does not move" is FALSE — peak positions shift subpixel on Si_SiGe and one bullseye disk is substituted ~26 px while the count holds at 11, which this harness cannot see (`open-items.md`). **The app's own pipeline was measured on 2026-09-09 and does NOT move**: `origin-fit-diagnostics probe-size` feeds the real `OriginCalibration.probeSize` with `meanDP` and prints the shipped `app tiledRun probeRadius`; under both median rules it is identical on four cubes — Si_SiGe 3.738, WS2 1.858, sim_Au 5.113, bullseye 6.843 px (`drift/apppath-{new,old}median-20260909.log`, `apppath-bullseye-{new,old}.log`), and bullseye's `maxDP` 11.223 px matches too. The drift was confined to the acceptance harness's own max-of-three input. Caveat: printed at 3 decimals, and only the probe radius — not the full origin fit or Q-calibration |
| C4 (c): exposure, action placement and explicit failures | implemented 2026-09-08, **screen verification blocked**; no Gate D trigger (presentation, error reporting and mechanical preview/inventory deduplication; no Core change). Three lower-tier slices reviewed and corrected here. Script unit/all **exit 69** (3/2 GB free); documented warm MCP fallback **570 passed / 0 failed / 1 skipped**, signed Debug build succeeded (`c4c/warm-test-final-20260908.{log,json}`, `build-signed-20260908.{log,json}`); no new tests. Final build additionally enables initial delivery of an already-failed configurator preview to the status strip; that one-line modifier is compile-verified after the unit run. C4(b)'s owed `virtual-detector-test` and `two-spec-analysis-test` each **exit 0** (`c4c/*-retry-20260908.log`; initial sandbox attempts could not write the Metal cache). Inventory exit 0, AppState + ResultExport **7509**, unchanged | Default-collapsed Advanced disclosures persist per window; dimensionless disk/parallax/ptychography knobs moved inside them. Contrast/gamma, retained-product actions, promote/reopen/release moved from Info to Settings; Dataset menu owns sidecar actions, Change remains the refusal recovery path. Pane clicks and scrubbing no longer select Imaging Direction. Both Remove entry points and both Resets confirm. Preview/ROI/inventory failures report reasons; PendingLoad owns preview error capture, inventory refresh is shared, cancellation/epoch guards retained. Budget partly paid by replacing historical comments in these touched paths with present-tense invariants, not an OperationCenter extraction. Native app control **works from this session** (the previous session's CUA failure did not reproduce): the delegated drive ran 2026-09-08 evening on `mac4DSTEM Demo.h5`; its screenshots (`c4c-drive/`) were session evidence and are not retained. **Seen on screen and holding:** Info is metadata only (contrast, gamma and the retained-product actions are gone from it); Prepare, Imaging, Bragg disks, Phase and Results each expose one primary action bound to readiness (`Compute Mean / Max`, `Compute Image`, `Detect All Disks`, `Run DPC`, `Save to Results`) with no "Update Image" or "Reconstruction Ready" anywhere; the collapsed `Advanced detection` disclosure opens to `Pattern smoothing s` and **is still expanded after leaving to Prepare and returning** (the remembered-across-visits clause, verified by re-test after a focus-loss confound produced a false collapse); Phase's Parallax and ptychography stages carry `Advanced` badges; the C7 `Detector: Classical` picker sits in Disk detection. the Dataset menu carries all four sidecar actions under their C4(c) names (`Save Current Result to Session Sidecar`, `Save Calibration to Session Sidecar`, `Change Session Sidecar…`, `Ignore Session Sidecar…`) and the sidebar no longer does. **Trap paid here:** the first drive showed no Dataset menu and the pre-C4(c) File-menu names although the binary's mtime was newer than the source's — mtime does not prove freshness; a rebuild (`c4c-drive/rebuild-20260908.log`, exit 0) settled it, and no source was edited on the stale evidence. **Still unverified on screen:** the four failure paths and the Remove/Reset confirmations. No new tracked file; this row is the evidence home. |
| C4 (b): staleness generalised — one verdict from the recipe | done 2026-09-08 night (a Sonnet slice in a worktree from the read-only plan `s4/c4b-staleness-plan.md`, patch applied to `main` and gated here), no Gate D (neither trigger: verdict/presentation logic, argued in the plan §6); unit **570 / 0 / 1, 571 cases** exit 0 (`c4b/unit-c4b-main-20260908.log`, 571 `func test` in source); core exit 0 (`c4b/core-c4b-main.log`); inventory exit 0 (`c4b/inventory-c4b-main.log`, `AppState` + `ResultExport` **7509**); six new tests each broken by a named mutation in the worktree (`c4b/mut1…6.log`; mutation 6 crashed the process on the force-unwrap the guard prevents), reverts `cmp`-verified; the worktree's `virtual-detector-test` and `two-spec-analysis-test` could not run there (no `References/py4DSTEM-dev` in the worktree) and were NOT re-run on `main` — owed; **unseen on screen** | `ProductWorkflow.stalenessVerdict(recordedStep:currentSignature:hasProduct:)` → `.current` / `.stale(changedKeys:)` / `.unknown`: the recipe step a product was made from against the signature the current settings would record, restricted to the signature's keys; a kind with no signature builder is never stale; a product whose step the recipe invalidated is stale. Builders on the owners: `Aperture.replayParameters(shape:aperture:)`, the dpc origin one-liner, `StrainProduct` (the two input keys, never `resolved_g*`), `ReplayStepPlan.ACOMReplayPlan.currentSignatureIfResolved` (nil without a model), disk detection = `DiskDetectionParams.replayParameters(kernel:)` + the learned class/threshold/hash (the old flag missed all three). `TaskProductState.staleDiskSettings` → `.stale(reason:)` with a generated reason naming the keys; the three UI surfaces read `staleReason`. `diskDetectionSettingsAreStale` keeps its name and delegates; `completedDiskParams` deleted; `realSpaceRegionShape()` inlined |
| C7 Gate B campaign over sessions 1–4 | done 2026-09-08 — a fresh high-tier refuter on the uncommitted tree (`archive/v3/c7-gate-b-2026-09-08.md`), 17 mutations, 5 survived, one claim refuted; its eight remedies adopted only after each was broken by re-applying its own mutation: `gateB/remedies-real.log` 48/48 on the real code, `remedies-mut1.log` exactly the four aimed tests fail (M3 rounding, M7 axis swap, M11 nearest, G4 export folder; 24/28), `remedies-mut2.log` exactly the other four (dotfile rule, refusal order, bounds guard, ingredient; 31/35); files restored `cmp`-identical; unit **564 / 0 / 1, 565 cases** exit 0 (`gateB/unit-c7-gateb-20260908.log`, 565 `func test` in source); core exit 0 (`gateB/core-gateb-20260908.log`); the Python fixture gate exit 0 (`disk-detector-fixture-gateb-20260908.log`); signed build exit 0 (`build-signed-gateb-20260908.log`) | Refuted and fixed: `evaluate.py` could not read an app export (`KeyError: app_probe`) — the store carries `ingredient`/`seed` through a round trip and `evaluate.py --ingredient` names the npz key. Blind spots closed with one assertion each: the matcher's diagonal-only fixtures (an axis swap in one input was invisible), `fitOffset`'s vacuous half-to-even check, `removeNearest`'s nearer-was-last test, the export destination, a border click stored off-detector (now refused). Changed on findings: a refused learned replay leaves the picker and threshold alone; the asset hash and `export.py`'s `sha256_tree` share one dotfile rule; `scan-bench` records the crop origin under the detector's keys. Held: Python parity of the learned path (fixture gate exit 0, worst diff 0), the replay rules, preserve-on-nil, the Neural Engine per-shape trap re-measured at 0.036. Corrected in the docs: the ceiling is ≈ 1.5× with a noise band and the 250² vs 256² FFT caveat. Opened: the probe channel's anchor above 256 px (`open-items.md`). Process finding: `-only-testing` with a file name that is not a class runs nothing and exits 0. **What Gate B could not test:** the >256-px path against external truth, the hash rule on the real package, anything on screen, the full `scientific` set |
| C7 session 4: hand-clicked disk-centre labels in the session sidecar (owner: centres, one attribute) | done 2026-09-08 (a Sonnet slice briefed from and gated here), no Gate D (neither trigger: new storage and UI, four stateless relocations pinned by existing tests); Gate B owed at C7's end, in scope; unit **557 / 0 / 1, 558 cases** exit 0 (`s4/unit-c7s4-20260908.log`, 558 `func test` in source); core exit 0 (`s4/core-final.log`); inventory exit 0 (`s4/inventory-final.log`, `AppState` + `ResultExport` **7 505**); signed build exit 0 (`s4/build-signed-c7s4-20260908.log`); the six harnesses that compile `BraggVectorEMDWriter.swift` and five of the seven that compile `VirtualDetector.swift` each exit 0 (`s4/<name>.log`; `residency-sweep` needs a cube path, `performance-baseline` is a benchmark); 18 new tests, of which **4 were broken first** by real mutations (row/col swapped in the encoder → the schema test; nil erasing → the preserve test; the remove radius unbounded → the radius test; the no-dataset guard returning published → the refusal test; `s4/mutA…D.log`, reverts `cmp`-verified) — **the other 14 were not individually broken; the Gate B campaign owes them a look**; the agent reported the disk at 0 bytes twice and cleared Xcode's DerivedData; **unseen on screen** | `Session/DiskCentreLabels.swift` (`DiskCentreLabelStore`: the `labelling` toggle, positions of `[row, col]` centres in the native frame, add / removeNearest / clear / reset, `encodedJSON` in `label_centres.py`'s schema — cube, dataset, frame "native", positions, a SHA-256 over positions — `load(from:expecting:)` refusing another cube, `exportForFineTuning`); `BraggVectorEMDWriter`: root attribute `mac4dstem_disk_centre_labels`, `mergeCalibration(diskCentreLabelsJSON:)` preserving on nil, `loadDiskCentreLabelsJSON`; `AppState` holds the store, restores it on activation (a status line on failure, never a modal); `saveCalibrationToSessionSidecar` carries the labels; `exportDiskCentreLabels` (the container's Documents/mac4DSTEM/disk-labels/); `toggleDiskCentre(atPatternRow:col:)` (within 3 px removes, else adds; refuses without a dataset, off Current, or with the toggle off); "Disk centre labels" rows in Disk detection (toggle, This position, Labelled, Clear This Position, Save to Sidecar, Export Labels…); `CentreLabelOverlay` (cyan crosses) and a tap catcher on the diffraction pane while labelling, in Disks mode; the budget paid by `DetectorShape.realSpaceRegion`, `SessionGates.isDataSourceFailure`, `ReplayRecordFrameMap.exportableRecipe`, `SessionSidecarLocator.copySidecarFile` |
| C8: triage of the AI-room branch (`ml/disk-detector` `f057545`) | done 2026-09-08 as the one read-only triage session the plan asks for (a Sonnet agent, reviewed here; nothing merged, no build, no Gate D — the branch's own tests declare they never met a compiler); evidence `archive/v3/c8-triage-2026-09-08.md` | Verdicts against the acceptance checklist: (1) density divides by the DISPLAYED product's mask, not `PrecipitateProduct.sourceValidity` — not met; (2) `isStale` exists only on `DiffractionGroupsProduct` and is read only by its own view — partly met; (3) edge objects consistent between segmentation and statistics, but "edge" is the array border, not the analysed extent; (4) every `.failed(String)` discarded at its call site — not met; (5) 2 of 7 run functions detached with Cancel — not met. Sorting: the four `Core/Analysis` engines (`Precipitates/*`, `DiffractionEmbedding`) depend on neither detector and are portable unwired today; the product/orchestration/UI layers of precipitates and diffraction groups wait for the §1.5 design session (the per-object list `PrecipitateProduct.objects` reaches neither export nor the sidecar; `clear()` drops it on dataset change); `DiskLabelStore`/`DiskLabelRows`/`AppState+DiskLabels` dropped (centre labels decided); `AIAnalysisSettings` needs a rewrite (its learned-disks case is retired by C7). AppState cost if ported: two session-owner properties. **Owner decision 2026-09-08 night: leave (`decisions.md`) — C8 closed** |
| C7 session 3: the position-matched disagreement map as a product, `scan-bench` on Core ML, the ceiling re-measured at 256 px | done 2026-09-08, no Gate D (neither trigger: a new diagnostic product and two relocations pinned by tests; no existing number moves); Gate B owed at C7's end per the plan, this map in its scope; unit **539 / 0 / 1, 540 cases** exit 0 (`unit-c7s3-final-20260908.log`, 540 `func test` in source); signed build exit 0 (`build-signed-c7s3-20260908.log`); core exit 0 (`core-c7s3-20260908.log`); inventory exit 0 (`inventory-c7s3-closeout-20260908.log`: `AppState` + `ResultExport` **7 515**, 15 under the baseline — the first inventory run of the tree exited 1 at 7 556, `inventory-c7s3-20260908.log`, and a second payment followed); the three harnesses that compile `DiskDetection.swift` — `disk-detection-test`, `disk-correlation-parity`, `cancellation-test` — each exit 0 (`<name>-c7s3-20260908.log`); six new tests broken first by four mutation rounds (`focused-mutA…D.log` and `.xcresult`; `focused-real.log` 77/77 before): A — radius made exclusive, `extraProvenance` dropped, one replay key dropped → exactly the three aimed tests fail (74/77); B — the map degraded to the count difference plus learned-side peak reuse → three tests fail, but the reuse mutation SURVIVED (the classical-side guard covered the only case), so the reuse test gained its mirror; C — farthest-first pairing → the closest-first test fails (6/7); D — learned-side reuse alone against the strengthened test → it fails (6/7); the three files byte-verified reverted; **`scan-bench` on Core ML, one 256-px frame, no tiling, two runs (`scan-bench-coreml-run1/2.log`; JSONs in `References/training_runs/disk-detector-2026-09-08/scan-bench-250/`): 525 native 250-px bullseye patterns (the 2.81× run's geometry), classical 0.76–0.83 ms/pattern (2 017 peaks), learned end to end **≈ 1.5×** (1.44–1.64× over three runs at both 0.7, 4 544 peaks, and 0.9, 3 086 peaks; Gate B's re-run 1.48× at both, so the band is run-to-run noise; caveat: a 250² classical FFT against the padded 256² frame), peak counts identical every run — under the 2× target the 2026-09-07 acceptance had waived at 2.81×**; **"Compare Detectors" and its map unseen on screen** | `DiskDisagreement.positionMatchedMap` (greedy closest-first pairing within 2 px, each peak once; `Summary` with both directions, the pooled median residual, `provenance(learnedRun:)`, `statusLine`; `countDifferenceMap` deleted), `AppState.runDiskDisagreement` → product `disk_disagreement` (scan domain, its own provenance keys, no recipe step) through `publishProduct(domain:extraProvenance:)`, the "Compare Detectors" button under the picker rows once both classes have run on the dataset; `DiskDetectionParams.replayParameters(kernel:)` and `SystemMonitor.count`/`scanProgressStatus` moved out of `AppState`; `tools/disk-detector/scan-bench/` (`run.sh dump|bench`, `dump.py`, `main.swift`) on `main`; labels in the sidecar NOT done — an owner decision (`open-items.md`) |
| C7 session 2: the Detector picker in Disk detection, its Session owner, the detector's identity on screen, replay refusing a class mismatch | done 2026-09-08 (a Sonnet slice, gated here), no Gate D (neither trigger: wiring and presentation; the one `Core/` change is a provenance key); unit **534 / 0 / 1, 535 cases** exit 0 (`unit-c7s2-20260908.log`, 535 `func test` in source), core exit 0, inventory exit 0 (`AppState` + `ResultExport` 7 530, one under the baseline), signed build exit 0; 20 new tests each broken first (`s2/before-inverted*.log`, `s2/provenance-before.log` → the after logs, `s2/focused-final.log` 109/0); the four harnesses that compile the touched `Core/` file — `disk-detection-test`, `bragg-export-test`, `sidecar-result-test`, `disk-detector` — each exit 0 (`<name>-c7s2-20260908.log`), not the full `scientific` set (1.6 GB free); **driven by the owner 2026-09-08 13:03 on the demo, three screenshots:** the picker, Threshold 0.70, Model `0f53d270` after the first live pass, the rings following the picker, Current CBED 9 peaks, Detect All Disks 1 296 peaks (144 × 9, median 9.0, range 9–9), the neural-net status texts; at 13:06 the Info tab's Provenance rows of the map: `detector_class` learned, `learned_threshold` 0.7, the full `learned_model_sha256` `0f53d270…b641ab` (the record's hash). **Every session-2 surface seen** | `Session/LearnedDetection.swift` (`LearnedDetectionSession`: class, threshold, probe reference, the loaded model, the last run of each class, `prepareForRun`, `livePeaks`, `replayParameters`, `replayRefusal`); the "Detector" picker (Classical \| Neural net) with its Threshold and Model rows at the top of Disk detection in `MapSettings`; the live rings follow the picker; `runDiskDetection` branches on the class after the same validation and records `detector_class` (+ `learned_threshold`, `learned_model_sha256`) in the replay step; the Bragg vector map's Provenance rows carry those three keys and the classical path names itself; `ReplayStepPlan.diskDetection` carries `DiskDetectorReplay` (absent key = classical; a learned step replays only at the shipped hash); `ProductWorkflowReadiness.wantsLearnedDetector` / `hasLearnedDetectorAsset` feed one prerequisite row and one guidance line; `ACOMSession.resetForDataset` took the activation block out of `AppState` (its budget: −ACOM reset, −one probe-radius prologue, −41 blank comment separators, disclosed in `decisions.md`) |
| C7 session 1: the learned detector's runtime on `main`, Core ML at 256 px | done 2026-09-08, no Gate D (neither trigger: no defect, an opt-in path pinned to the Python reference), Gate B owed at C7's end per the plan; 19 tests in three files, six mutations of `LearnedDiskDetector` each caught by the test aimed at it (`test-learned-mut.log`: count scaling, fit offset, the 256 branch, the window copy, the hash's paths, the shift back), revert byte-verified; learned classes 19/0 (`test-learned-2.log` exit 0); export check every Core ML row within 0.075 of PyTorch float16 (`check-c7.log`, tolerance 0.1; its exit 1 is the pre-existing Core AI GPU and stateful rows); `disk-detector` harness exit 0; **nothing on screen yet — no UI in this session** | `Models/DiskDetector/disk-detector-heatmap-256.mlpackage` (float16 in/out, batch flexible, macOS 14 target, sha `0f53d270…`) with its record JSON, the one `.gitignore` exception; `Core/ML/LearnedDiskDetector.swift` on Core ML (compile at load, `.all` compute units), `inputSize` 256, `defaultThreshold` 0.7, `toCounts`, `fitOffset`/`window` = `simulate.fit_to` (pad below 256, as is at 256, windows above), `LearnedDiskDetection.swift` streaming + count map; `DiskDetector.Candidate`/`correlation`/`refine` and `DetectorClass` from the branch; `export.py` Core ML heatmap route (+ the several-shape attempt, recorded not shipped), `check_export.py` checks every package, `write_swift_fixture.py --coreml --batch 32`; the Swift fixture at 256 px. `AppState` untouched |
| C4 slice 2: one enable logic | done 2026-09-07 night by a Sonnet agent, wiring only, no Gate D; two tests broken first (`pw-fail.log`, `sg-fail.log` exit 65 → `test-productworkflow-after.log`, `test-gates-nav-demo.log` exit 0), `xcodebuild build` exit 0 (`build1.log`); unit 495/0/1 (gate table); **unverified on screen** | `ProductWorkflow.mayRun(_:readiness:isBusy:)` is what every run button binds to (Compute Strain Map, Reconstruct Object, Prepare Parallax Preview, the toolbar action); `SessionGates.mayWriteSidecar` gates the five sidecar save/remove controls; `View.disabledWhileRunning(appState)` on the four settings panels disables every parameter while a run is in flight; "Update Image" is "Compute Image" and the dead "Reconstruction Ready" button is gone. 56 survey rows classified in the agent's report; the parallax stage buttons keep their in-memory sequencing checks, which `ProductWorkflow` does not model. `AppState` untouched |
| C4 slice 1: the four C3 presentation observations | done 2026-09-07 night by a Sonnet agent, presentation only, no Gate D; two new tests broken first (`statusbar-before.log` exit 65 → `-after.log` exit 0; `activitylog-before.log` → `-after.log`); unit 493/0/1 (gate table); **unverified on screen** | `LayoutPolicy.progressPercentWidth` (36 pt, measured against "100 %") reserves the status bar's percentage; the status message is one line, tail-truncated; the output log scrolls to its newest line on appear through `ActivityLog.scrollTarget(forCount:)`; `MapSettings.parameterSliderRow` shows title and value as two texts, which also fixes the two sigma sliders that shared it. `AppState` untouched. Not testable in the unit target, said plainly: the one-line truncation and the slider layout |
| C5, first extraction: the fit-verification overlays out of `AppState` | done 2026-09-07, unit + `core` green, six tests broken first (five mutations, all caught); **owner-verified on screen 2026-09-07 23:33** (light appearance, `sim_Au`: the fitted-origin cross on the central disk) (`drive/shots/`): on the demo fixture the red fitted-origin cross draws on the central disk in Prepare, the toggle removes it and brings it back, and it draws on the Mean pattern too; the yellow ring and dot that stay with the toggle off are the aperture control, not the overlay; no fit ellipse was drawn because the demo carries none; strain and ACOM overlays not reached (nothing computed) | `Session/FitOverlayPresentation.swift`: the origin/ellipse/strain-lattice/ACOM-template overlays as a value over a snapshot; `AppState.fitOverlays` builds the snapshot, `ImagePanes` reads the value. `AppState` 5 593 → 5 500 lines. The reopen boundary is pinned: a calibration restored through `SessionCalibrationTranslation` draws the same origin and ellipse as the live one. Not exercised: the ACOM template path beyond its gating (no `OrientationPlan` fixture in the unit target). The rule itself: `inventory` fails when `AppState.swift` + `ResultExport.swift` exceed their count at HEAD (HEAD^ on a clean tree) — broken first by a 100-line append (`inventory-c5-broken.log`) |
| Bullseye: flat measured-kernel mode + the file's probe as a kernel source | done 2026-09-05, Gate D diagnosed, Gate B passed with findings applied, **agent-verified on screen 2026-09-07** (`shots-c3/a9-strain.png`: Measured kernel mode "Flat", "Use File's Probe"; detection on the demo 9/9 per pattern, 1 296 peaks) | `ProbeKernel.flat` = py4DSTEM `get_probe_kernel_flat` (normalise, Fourier-shift the centre to the corner; DEVIATION: a non-finite pixel counts as zero), `ProbeKernelMode` on every kernel and in both provenances, `.fileProbe` with `probePath`; `FourDDataSource.probeCandidates`/`readProbe` read the legacy (Qx, Qy, N) and the modern (2, Qx, Qy) `Probe` layouts, slice 0 either way. Parity on the bullseye file: 878/878 and 164/164 peaks with py4DSTEM's flat route at two thresholds, both sides pinned to (125, 125) (`parity/compare-0.05.log`, `-0.1.log`); the kernel at the app's own probe centre matches to 3e-6 (refuter's `refute-bullseye/flat/compare-pristine2.log`). Refuter's findings applied: two mutations survived every shipped check — an unwrapped frequency index (passed the integer-centre fixture and the parity) and a dropped conjugation (correlation became convolution; every radially symmetric check blind) — now caught by the fractional-centre/conjugate-transform fixture (`flat_kernel_fractional_centre`, 4.5e-8 / 6.7e-7) and an asymmetric unit test; the modern Probe layout was refused, now read (`p3` fixture); the UI defaulted to the trench, now flat; the stated mechanism corrected (the trench fails at the ESTIMATOR'S radii, not on bullseye probes as such). Mutations retained: five (mut2), four (mut3), two unit-suite (`unit-mutation-M1-20260905.txt`), all caught. Unit 485/0/1 (486 cases, MCP, `unit-mcp-flatkernel2`). `AppState` gained `generateFileProbeKernel`; nothing moved out. Not exercised by any check: the AppState glue itself (an x/y swap there would be invisible) |
| Detection threshold: the one-peak warning names the knob; the default is measured, not moved | done 2026-09-05, controls agent-verified 2026-09-07; **owner-verified 2026-09-07 23:38** that a high Min relative (0,5 %) on `sim_Au` yields a warning in the preview ("the selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated", 37 candidates → 0 accepted); the full-scan summary's own wording is not in that screenshot | `DiskDetectionScanSummary` carries the run's `parameters`; the median ≤ 1 warning names Min relative intensity (value, reference peak, both remedies) instead of "spacing or thresholds". One test, failing first on the old text (MCP log 18:22, passing 18:24). `AppState` touched at one call-site argument only — no responsibility moved out, said plainly. The `relativeToPeak` 0 → 1 default question is REFUTED by measurement on six training cubes (`det-experiment-20260905.log`, closure in `closed-items-2026-09.md`): WS₂ 1 → 45 peaks/position where ~13 are disks, sim_Au 3 918 and MgO 12 357 positions at the 70 cap — the reference collapses wherever the second peak is weak. Default unchanged; item closed. New observation: twisted bilayer graphene finds one peak at either reference (`open-items.md`). Unit 479/0/1 (480 cases, MCP route, `unit-mcp-detection-20260905.json`) |
| Origin measurement: the CoM window iterates and never cuts the beam's edge | done 2026-09-05, Gate D pre-registered (prediction met to 0.001 px), Gate B passed with findings applied | `measureOrigin` recentres its window on its own estimate (≤ 4 passes) in max(r·rscale, r + 1.5 px); DEVIATION from py4DSTEM's single pass noted in the kernel. WS₂ at the shipped rscale: 63.986 → 63.7375 against an independent 63.738. The refuter's numpy twin over ten training cubes: new values within 0.02 px of a wide-window reference on every clean cube, the old ones 0.25–0.8 px off; the shift depends on the beam's place in the block grid, not disk size (`q-calibration-design.md` §9, which corrects the "~0.3 px, small beams only" claim). `origin_measurement_truth` at 0.02 px (six mutations, the bounding-box clip survived 0.05 px); two-spec P4 equivariance tightened 0.65 → 0.001 px. Every origin-derived number can move, up to ~0.8 px mean on the training set — a v2.6.0 change |
| Q-calibration (a): the same-shell cluster mean replaces the per-pattern minimum | done 2026-09-05, Gate D pre-registered, Gate B passed with the mechanism corrected | `KnownCrystalQCalibration.estimate` averages the innermost shell's equivalents (band = derived separation capped at 8 %), both shells; `sameShellPeaksPerPosition` reports k. WS₂: cluster 18.902 px vs 18.901 from the independent 11-20 shell; the minimum was one spoke of a 0.26 px origin-fit offset (new open item). sim_Au: the reference shell is item (b)'s problem and Friedel pairs differ 2.4 %, so no truth claim there. `q-calibration-gate-test` 79 checks, 14 mutations; the scratch experiment harness and the refuter's dumps are in the scratchpad |
| Science lane: probe refusal, ACOM origin snapshot, selected-area fixture, CIF fingerprint | done 2026-09-05, Gate B passed with findings applied | `probeSize` → nil, `OriginCalibrationError.probeNotMeasurable`, finite-only at every step, `np.median` parity; `ACOMRunSemantics.originProvenance`; `selected_area_diffraction_partial_rows` with `2^scan` values and a 1 × 2 region (ten mutations, refuter's row-reversal included); `CrystalModel.contentFingerprint` recorded as `material_fingerprint`, `resolveMaterial` refuses a different CIF under a shared id. Refuter report and every mutation log in the scratchpad; closures in `closed-items-2026-09.md` |
| UI-review label findings (b)(d)(e)(f), minors, `PaneSplit` (a)(c) | done 2026-09-05, **agent-verified on screen 2026-09-07** except (f) staleness, which no drive has yet made stale (`shots-c3/a1-launch.png`, `a3b-narrow.png`, `a4b-divider-back.png`: "Virtual detector · Annulus · Relative" label, colorbar with range and units, cursor readout `1.159e+04`, scale bar `5 px` only while Q is Not set, headers overflow into ••• and the divider survives a Results round trip) | Pattern statistics named for what is on screen (`PatternSourceLabel`); comparison panels carry a `Colorbar` (range, units, zero mark, masked swatch); cursor readout at four significant digits; ONE staleness verdict (`TaskProductState`, `ProductWorkflow.productState`) on the sidebar, the inspector and the strain/ACOM maps; scale bar never prints a unitless sampling as px (`ScaleBar.footerSampling`); no kernel → cross markers, not a 3 px circle (`PeakOverlayGeometry.radius` is optional). Both pane headers are `ViewThatFits` with an overflow menu; the divider fraction is `@SceneStorage`. Six unit tests, each broken first |
| DM4 Gatan STEM-SI import | fixed 2026-09-05, reviewed and reworked the same day; owner's GMS observation and re-drive owed | Empty positional labels resolve by physical sibling index (ncempy's rule, confirmed against ncempy on the real file); calibration domains distinguish detector-fastest from scan-fastest storage. `Si-SiGe.dm4` discovers as scan 77 × 17, detector 448 × 480, uint16, 2 nm / 0.06208537 1/nm — the roles are proven by the units and the survey rectangle; **the detector pair's x/y order is not** (`open-items.md`, Gate D). Review rework: full-cube read 19 s → 0.94 s (blocked transpose), undecidable units open the file without pixel sizes instead of refusing it, detector-fastest DM4 reports `.scanOnly` pushdown again, py4DSTEM's TitanX roll recorded as unported. Probe log `dm4-probe-20260905.log`. **Evening:** the `realslices` refusal its own harness check demanded (`read_v0_12.py:373-388`) was never in the reader — a legacy strain stack opened as a cube with a 4-px detector; the rule now names both v0.12 slice collections and `datacube-discovery-test` is green again |
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert (`open-items.md`, the constraint-loop entry), which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **agent-verified 2026-09-07 with one finding** (`shots-c3/a5-running.png`: the slot holds `0 s` and the progress bar; the `%` label wraps onto a second line — `open-items.md`; the demo run is sub-second, so throughput/ETA were never on screen) | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| The output log moved off `AppState` | done 2026-09-04, **agent-verified 2026-09-07** (`shots-c3/a6-log.png`: the run's lines are there; the panel opens scrolled to its top — `open-items.md`) | `ActivityLog` (`App/ActivityLog.swift`) owns the strip's buffer: the filter, the no-repeat rule, the 300-line cap and the stamp, on an injected clock. `AppState` 495 → 494 stored properties. `@Observable` on it is load-bearing — with the annotation removed, five of its six tests still pass and the strip silently stops updating, which is why `ActivityLogTests` asserts the chain with `withObservationTracking` (the repo's first). Toggling the log from the status bar is the five-second check |
| Saved-session sidecar contents moved to the LEFT sidebar | done 2026-09-04, **rows agent-verified 2026-09-07** (`shots-c3/b3b-sidebar.png`, `b3d-reopened.png`: filename row, Calibration, Change…, Ignore… in the Session section, back after reopen); **Remove owner-verified 2026-09-07 23:33**: right-click on "DPC magnitude" shows "Remove DPC magnitude" (beside the system's Ask Siri item) | `Section("Saved session sidecar")` is gone from `WorkspaceInspector`; the sidecar filename, Calibration, BraggVectors, the saved-result rows, Apply Saved Controls and Change…/Ignore… render in `WorkspaceSidebar`'s `Section("Session")`. Info keeps only the unreadable / does-not-fit sections — the explanation half of the split. Builds clean with no warnings and no test names the moved identifiers, which is also the limit of what any gate can say: this is placement, and only the owner's eyes close it. One judgement call to overrule or keep — Remove is now the result row's context menu, not a second visible row per result (`open-items.md`) |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | **571 passed / 0 failed / 2 skipped, 573 cases — 2026-09-09**, inside the green `all` run; reconciled against 573 `func test` in source. The second skip is new and benign: `TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes` does `XCTSkipUnless(fileExists)` and WS2's sidecar was deleted by the owner on 2026-09-09, so the gate quietly lost that one case — restore a WS2 sidecar to get it back. |
| `run-tests.sh scientific` | **44 harnesses, exit 0 — 2026-09-08 morning, `main` with `disk-detector` gated** (`scientific-c6-main-20260908.log`, `GATE_EXIT=0` on its own line); the C7 session-1 tree re-ran the one harness it touched, `disk-detector`, exit 0 (`disk-detector-fixture-c7.log`), not the full set (< 1 GB free; the Swift changes are outside every harness's source list). Previous: 43/exit 0 three times on 2026-09-07 (`scientific-{before,after,final}-20260907.log`). |
| `run-tests.sh core` (both packages) | **exit 0 — 2026-09-08, the C7 session-4 tree** with `Session/DiskCentreLabels.swift` (`s4/core-final.log`). Previous: session 3, same day (`s3/core-c7s3-20260908.log`) |
| `run-tests.sh inventory` | **exit 0 — 2026-09-09, after the review fixes** (`inventory-final-20260909.log`); AppState + ResultExport **7509**, equal to HEAD. Six checks were added that day and the gate was red on arrival: it caught the untracked model spec, the dead link to the archived v2.5 plan, the missing licence texts, and — three times — this file's own prose, which is the check working: a doc may not write a repo path it does not have, not even to describe one. Metric renamed: `AppState.swift type-scope decls` **166**, not the old "stored properties 491", which counted function locals. **Markdown went UP, and the reason is stated as the rule requires: live 5 054 → 5 133 (+79), cold-start 965 → 1 037 (+72). The +72 is this handoff and the three open items the review left standing; the register itself is 192 archive lines that replace a 2 014-line file outside the repo. Nothing was deleted to pay for it because nothing live was found stale enough to delete — the next session that touches these files owes the trim.** |
| `tools/package-test/run.sh` | **exit 0 — 2026-09-08, the C7 session-1 tree** (`inventory-c7-final-20260908.log`): gated 46, diagnostic 9; `AppState` + `ResultExport` 7 531 (unchanged); live markdown up from 4 693 — the runtime's decisions, the plan's C7 line and one open item, against a shorter handoff; the reason is stated here. |
| `run-tests.sh all` | **exit 0 — 2026-09-11, the v3.0.0 cut gate on the frozen tree** (`all-v3cut-20260911.log`, `GATE_EXIT=0` on its own line), **46 harnesses, zero `FAIL` lines, unit 573 passed / 0 failed / 2 skipped = 575**, reconciled against **575** `func test` in source. Covers everything this session landed: the architecture pin and its fixture, the GPL/NOTICE resources, the Finder URL handler, the concurrent-open guard and its two new tests. `package-test` now prints six PASS lines, two of them new — the GPL text inside the bundle, and `arm64` alone on the executable and all three dylibs, *built the way the archive builds*. `inventory` exit 0 the same day (`inventory-final.log`): **AppState + ResultExport 7509, exactly equal to HEAD**, so C5 was paid rather than waived — the guard was compressed to two lines and two duplicate blank lines collapsed to cover it. Live markdown **4962**, down. **Reconciliation trap, and the recorded fix for it is itself wrong:** this file has said since 2026-09-09 to "count `^Test case '` lines by status". That undercounts — here by exactly one, `QCalibrationOriginGateTests.testUnusableOriginRefusesQCalibrationAndSetsNoScale`, whose result line xcodebuild glued onto the end of the preceding line so that it begins neither with `Test case '` nor with anything anchorable. Count the **suffix** instead: `grep -o "()' passed on 'My Mac"`. Reading the anchored count would have reported 572/575 and sent the next session hunting a test that had in fact passed. **Three refusals on the way here, all exit 69 at the 8 GB floor**, and the background wrapper printed "exit code 0" for every one of them — read `GATE_EXIT`, never the caller. Space came from Xcode's `DerivedData`, `tools/free-space.sh --clear`, and this session's own scratch archives. Previous: exit 0 earlier the same day on the arch fix (`all-arch-fix-20260911.log`), 46 harnesses, superseded because source changed under it. |

## Handoff — NEXT: port the AI pipeline onto main (started, not done)

**State on arrival, 2026-09-11 end of session.** v3.0.0 is released and pushed
(release row above). `main` is `9b9949b`, clean. An empty branch
**`ai/precipitates-embedding`** exists at that same commit — created as the
home for the work below; nothing has been written to it. Delete it and start
again if you prefer.

**The task, decided by the owner:** move the unmerged AI-pipeline work from
`ml/disk-detector` onto current `main` by **porting files forward, NOT by
rebasing** — the branch is 27 commits ahead and **41 behind**, its merge base is
2026-09-06, and `main` has since shipped v3.0.0.

**What is unmerged and wanted** (verified 2026-09-11 with
`comm -23 <(git ls-tree -r --name-only ml/disk-detector|sort) <(git ls-tree -r --name-only main|sort)`):
`Core/Analysis/Precipitates/{PrecipitateSegmentation,PrecipitateReflections,PrecipitateStatistics}.swift`
(388/176/140 lines), DiffractionEmbedding.swift (708, under Core/Analysis on the branch),
`Session/{PrecipitateProduct,DiffractionGroupsProduct}.swift`,
`App/AppState+{Precipitates,DiffractionGroups}.swift`,
`UI/{AIAnalysisSettings,PrecipitateSettings,DiffractionGroupsSettings}.swift`,
`mac4DSTEMTests/{PrecipitateTests,DiffractionEmbeddingTests}.swift`,
`docs/ai-ml/{README,precipitates}.md`, and a second model
disk-detector-heatmap-b32.aimodel (branch only, under Models/DiskDetector).
Read the branch WITHOUT checking it out: `git show ml/disk-detector:<path>`.

**Four known problems, none of them solved yet:**

1. **Disk labels exist twice, in different shapes.** The branch has
   AppState+DiskLabels.swift + DiskLabelStore.swift +
   DiskLabelRows.swift (branch only); `main` has `Session/DiskCentreLabels.swift` +
   `DiskCentreLabelTests.swift`, which **shipped in v3.0.0**. Owner's decision:
   **main's wins.** Not established: whether the ported features call into the
   branch's store, and what the equivalent on `DiskCentreLabels` is. Check every
   call site before dropping the branch trio — this is the highest-risk part.
2. **`Session/LearnedDetection.swift` diverged by 159 lines**, both sides
   independently. Main's is the shipped one and is the default to keep; port
   forward only hunks the new features actually require, hunk by hunk.
3. **The AppState rule almost certainly bites.** The branch adds three
   `AppState+*` extension files. CLAUDE.md forbids new stored state in AppState
   and `inventory` fails if `AppState.swift` + `ResultExport.swift` net positive
   (today they are **7509, exactly flat** — there is no slack). The compliant
   shape is main's own: a `Session/` type that owns the state, held by AppState
   as one property with no forwarding — see the role comments at the top of
   `Session/DiskCentreLabels.swift` and `Session/StrainProduct.swift`.
4. **Build integration.** Every new file under `mac4DSTEM/Core/` and
   `Session/` must be added to the pbxproj `membershipExceptions` list — they
   compile through the SwiftPM package targets, not the app target. And a
   `.aimodel` must never live under `mac4DSTEM/` (MLAssetCompile fails for the
   macOS 14 target); the b32 model's placement is undecided.

**Do NOT port** `docs/archive/2026-08-31-review/test-evidence/.../source-copy/**`
— ~60 duplicated Swift sources that exist only on the branch.

**The open question nobody has answered:** whether the precipitate and
embedding science is a py4DSTEM port (needs a parity harness) or original work,
and whether its branch tests are Swift-against-Swift with no reference — in
which case the science is unverified no matter how cleanly the files move.
**Answer that before quoting any number from these features.**

**The analysis COMPLETED, including its port plan** — six area maps, 19
verifications and a step-by-step plan whose every step ends at a green
`run-tests.sh`, in
[`archive/2026-09-11-ai-port-analysis.md`](archive/2026-09-11-ai-port-analysis.md).
**Read its first section before anything else — three findings there change the
shape of the task, and one says this port is already covered by a standing
decision:**

- **`decisions.md` 2026-09-08 already ruled on this.** "C8: the four pure
  engines stay on the branch (owner, in chat: 'leave')" — not ported *unwired*;
  they re-enter *with their product and UI layers* through the §1.5 design
  session. The reason given (dead Core in a tree about to become v3.0.0) has
  lapsed. The condition has not. **A port needs a new dated entry reversing it.**
- **The science is ORIGINAL, not a py4DSTEM port** — no DEVIATION notes, no
  reference implementation, and the segmentation deliberately abandoned
  skimage's convention. **No parity harness is possible.** Gate D applies:
  `lengthPx`, `widthPx`, `orientationDegrees`, `area` and `arealDensity` all
  reach an export.
- **Its own pre-registered ship gate is unmet** — the design doc demands a
  baseline without the ridge filter that the ridge filter must beat "or it does
  not ship". Never written; the hand count was never made.

The rest of that file is evidence and a proposed plan. **Rows without a
Verifier line are leads, not facts.** Also established:

- **`main` has no AI Analysis workspace.** `WorkspaceArea` is
  prepare/image/map/reconstruct/results (`App/ProductWorkflow.swift:10-15`); the
  branch's UI hangs off a `.aiAnalysis` area that does not exist here, and the
  branch gates live learned rings on it. **Owner decision: does v3.1 add a sixth
  workspace, or do precipitates and grouping live inside Map?** Nothing can be
  ported until this is answered — it decides where the UI lands.
- **The embedding needs LAPACK, and the branch bought it with `.unsafeFlags`**
  (`-Xcc -DACCELERATE_NEW_LAPACK` in `Package.swift`). That flag changes how ALL
  of DSTEMCore compiles and **permanently forbids the package being consumed as
  a dependency**. It also silently breaks `tools/bragg-spacing-probe/run.sh`,
  which nothing gates. **Owner decision, and it is a policy one, not a patch.**
- **Dropping the branch's disk-label trio is clean.** Verified: `main` has zero
  occurrences of `DiskLabelStore` / `diskLabels` / `mac4dstem_disk_labels`, and
  nothing in the port scope references them. Neither Gate D trigger applies.
  But **confirm the dropped capability is unwanted first** — main's store cannot
  express a rejection verdict on a machine-proposed candidate *set*, which is
  exactly what fine-tuning on your clicks would want. That is the one thing
  worth re-adding deliberately rather than losing by omission.
- **The AppState rule bites, measured:** the branch's `AppState.swift` diff is
  **+280 lines** against a rule that allows zero. Its bodies must be rewritten
  into `Session/` owners before anything lands.
- **Do not port:** the branch's `LearnedDiskRows` (duplicates what main shipped
  at `UI/MapSettings.swift:104-138`), its `BraggVectorEMDWriter` hunks (main has
  the identical mechanism under `diskCentreLabelsJSON`), and the
  `source-copy/**` tree. Keep `LearnedDiskDetector.defaultThreshold` (0.7) —
  never hardcode the branch's literal.
- **One branch test is worth porting even though its implementation is not:**
  `mac4DSTEMTests/ProductWorkflowTests.swift:850-878`
  (`AIAnalysisDetectorChoiceTests`).

## Closed 2026-09-11 — v3.0.0 is cut and pushed

Owner, 2026-09-09: C0–C3, C6 and C8 are closed; C7 is closed apart from the
owner's sidecar-reopen check; the `all` gate is green. **C4(c) is committed at `1eb49c5` and driven.**
C5's measured line rule remains in force; its next monthly extraction is
`OperationCenter` forwarders, a separate session. The plan is archived
(2026-09-11) and the feature freeze it carried has lapsed.

**The review fixes are at `5d08c7d` and PUSHED** (corrected 2026-09-11: the
line here said "not pushed" and `origin/main` had already moved; `main` and
`origin/main` are both `72e6ccd`). It is the first commit whose clone carries
the Core ML model spec, so the first that can reproduce `0f53d270…b641ab` and
pass the CI `unit` job.

**The 2026-09-09 register: 111 claims remain unverified, and none may be fixed
from the register.** The rules for touching it — the exclusion list, what triage
is for, why D002/D003 are closed and what Gate B found on the D002 port — are
one entry in `open-items.md` and the evidence at
[`archive/2026-09-09-review/d002-d003-gate-d.md`](archive/2026-09-09-review/d002-d003-gate-d.md).

**Gates, 2026-09-11:** `all` ran in full and is green (gate table).
**`ARCHS = arm64` does NOT hold everywhere, corrected today:** D064 verified it
with `lipo` on a Release *build*, and the *archive* still compiled an x86_64
slice (`open-items.md`, the release blocker). Debug and Release build; the
archive does not. C4(c) was reviewed clause by clause on 2026-09-08 and is
committed at `1eb49c5`; do not re-review it.

**Disk:** ~7.8 GB free after this session; `all` needs 8 and refused three times today. The six cubes the
gated harnesses read must stay in `References/training_dataset/` —
`calibrationData_bullseyeProbe.h5`, `downsample_Si_SiGe_exp.h5`,
`polycrystal_2D_WS2.h5`, `Si-SiGe.dm4`, `sim_Au_data_all_binned.h5`,
`Particle_1_…bin8.h5`. **Five** are now pinned by name in
`tools/real-data-acceptance/expected.json` (bullseye joined them 2026-09-09),
and `compare.py` turns the gate red if a pinned cube is missing.

**Three traps, each paid here.** (1) A stale Debug binary showed the pre-C4(c)
menus *although its mtime was newer than the source's* — mtime does not prove
freshness; rebuild before concluding anything from a drive. (2) The
background-task wrapper reported "exit code 0" for a run whose own line said
`GATE_EXIT=1`, and again for the green one — read the gate's own line, never a
caller's. (3) 2026-09-09: a diff tool that iterates over the EXPECTED entries
is blind to exactly the data no one pinned, which is where drift hides.

**v3.0.0 SHIPPED 2026-09-11.** Archive, notarization, stapling, DMG, the second
notarization of the DMG, `spctl` on both, and verification by mounting the image
are all done and recorded in the release row above. **What is left is the
owner's alone:** push `main` (the release commit and this one), tag `v3.0.0` and
push the tag — GitHub Desktop does not push tags — upload
`build/release/mac4DSTEM-3.0.0.dmg` to the GitHub release, and paste the
prepared Intel note at the top of the **v2.5.1** release's notes (owner's
decision 2026-09-11: annotate, do not withdraw).

**Two things learned in the credentialed run, both cheap to forget:**
(1) `make-dmg.sh` prints a SHA-256 **before** stapling, and stapling rewrites
the image — publish the hash `notarize.sh` prints at the end, not that one.
(2) `notarytool store-credentials` writes to the **data-protection** keychain,
which `security find-generic-password` cannot see; a check built on that tool
reports "no profile stored" for a profile that exists and works. Do not gate a
release step on it.

**What was left before the run, now done:**

1. **The archive blocker is CLOSED** (2026-09-11, Gate D, both triggers absent
   for the fix itself but the cause was not established, so the protocol ran).
   The cause: project-level `ARCHS = arm64` does not reach the SwiftPM package
   targets `DSTEMCore`/`DSTEMSession`, where every `Core/` and `Session/` source
   is compiled; a generic destination therefore built `ARCHS_STANDARD` and
   `Float16` does not exist on x86_64. The pin travels on the xcodebuild command
   line, spelled once in `tools/lib/release-arch.sh`. **The concrete destination
   `platform=macOS` constrains the package targets on its own** — measured by a
   refuter, Release with `Float16` present and no pin, exit 0 and arm64-only —
   which is exactly why the old gate could not see this.
   **Verified on the real `archive` action**, ad-hoc signed: ARCHIVE SUCCEEDED,
   zero x86_64 tasks, `lipo -archs` = `arm64` on the executable and all three
   embedded dylibs, version 3.0.0 (6), floor 14.0, no duplicate `Info.plist`.
   Evidence and the two traps paid: `archive/closed-items-2026-09.md`.
2. **The gate now covers the archive.** `package-test` built the concrete
   machine and was structurally blind; it builds `generic/platform=macOS` with
   the same pin and asserts `lipo` on the built Mach-Os, so the tempting wrong
   fix — making `Float16` compile on x86_64 — goes red too. Broken before it was
   trusted: the assertion first printed FAIL and returned 0, and its accumulator
   was named `status`, which zsh aliases to `$?`.
3. **Version is already `3.0.0` / `6`** in the project — `package-test` asserts
   it from the project file and printed it, 2026-09-11.
4. **Remaining: the credentialed run only**, which needs the owner's Developer
   ID certificate and notary profile. `docs/releasing.md` end to end: archive,
   notarize, staple, DMG, notarize the DMG, `spctl`, record the hashes. Then
   flip `README.md`'s "New in v2.5.1" to v3.0.0 and fill `releasing.md`'s
   version line from the real run — deliberately not done before the artefact
   exists.

**A readiness review ran the same day and found more than the blocker did.**
Eight dimensions, each finding then attacked by an independent refuter; the
survivors I re-confirmed from source myself. Landed this session, each gated:
the app now ships the **GPL text and `NOTICE` inside the bundle** (it shipped
its dependencies' licences and not its own, and the bundled README pointed at
two files that were not there — `package-test` asserts both, non-empty, and that
LICENSE really is the GPL); **double-click actually opens a dataset**
(`CFBundleDocumentTypes` was declared 2026-09-09 with no URL handler, so Finder
launched the app to an empty window while `CHANGELOG` claimed the feature —
`.onOpenURL` added, **unverified on screen**); **a second dataset open is
refused while one is in flight** and "New Dataset Window" is disabled during a
load, with a test that fails without the guard (negative control run: exit 65,
`ConcurrentOpenRefusalTests.testASecondOpenIsRefusedWhileOneIsInFlight` failed
with the guard removed, the sibling still passing); and the learned detector's
**recall/precision now quotes the shipped threshold** — 0.768 / 0.712 at
confidence 0.7, not the 0.9 row's 0.667 / 0.840 that `CHANGELOG` had been
printing beside a build that ships 0.7. Three findings are disclosed rather than
fixed and are live in `open-items.md`: the hexagonal IPF key's labels, the
single-slice ptychography export guard, and the real fix for concurrent HDF5.

**Found while closing the blocker, and it is about what users have now:** the published
v2.5.1 executable is `x86_64 arm64` against arm64-only HDF5, which `H5Reader`
dlopens — so on an Intel Mac it launches and then fails every dataset open.
Register `D064` predicted that artefact and was marked fixed on 2026-09-09; the
fix pinned the app target only. Live entry in `open-items.md`; the owner decides
whether to withdraw or annotate that download.

**Also corrected:** `docs/releasing.md` recommended archiving from Xcode's
Organizer, which cannot carry the pin and is the most likely way v2.5.1 became
universal. It now says not to.

**Done, and not to be redone:**
- Gate B on the Quantitative-badge fix: **rejected, fix reverted**, defect ships
  as a stated limitation (`archive/2026-09-11-drive/quantitative-badge-gate-b.md`).
- The `Info.plist` duplicate: **fixed and verified in the built bundle** — gone
  from `Contents/Resources/`, `LSMinimumSystemVersion` still 14.0.
3. **Set the version to `3.0.0` / `6`** in the project, then `docs/releasing.md`
   end to end: build, notarize, staple, `spctl`, record the hashes. `README.md`
   and `docs/releasing.md` are deliberately NOT updated yet — they assert
   properties of an artefact that does not exist (the DMG, its size, its
   notarization ticket), and this repo does not write a claim before it is
   true. Flip README's "New in v2.5.1" to v3.0.0 and fill `releasing.md`'s
   version line at that point, from the real run.

**Driven 2026-09-11 and good** (the owner, on `downsample_Si_SiGe_exp.h5` and
`051_STEM_SI_…bin_4`): Strain (ε_xx and ε_yy, 100 % indexed, median RMS
0.778 px), Orientation/ACOM preview and full scan correctly badged Exploratory,
DPC & iDPC correctly badged qualitative, Bragg disks (248 111 peaks, median 24.0,
range 16–42), the CIF import control, and `Size as float32` in Info — which
verifies one of the four fixes of 2026-09-09 on screen. Three refusals behaved
exactly as they should, naming the number and the remedy: the ellipse fit
("ring signal covers only 9 angular bins") and both Advanced memory refusals.

**Still unseen on screen, and NOT blocking** (owner, 2026-09-11): Parallax and
single-slice ptychography on real data (they refuse this machine's memory —
`open-items.md`), the four Phase E failure paths, both Resets, and disk-centre
labelling. Each is named in `CHANGELOG.md`'s "Known limitations at 3.0.0".

**Deliberately not doing before 3.0.0** (owner, 2026-09-09, against bloat): a
glossary or tooltip layer; the WS2 display-contrast problem (disks sit at 0.19 %
of the beam and are invisible at default scaling — real, but the fix is a
thought about display scaling, not a patch); re-deciding when `Strain` unlocks;
the duplicate ⌘R / ⌘↩; and any further driving rigs.

**Owed alongside, not blocking the cut:**

- **Two owner observations, both on `Si-SiGe.dm4` and Prepare**
  (`open-items.md`): open the file in GMS and read the pattern's width and
  height (the detector-pair Gate D item), and drive the manual Q/R fields after
  their rows turn green, in Prepare and in the export sheet.
- **The UI-review fixes and the pane headers** (`open-items.md`): the four
  label findings, the two minors, the compressible headers and the remembered
  divider all landed 2026-09-05 with tests and no screen time. The drive above
  covers them.
- **The science lane, one item at a time.** The plan is archived, so this is
  open again; take one item, in the order below.
  What landed 2026-09-05 through Gate B is in `closed-items-2026-09.md` and
  `q-calibration-design.md` §8–9. Still open: the probe-size under-read on
  ring-shaped probes and the owner's drive of the bullseye maps; ACOM coverage
  (a) is an owner decision, relabel or convert; Q-calibration (b) and the
  origin-fit holes (b)/(c) as design passes. A landed number change cuts
  v2.6.0.

**macOS 14–25 is compile-verified, never executed** (every machine here is
26; a VM needs ~40 GB); the first report from an older system is the test.

**The rule bought the hard way** (`open-items.md`, the constraint-loop entry):
nothing inside a split column may repeatedly change its own minimum size.
`.fixedSize()` on text whose string changes is the easiest way to do it by
accident, and it only shows on a dataset big enough for an operation to tick.
All 12 bare `.fixedSize()` sites in `UI/` are audited and contained.

**Two traps (hit again 2026-09-07):** read the gate's own `GATE_EXIT` line,
never a wrapper's; reconcile the unit count against `func test` in source.

**Driving:** `open -n <Debug app> --args --demo-fixture`; per-window `screencapture -x -o -l <id>`.

## Owed to the owner

- **Driven by the owner 2026-09-08 night:** Compare Detectors, centres placed by hand, Export Labels… — the buttons work (the owner's words; the centres' correctness is his eye). Not yet reported: the map's `disagreement_*` Provenance rows, Save to Sidecar and the labels returning after a reopen. Four session-4 choices to overrule on sight: labels save only with the calibration save; the click catcher exists only in Disks mode; `isDataSourceFailure` now lives on `SessionGates`; the export names the file in the status line. C4 slices 1–2 remain undriven. (Both branches were at `origin` on 2026-09-09; `main` is `72e6ccd` at `origin` on 2026-09-11, `ml/disk-detector` `f057545`.)
- The §10g decisions and plan §8 (sidecar wire format). (C8's engines question settled 2026-09-08: leave, `decisions.md`.)
