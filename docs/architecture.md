# Architecture

What the app is made of, how the layers depend on each other, where a new
file goes, and where the consolidation is taking the ownership model. Product
scope is `README.md` and `CHANGELOG.md`; live status is `status.md`; the
sequence of the consolidation is `archive/v2/v2.5-plan.md`; the feature plan is `ROADMAP.md`.

## Layers and the dependency rule

```text
SwiftUI views (UI/)          present state, send user intent           app target
App/ (AppState, PendingLoad, own the window, dispatch, publish         app target
      ProductWorkflow, …)
Session/  → DSTEMSession     replay plan/run/record, sidecar location,  package
                             gates, calibration frame policy, products,
                             residency, recovery, system monitor —
                             no SwiftUI, no AppState
Core/     → DSTEMCore        pure algorithms, readers, writers, GPU     package
                             engine — no SwiftUI, no AppState, no Session
Shaders/, Support/           Metal kernels; export, bridging header     app target
```

The rule that matters is direction: each layer knows nothing above it.
Since 2026-09-03 this is a module boundary, not a convention: `Package.swift`
builds `Core/` as `DSTEMCore` and `Session/` as `DSTEMSession`, standalone
SwiftPM targets whose own comment states the purpose: `swift build` fails the
moment `Core/` reaches upward into `App/`, `UI/` or `Support/` — run as
`tools/run-tests.sh core`. The Xcode app target compiles the *same* files
directly, via an explicit exception list in `project.pbxproj` enumerating
every `Core/`/`Session/` file, so package and app target never drift apart
file-for-file. Declarations use the `package` access level throughout (app
and test targets set `SWIFT_PACKAGE_NAME = mac4dstem`); a file compiled into
both the app target and a standalone `tools/` harness guards the imports
with `#if canImport(DSTEMCore) import DSTEMCore import DSTEMSession #endif`
(56 files today). `tools/run-tests.sh inventory` backs the UI half: it greps
`UI/*.swift` for `import AppKit` and for
`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController` and fails if
any appear — the app once aborted at launch in AppKit's update-constraints guard.
Both packages share one Swift 6 concurrency configuration:
`.defaultIsolation(MainActor.self)` — every type is MainActor-isolated by
default, so GPU dispatch and CPU-heavy work must be explicitly marked
`nonisolated` to run off the main thread. A real defect from missing this:
`Core/ML/LearnedDiskDetection.swift`, an extension member without
`nonisolated` that silently inherited `@MainActor` and pinned every progress
callback to the main thread. Bare `swiftc` (most `tools/` harnesses) defaults
to *non*isolated, so a harness without matching isolation flags cannot see
this class of defect — a narrowed, not closed, blind spot per
`tools/lib/sources.manifest`: **the Xcode app build is the only real gate for actor isolation**.

## What it does, by subsystem

**Workflow.** Six workspaces — **Prepare / Imaging / Strain & ACOM / Phase /
AI Analysis / Results** (`⌘1…⌘6`; `App/ProductWorkflow.swift`'s
`WorkspaceArea`). Navigation is side-effect free; whole-scan work starts
only from an explicit primary action, runs detached with live progress and
Cancel, and reports in the infobar.

**Data and display.** HDF5 (`.h5`/`.hdf5`/`.emd` — py4DSTEM, Gatan, HyperSpy
and arbitrary EMD layouts via link traversal), Gatan DM3/DM4
(`dm4-format.md`), Preview-tier EMPAD RAW/XML and Merlin MIB, loaded at
runtime via `dlopen` (HDF5 notes, below). Open with options: scan crop,
detector crop, detector bin; streaming residency bounds peak memory
independent of scan size. GPU-rendered viewers with colormap LUTs, log
scaling, per-view contrast/gamma, calibrated 1-2-5 scale bars.

**Virtual imaging and diffraction.** BF/ADF/HAADF presets, draggable annular
aperture, rectangle and point detectors, and the reciprocal operation:
real-space ROIs drive selected-area diffraction.
**Calibration.** Origin (py4DSTEM `get_probe_size` → `get_origin` →
`fit_origin`), R–Q rotation via CoM-curl minimisation with explicit 180°
flip, elliptical distortion (conic and 11-parameter amorphous-ring), Q
calibration against a known crystal (`q-calibration-design.md`). Every value
carries provenance; a fit that fails its gate reports "not quantitative"
rather than a number. Calibration from a different frame is re-referenced or
refused (`SessionCalibrationFramePolicy`).

**DPC / iDPC.** Four views off one cached CoM field; iDPC is quantitative
projected phase only when origin, rotation and both samplings are present.
**Bragg disk detection.** Port of `find_Bragg_disks` with synthetic or
measured probe kernel, hybrid cross-correlation, and pixel / parabolic /
DFT-upsampled subpixel refinement; `FFT2D` is an exact Bluestein transform
for any detector length. Staleness tracking keeps changed settings from
silently feeding strain or ACOM.

**Strain mapping.** py4DSTEM `process/strain`: consensus or manual g₁/g₂,
robust local lattice fits, component-median reference, εxx/εyy/εxy/θ with
unfittable positions as explicit no-data.
**ACOM orientation mapping.** Polar-correlation template matching against a
validated `CrystalModel` catalogue (cubic presets, HCP magnesium, 2H-WS₂,
custom cubic, imported CIF). CPU and Metal backends with parity gating,
reliability, IPF-Z maps, Bunge Euler output. Physical matching requires
calibrated Q sampling; otherwise **Exploratory**. Point-group coverage is
cubic and hexagonal only, by decision: CIFs outside them are refused.
**Parallax and ptychography.** Staged parallax (calibrated virtual-BF
preprocessing → alignment → aberration fitting → CTF correction → subpixel
upsampling → depth sectioning) and a single-slice iterative ptychography
engine, each memory-bounded, cancellable and source-locked to py4DSTEM.

**Sessions, recipes, export.** A `<source>.mac4dstem.h5` sidecar holds named
results, calibration, BraggVectors and the replay record; every sidecar
names the oldest reader that interprets it without misreading. A rehearsal
on a view records a recipe; promote replays it on the full cube,
re-referencing detector-pixel parameters into the source frame and refusing
by name what it cannot re-express. Exports: PNG as displayed, Bragg peaks
CSV, py4DSTEM `BraggVectors`, calibrated reduced `DataCube` with the recipe.

## Data flow: file → screen

1. **Open.** `AppState` picks a reader by extension (`.dm4`/`.dm3` →
   `DM4Reader`, `.mib`/`.raw`/`.xml` → `VendorRawReaders`, default →
   `H5Reader`; `Core/Data/`). Every reader conforms to `package protocol
   FourDDataSource: Actor`, so file I/O is off the main actor.
2. **Discover.** `reader.discoverPrimaryDataset()` returns a
   `DatasetDescriptor` describing the file's shape/dtype at full extent.
3. **Specify the view.** `LoadSpecification` records what part of the file
   is actually loaded — its own header: "a load is a view, not a new
   dataset". A `LoadView` pairs a descriptor with a specification.
4. **Decode / stream.** `package actor FourDArray` wraps the reader +
   `LoadView`, keeps an LRU pattern cache, and can go "resident" via
   `ResidentCube`, gated by `Session/DatasetResidency.swift` ("nothing
   outside may set `isResident`").
5. **Compute.** Per-mode analysis in `Core/Analysis/` and `Core/Crystal/`.
   Some paths run pure CPU (Accelerate/vDSP `FFT2D`); others dispatch to
   `Core/Compute/MetalEngine.swift`, whose GPU calls are **synchronous and
   blocking** (`commit()` + `waitUntilCompleted()` — call only from a
   background `Task`); its parameter structs stay byte-identical to their
   `.metal` twins (Developer notes, below).
6. **Publish.** A result becomes a `DisplayedProduct` — pixel payload, a
   `ProductDomain`, a `ProductQuantitativeStatus`, sampling, a flat
   `provenance: [String:String]` and overlays, so UI never infers semantics
   from a display title. `Session/ResultPresentation.swift` (AppState seam 5,
   `docs/archive/v4/appstate-seams-plan.md`) owns the live one;
   `AppState.publishProduct(...)` (`App/AppState.swift`) is the one choke
   point that writes it, and `appState.displayedProduct` is the one read
   site every viewer, comparison and export path uses.
7. **Record the recipe.** `Session/SessionReplay.swift` records completed
   runs into a `SessionReplayRecord` — one step per analysis kind, in
   first-run order, not a keystroke log. `Session/ReplayPlan.swift` parses a
   recorded step back into typed parameters for replay/promote; it lives in
   `Session/` because its output vocabulary is App-level workflow state.
8. **Show.** `UI/` renders `appState.displayedProduct` via
   `@Environment(AppState.self)` (`ContentView.swift`) through the one
   SwiftUI↔Metal bridge, `UI/MetalImageView.swift`; a `contentVersion` gates re-upload.
9. **Export / persist.** `Support/ResultExport.swift` writes PNG, CSV of
   Bragg peaks, and py4DSTEM/EMD-compatible HDF5
   (`Core/Data/BraggVectorEMDWriter.swift`). Sidecar-rewriting entry points
   call `gates.sidecarRewriteRefusal()` first (`Session/SessionGates.swift`);
   provenance is composed once per fact, snapshotted at compute time, not
   read live off current calibration.

## Project structure and where files go

Synchronized folder groups: any file under `mac4DSTEM/` joins the app target
and `.metal` files route to the Metal compile phase. Placement is wiring.

| Putting in… | goes under… |
|---|---|
| App entry, window state (`AppState`), pending load, workspace vocabulary | `mac4DSTEM/App/` |
| Session state with no UI: replay, sidecars, gates, products, residency, recovery | `mac4DSTEM/Session/` (package `DSTEMSession`) |
| Readers, calibration model, EMD writer, product model | `mac4DSTEM/Core/Data/` |
| Metal engine, FFTs, multicorr, cancellation | `mac4DSTEM/Core/Compute/` |
| Analysis algorithms (virtual detector, solvers, disks, strain, DPC, parallax, ptycho) | `mac4DSTEM/Core/Analysis/` |
| Crystal models, scattering factors, ACOM matching, CIF import | `mac4DSTEM/Core/Crystal/` |
| Learned stages: the Core ML inference class and its scan orchestration (C7) | `mac4DSTEM/Core/ML/`; the pinned asset and its record JSON in `Models/DiskDetector/` (a folder resource, compiled at load); its session owner `Session/LearnedDetection.swift` |
| Operation lifecycle | `mac4DSTEM/Core/Workflow/` |
| Metal kernels | `mac4DSTEM/Shaders/` |
| SwiftUI views, viewers, controls, inspectors | `mac4DSTEM/UI/` |
| Export, bridging header | `mac4DSTEM/Support/` |
| Fast unit and workflow-contract tests | `mac4DSTEMTests/` |
| Standalone parity, diagnostic and packaging harnesses | `tools/<name>/` — classify it in `tools/run-tests.sh` (gated / diagnostic / owner-only) |
| Docs | `docs/` (live set in `CLAUDE.md`); dated or superseded → `docs/archive/` |
| CI | `.github/workflows/` |
| Machine-local data and the fetched py4DSTEM lock | `References/` (gitignored; `tools/lib/fetch-py4dstem.sh` pins the lock commit) |

`References/` is tiered, not bloat: tiny tracked fixtures for every gate;
locally staged representative datasets; multi-GB acceptance data on the
owner's machines; the py4DSTEM source at the pinned commit that `DEVIATION`
notes cite (fetched on demand, not tracked since 2026-09-03).
A new `Core/Data` file must also join the right group in
`tools/lib/sources.manifest` or an existing standalone harness silently
stops compiling against it (Tools and harnesses, below). Apple-Silicon-only
code is guarded with `#if !arch(arm64) #error(...)`, not a silent `#if
arch(arm64)`, so a bare `#if` cannot ship a broken x86_64 slice
(`Core/ML/LearnedDiskDetector.swift`). `UI/PaneOverlays.swift` is the one
file where ad hoc drawing geometry is expected — "none of it sizes text for
a form," per its header.

## Ownership today and where it is going

The `docs/archive/v4/appstate-seams-plan.md` extraction (all seven seams,
complete 2026-09-18) moved every feature's state into one `@Observable`
owner in `Session/` plus one orchestration extension in `App/`; `AppState`
(`App/AppState.swift`, 1603 lines at HEAD) now composes those owners plus
the window, publishing glue and the dataset epoch, rather than holding
feature state directly, and `ContentView` reconstructs workflow rules from
it. Current owners (`mac4DSTEM/Session/`): `ACOMSession`, `ACOMWorkflow`,
`CalibrationSession`, `DatasetResidency`, `DatasetSession`,
`DiffractionGroupsProduct`, `DiskCentreLabels`, `DiskDetectionProduct`,
`DPCProduct`, `FitOverlayPresentation`, `LearnedDetection`, `LoadedView`,
`MaterialsProjectKeyStore`, `MaterialsProjectSettings`, `OperationCenter`,
`PhaseContrastProduct`, `PhaseMapObjectsBridge`, `PhaseMappingProduct`,
`PrecipitateClassificationProduct`, `PromotionRun`, `QCalibrationRun`,
`RecentDatasets`, `ReplayPlan`, `ReplayRun`, `ResultPresentation`,
`SessionCalibrationFramePolicy`, `SessionGates`, `SessionReplay`,
`SessionSidecarLocator`, `StrainProduct`, `SystemMonitor`,
`WorkspaceRecovery`; each with its own `App/AppState+<Feature>.swift`
orchestration file where cross-owner logic needs one (`+ACOM`,
`+Calibration`, `+DatasetSession`, `+DiffractionGroups`, `+DiskDetection`,
`+DPC`, `+MaterialsProject`, `+Open`, `+PhaseContrast`, `+PhaseMapping`,
`+Promote`, `+Replay`, `+ResultPresentation`).
The target the seams plan cited (`archive/v2/v2.5-plan.md` §4) goes further
than what shipped: one immutable `ScientificProduct` value type (pixels,
axes, units, frame, calibration snapshot, validity, provenance) with
`ProductPresentation` separate, and a typed task registry shared by live
runs and replay. That unification is not built — the per-feature owner
pattern above is the seams plan's actual, shipped shape.
Rules while extending: no new stored state in `AppState`; a feature names its
owner first; numerical code is split only at scientifically meaningful
boundaries. `AppState.swift` + `Support/ResultExport.swift` (1601 lines) are
size-tracked by `inventory` against the previous commit (`HEAD^` on a clean
tree, `HEAD` on a dirty one): growth is allowed where one of these two files
is the honest home for the state, and a commit that grows them says in its
message why no other home would do (owner, 2026-09-16).

## The UI contract

`UI/` was rebuilt from scratch in SwiftUI in 2026-09-04's migration; the
AppKit-hosted window it replaced was deleted the same day, so there is one UI
again and no flag selects it. Six rules, the first three enforced by
`run-tests.sh inventory`:

1. **SwiftUI only.** No `NSSplitViewController`, no hosted AppKit shell, no
   `NSEvent` monitors, no `NSCursor`, no AppKit layout, no `import AppKit`.
   The one permitted platform bridge is `MetalImageView`, which is written
   with a shared body and a two-line per-OS conformance.
2. **No AppKit shell.** `HSplitView`, `VSplitView`, `NSSplitView` and
   `NSSplitViewController` are banned outright — `HSplitView` was half of a
   launch crash (`open-items.md`) and is macOS-only besides. `inventory`
   greps for all four and for `import AppKit`.
3. **`LayoutPolicy` is the whole number budget.** Every column range, science
   floor, field width, thumbnail ceiling and sheet size is there and nowhere
   else. Outside it, a `.frame` is permitted only as scientific drawing
   geometry — the panes, overlays, scale bars, colorbars, histograms and
   legends, whose sizes are the image's, not the layout's.
4. **No pane focus model.** There is none, and the types that carried the old
   one — `WorkspaceNavigation.focusedPane` and `.inspectorContent` — were
   DELETED on 2026-09-04 (`f8a8c2d`), not merely left unused. Where the old UI switched its
   controls on which pane was "active", UI offers an explicit control;
   `AppState.activePane` survives only as the ROI direction's storage.
5. **No new state on `AppState`.** UI's selection is derived from
   `WorkspaceNavigation`, never stored beside it (`WorkspaceRoute`).
6. **The window is three full-height columns, one job each** (ADR 035/036;
   `docs/archive/v4/window-design.md`; shipped and driven-accepted in
   v4.0.0, 2026-09-23). Left is `WorkspaceSidebar`; right is
   `WorkspaceInspector`'s Settings · Info tabs, in one glass capsule row,
   presented as `.inspector` on the `NavigationSplitView` itself (not on the
   detail view) so it reaches the toolbar like the sidebar does. Both
   collapse completely and run from the toolbar to the window's bottom
   edge; below `LayoutPolicy.datasetWindowMinimumSize` (915 pt, both panels
   at their ideal width plus the science floor) a panel closes before a
   science pane shrinks past it — `WindowAnatomyPolicy` is retired, folded
   into `LayoutPolicy` and `WorkspaceNavigation`. Centre (`WorkspaceView`)
   is the science panes, the infobar (the column's own divider and drag
   handle) and the process area — **there is no canvas header**: the file
   name, the live run, and the room's one primary action (Save to Session,
   Reveal in Finder, the dataset menu) live in the standard toolbar instead
   (`ContentView.windowToolbarContent`), ranked by `.visibilityPriority` so
   the run verb and dataset switcher are the last to overflow as the window
   narrows. Readiness has one home, the Settings tab's first section
   (`UI/CalibrationReadinessRow.swift`). The inspector's row vocabulary is
   `UI/InspectorRows.swift` — flat HIG sections per Apple's own guidance
   (title is the leading disclosure, hairline, one bordered push button per
   row), not cards (ADR 037, superseded the same night it shipped). Each
   science pane's own header popover (`UI/PaneOverlays.swift`) carries that
   pane's contrast, histogram and gamma controls.
- **Navigation is a source list, settings are forms, and the two containers
  are not interchangeable.** Rule 1's `List(selection:)`/`.listStyle(.sidebar)`
  carries navigation; the decided inspector is one top-level `.columns`
  `Form` with `LabeledContent`,
  `Picker`, `Toggle`, `TextField`, `Slider`, `Button` as system controls, no
  hand-built rows with a `Spacer` between a label and its value.
  `LabeledContent` stacks a multi-element label vertically only inside a
  `Form`, so a row written for one crushes onto one line in the other.
- **Overflow is a finding; truncation is a choice.** A long value truncates
  the way Finder truncates a filename and Xcode truncates with a tooltip;
  text that must be read in full is short by construction or lives on
  `.help`. A gate that cannot see text (`controls(_:)` collects `NSControl`s,
  and no SwiftUI `Text` is one) cannot hold a rule about text.

## Requirements, build, test

- macOS 27+ on Apple Silicon — `MACOSX_DEPLOYMENT_TARGET = 27.0` in every
  build configuration and `.macOS("27.0")` in `Package.swift`, raised from
  14 on 2026-09-22 (`decisions.md` 008); v3.0.0's artefact (floor 14) stays
  downloadable for older systems. Xcode 27 or later — development is on
  27.0, CI on macos-26. No separately installed HDF5.
- Build: open `mac4DSTEM.xcodeproj`, scheme `mac4DSTEM`, `⌘R`; or
  `xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build`.
  Tools resolve their own toolchain via `tools/lib/developer-dir.sh`
  (`DEVELOPER_DIR` wins; the Command Line Tools directory is rejected).
- Test: `tools/run-tests.sh unit | scientific | all | inventory | core | benchmark | campaign` (seven lanes; the script is the roster).
  The `scientific` array in that script is the harness roster; no count is
  stated anywhere else. On-screen verification is the owner driving the app
  and reporting through `/diagnose` (the checklist was retired 2026-09-03).
- Never add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch.

## Tools and harnesses

`tools/run-tests.sh {unit|scientific|core|inventory|benchmark|campaign|all}`
is the one discoverable entry point over ~70 directories. Every directory
must appear in exactly one of five arrays at the top of that script —
`scientific` (CI-gated), `diagnostic` (needs gitignored/machine-local data,
never gated), `owner_only`, `retired`, `support` (`lib`, `release`,
`crystal-structures`) — plus `real-data-acceptance`/`package-test`, gated
only under `all`; `inventory` fails on any directory not classified.
Most harnesses are zsh `run.sh` scripts that compile a handful of production
`Core/` sources with `xcrun swiftc`, sourcing `tools/lib/sources.manifest`
first for a dependency-closed file list per named group (see "Project
structure", above). One needing the bundled HDF5 dylibs copies and
ad-hoc-codesigns them first, since the repo's signed copies won't validate
for an unsigned tool; one needing GPU kernels compiles `Shaders/*.metal` to a
`default.metallib` by hand. `tools/package-test/run.sh` runs a full
`xcodebuild -configuration Release` at the release archive's own
destination/architecture pin, because a prior gate on a generic destination
once stayed green an hour before an archive build failed.
`tools/free-space.sh` is the disk-space preflight remedy: `run-tests.sh`
refuses to start `unit`/`scientific`/`benchmark` below 4 GB free and
`all`/`campaign` below 8 GB (exit 69), reporting (or, with `--clear`,
deleting) known regenerable build debris only, never `References/`. Not
every harness is Swift: `tools/disk-detector/` is a Python
training/export/evaluation pipeline with its own frozen, gitignored
hand-labelled test set; `tools/comparator-test/` mutation-tests
`tools/real-data-acceptance/compare.py` itself, since a comparator that
quietly stopped checking something looks like a passing gate.

## HDF5 notes

`H5Reader` and the session writer `dlopen` `libhdf5.dylib` and bind every
symbol via `dlsym`, searching `MAC4DSTEM_HDF5_PATH` (harnesses), the bundle's
`Contents/Frameworks/`, then dyld's bare-name lookup. The target embeds and
signs `libhdf5`, `libsz.2`, `libaec.0`; App Sandbox with user-selected
read/write and app-scoped bookmarks. Release enables Hardened Runtime; local
Debug builds leave it off so macOS accepts the separately signed closure.
Distribution always uses hardened Release (`releasing.md`). HDF5 access is
serialised process-wide by a lock, not an actor: `HDF5Serial`
(`Core/Data/HDF5Types.swift`) is acquired and released around every
`H5Reader` public method's body, recursive so a nested entry does not
deadlock and never held across an `await`.

## Known limitations

- Tiles are expanded to float32; native-dtype kernels would cut bandwidth.
  The app always streams; the resident path is reachable only from harnesses.
- Metal commands cannot be interrupted after submission: Cancel discards the
  cancelled run's result immediately while the in-flight command finishes;
  a streaming pass waits out at most one tile.
- Session rehydration is pixel and metadata level; transient arrays are not reconstructed.
- Origin coarse search deviates from py4DSTEM (binned block-sum argmax); the
  probe-size fallback can look usable where py4DSTEM would return NaN
  (`open-items.md`).
- No non-Metal fallback; `MetalEngine` fails fatally without a device.
- R–Q rotation has an inherent 180° ambiguity (Flip 180° in Calibration).
- MIB/EMPAD readers are Preview until real vendor acquisitions are supplied.
- Bundle identifier `com.mac4dstem.mac4DSTEM` keys the sandbox container and
  bookmarks; it cannot change again without breaking existing installs.

## Developer notes

- One `@main` in `App/mac4DSTEMApp.swift`; the root view is
  `UI/ContentView.swift`. See "The UI contract" above.
- Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
  blocking compute types are `nonisolated` and run via `Task.detached`;
  readers are actors; long analyses guard publication with dataset epoch and
  operation token. Never conscript the main thread with `concurrentPerform`
  (the frozen-Detect-All-Disks lesson).
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the
  `.metal` structs (all 4-byte fields).
- Debug builds compile the app module at `-O` so interactive science is never
  benchmarked at `-Onone`.
