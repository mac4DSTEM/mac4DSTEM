# ARCHITECTURE.md — fresh-eyes read (from code, tests and tooling only)

Everything below is traced to a file in this checkout. Where a claim rests
on a code *comment* rather than executable code, that is said explicitly.

## 1. Layering

```
UI/            SwiftUI views only. Reads/drives App+Session+Core, adds no state.
   |
App/           AppState (the composition root) + its per-feature extensions
   |           and app-level orchestration/navigation.
   v
Session/       DSTEMSession package. Calibration state, products, recipes
   |           and replay, sidecar location, recovery, residency. No SwiftUI.
   v
Core/          DSTEMCore package. File formats, the 4D array abstraction,
               algorithms (Analysis/, Crystal/, ML/), Metal (Compute/).
               No SwiftUI, no AppKit, no App-level types.

Support/       App-adjacent glue that isn't science or UI (export, metadata).
Shaders/       .metal kernels, compiled into the bundle's default.metallib.
```

Two independent enforcement mechanisms back this, not just convention:

- **`Package.swift`** defines `DSTEMCore` (`path: mac4DSTEM/Core`) and
  `DSTEMSession` (`path: mac4DSTEM/Session`, `dependencies: ["DSTEMCore"]`)
  as standalone SwiftPM library targets. Its own comment states the
  purpose: "this package exists so that `swift build` fails the moment
  Core/ reaches upward into App/, UI/ or Support/" — run as
  `tools/run-tests.sh core`. The Xcode app target compiles the *same*
  source files directly (a `PBXFileSystemSynchronizedRootGroup` for the
  `mac4DSTEM/` folder, with an explicit exception list in
  `project.pbxproj` enumerating every `Core/` and `Session/` file plus
  `Info.plist` — lines ~59–151), so the package and the app target never
  drift apart file-for-file.
- **`tools/run-tests.sh`'s `inventory` function** greps `UI/*.swift` for
  `import AppKit` and for `HSplitView`/`VSplitView`/`NSSplitView`/
  `NSSplitViewController` and fails the gate if any appear (a defect
  history is cited in a comment there: the app "aborted on launch in
  AppKit's update-constraints guard" the one time this was tried).

Verified directly (not just asserted by comment): `grep -rn "import
AppKit\|import SwiftUI" mac4DSTEM/Core mac4DSTEM/Session` returns nothing.

Both packages share one Swift 6 concurrency configuration
(`Package.swift`): Swift language mode 5, **`.defaultIsolation(MainActor.self)`**
— i.e. every type is MainActor-isolated *by default* — plus
`NonisolatedNonsendingByDefault`, `InferIsolatedConformances`,
`InferSendableFromCaptures`, `MemberImportVisibility`. Because MainActor is
the default, GPU dispatch and CPU-heavy work must be explicitly marked
`nonisolated` to run off the main thread; `grep -rln nonisolated
mac4DSTEM/Core` matches 61 files. A real bug from getting this wrong is
documented in `Core/ML/LearnedDiskDetection.swift`: an extension member
without `nonisolated` silently inherited `@MainActor` and pinned every
progress callback to the main thread (measured: "5 of 5... 847/847
main-thread samples"). Bare `swiftc` (used by most `tools/` harnesses)
defaults to *non*isolated, so a harness built without matching
`-default-isolation MainActor` flags cannot see this class of defect at
all — `tools/lib/sources.manifest` calls this out as a documented,
narrowed-not-closed blind spot and supplies `MAC4DSTEM_ISOLATION_FLAGS` for
harnesses that opt in. **The Xcode app build is the only real gate for
actor isolation**; nothing under `App/`/`UI/` is ever compiled into a
`tools/` harness (`sources.manifest`: "Groups intentionally stop at Core/").

Cross-module visibility uses Swift's `package` access level throughout
(`package nonisolated struct DatasetDescriptor`, `package actor
FourDArray`, `package final class SessionGates`, etc.) — types are visible
across `DSTEMCore`/`DSTEMSession`/the app target without being `public`,
i.e. without becoming a published API surface. Files compiled into both the
app target and a standalone `tools/` harness guard the package imports:
`#if canImport(DSTEMCore) import DSTEMCore import DSTEMSession #endif`.

## 2. Ownership of state

**`AppState`** (`App/AppState.swift`, 5,461 lines, `@Observable final class`,
line 87) is the composition root and the thing SwiftUI actually observes.
One instance is created per window, *below* `WindowGroup` rather than on
`App` — `App/mac4DSTEMApp.swift`: "prevents a second dataset window from
replacing the first window's reader, calibration, cancellation token, or
results." It is injected via `.environment(appState)` and separately
exposed to menu commands through a `FocusedValueKey`
(`mac4DSTEMApp.swift:7-16`). Multiple `AppState` instances can coexist (one
per window); libhdf5 itself is process-wide and not thread-safe (a plain
global error stack, per comment), which is a known open constraint on
concurrent windows, not a solved one.

`AppState` does not hold most feature state as bare properties. Instead it
composes one `let`-held object per feature/seam, each an `@Observable`
class living in `Session/` (science/session state) or `App/` (pure
view-state with no science), with **no forwarding properties** — call sites
write `appState.strain.map`, never a proxy `appState.strainMap`. Confirmed
directly in `AppState.swift`:

| Property | Type | Home |
|---|---|---|
| `residency` | `DatasetResidency` | Session/ |
| `loadedView` | `LoadedView` | Session/ |
| `sessionSidecar` | `SessionSidecarLocator` | Session/ |
| `recents` | `RecentDatasets` | Session/ |
| `replay` / `replayRun` | `SessionReplay` / `ReplayRun` | Session/ |
| `gates` | `SessionGates` | Session/ |
| `strain` / `diffractionGroups` / `phaseMapping` | `StrainProduct` etc. | Session/ |
| `qCalibration` | `QCalibrationRun` | Session/ |
| `calibrationSession` | `CalibrationSession` | Session/ |
| `acomSession` | `ACOMSession` | Session/ |
| `learnedDetection` | `LearnedDetectionSession` | Session/ |
| `diskCentreLabels` | `DiskCentreLabelStore` | Session/ |
| `operationCenter` | `OperationCenter` | Session/ |
| `navigation` | `WorkspaceNavigation` | App/ (pure view-state, no science) |
| `activityLog` | `ActivityLog` | App/ |

Each extraction is described, in the type's own header, as fixing a
specific found defect — e.g. `Session/SessionGates.swift`'s header
describes two call sites (physical iDPC, Q calibration) that used to derive
the same "may I trust this origin fit?" judgement two different ways.
`Session/'s` own self-description, from `Package.swift`: "calibration
state, products, recipes and replay, sidecar location, recovery,
residency — no SwiftUI, no AppState." `Core/` owns "the science" itself
(quote, `SessionGates.swift`): predicates live in `Core/Data/Calibration.swift`;
Session only owns the rule that app code asks the gate instead of
re-deriving the judgement.

**A size budget forces this discipline rather than leaving it optional.**
`tools/run-tests.sh`'s `inventory` function sums `App/AppState.swift` +
`Support/ResultExport.swift` against the previous commit (`HEAD^` on a
clean tree, `HEAD` on a dirty one) and reports growth (this used to fail
the gate outright; comments in the script mark that as relaxed by the
owner on 2026-09-16 to a report, "since growth is allowed where these
files are the honest home for the state," while the caution/measurement
stays). Multiple relocations are tagged in comments as done specifically
"to pay down the AppState + ResultExport budget" (e.g.
`Session/SessionGates.swift`, `App/WorkspaceNavigation.swift`).

**What still lives as bare `AppState` properties** (i.e., hasn't earned its
own seam yet): a large amount of per-analysis-mode raw state — roughly 20
parallax/ptychography scalars, `diskParams`, `currentPeaks`,
`braggVectors`, `descriptor`, `selectedScan`, `currentPattern`,
`publishedProduct`, `fourD`/`reader` (private). The pattern is evidently
incremental — one seam extracted per session that touches that area — not
a wholesale refactor.

**Views add no state of their own.** `UI/WorkspaceRoute.swift`'s own
comment: "The route is derived from `WorkspaceNavigation`, never stored
beside it: UI adds no state to `AppState`."

## 3. Data flow: file on disk → pixels on screen

1. **Open.** `AppState` picks a reader by extension (`.dm4`/`.dm3` →
   `DM4Reader`, `.mib`/`.raw`/`.xml` → `VendorRawReaders`'s
   `MIBReader`/`EMPADReader`, default → `H5Reader`; `Core/Data/`). All
   readers conform to `package protocol FourDDataSource: Actor`
   (`Core/Data/FourDDataSource.swift`) — every reader is a Swift `actor`,
   so file I/O is serialized off the main actor. `DemoFourDDataSource`
   implements the same protocol for the built-in fixture without touching
   disk.
2. **Discover.** `reader.discoverPrimaryDataset()` returns a
   `DatasetDescriptor` (`Core/Data/DatasetDescriptor.swift`) describing the
   file's shape/dtype at full extent.
3. **Specify the view.** `LoadSpecification` (`Core/Data/LoadSpecification.swift`)
   records what part of the file is actually loaded — its own header: "A
   LOAD IS A VIEW, NOT A NEW DATASET... changing the specification reopens,
   it does not re-derive from reduced data." A `LoadView` pairs a
   descriptor with a specification.
4. **Decode / stream.** `package actor FourDArray` (`Core/Data/FourDArray.swift`)
   wraps the reader + `LoadView`, exposes `pattern(ry:rx:)` and
   `scanTile(yRange:)`, keeps an LRU pattern cache, and can go "resident"
   (whole cube in one `MTLBuffer`) via `ResidentCube`
   (`Core/Data/ResidentCube.swift`), gated by `Session/DatasetResidency.swift`
   ("Nothing outside may set `isResident`," per its header).
5. **Compute.** Per-mode analysis in `Core/Analysis/` and `Core/Crystal/`.
   Some paths run pure CPU (Accelerate/vDSP `FFT2D`, e.g. `DiskDetection.swift`,
   `StrainMapping.swift`); others dispatch to `Core/Compute/MetalEngine.swift`,
   which owns the `MTLDevice`/queue/`default.metallib` and exposes six
   `package func` GPU calls (`virtualDetector`, `virtualImage`,
   `virtualDiffraction`, `dpStatistics`, `measureOrigins`, `centerOfMass`),
   each **synchronous and blocking** (`commit()` + `waitUntilCompleted()`
   — comments on `VirtualDetector.swift` and `MetalEngine.swift` both say
   to call these only from a background `Task`, never the default
   MainActor context). Four Swift-side parameter structs in
   `MetalEngine.swift` (`CubeDims`, `ApertureParams`, `CoMParams`,
   `OriginParams`) must stay byte-identical to their `.metal` twins — see
   §7. `Core/Crystal/OrientationMatcher.swift` (ACOM) is the one place that
   builds its **own** Metal pipeline state directly against
   `MetalEngine.shared.{device,queue,library}` rather than going through
   `MetalEngine`'s cached-pipeline methods — a second, less-guarded pattern
   for "how a file gets a `MTLComputePipelineState`" worth knowing about.
   `Core/ML/LearnedDiskDetector.swift` is a third, Core-ML/Neural-Engine
   path: it proposes disk-centre *candidates* from a heatmap, but always
   hands them to the same classical `DiskDetector.refine(...)` for the
   actual subpixel measurement ("a candidate stage, never a measurement,"
   per its header) — there is no shared protocol between the classical and
   learned detectors, only a matching call shape.
6. **Publish.** A result becomes a `DisplayedProduct`
   (`Core/Data/DisplayedProduct.swift`) — an immutable bundle of pixel
   payload (`.scalar(FloatImage)`/`.rgba(RGBAImage)`), a `ProductDomain`
   (`.scan`/`.detector`/`.reconstruction`), a `ProductQuantitativeStatus`
   (`.quantitative`/`.relative`/`.exploratory`/`.categorical`), sampling
   (pixel size/units), a flat `provenance: [String:String]`, and overlays —
   its own header: "Pixel payload, coordinate domain, validity, units,
   provenance, and fit evidence travel together so UI code never has to
   infer semantics from a display title or array dimensions." `AppState`
   holds the live one as `publishedProduct`, written by exactly one choke
   point, `AppState.publishProduct(...)`, which every per-mode run function
   is being migrated to call (its own comment: "one site at a time").
7. **Record the recipe.** `Session/SessionReplay.swift` records completed
   runs into a `SessionReplayRecord` (`Core/Data/SessionReplayRecord.swift`)
   — an ordered list of `{kind, parameters, recorded}` steps, "one step per
   analysis kind, in FIRST-RUN order... not a keystroke log" (its header).
   `Session/ReplayPlan.swift` is the parser that turns a recorded step back
   into typed parameters for replay/promote runs; its header explains why
   it lives in Session rather than Core — its output vocabulary is
   App-level workflow state, so a Core placement would invert the
   dependency the layering rule protects.
8. **Show.** `UI/` renders `appState.publishedProduct` and friends via
   `@Environment(AppState.self)` (`ContentView.swift`). The one SwiftUI↔Metal
   bridge is `UI/MetalImageView.swift` — its own header: "the one SwiftUI to
   Metal bridge in UI," drawing already-normalized pixels through
   `MetalEngine`'s display pipeline (fullscreen triangle + colormap LUT) or
   packed RGBA8 through a second pipeline; a `contentVersion` the caller
   must bump on every pixel change gates re-upload (a comment names a
   previously-shipped defect: a literal `0` here froze a comparison panel
   on stale pixels).
9. **Export / persist.** `Support/ResultExport.swift` (an `AppState`
   extension, 1,939 lines) writes PNG (with burned-in scale bar, caption,
   and full provenance in PNG metadata), CSV of Bragg peaks, and
   py4DSTEM/EMD-compatible HDF5 (`Core/Data/BraggVectorEMDWriter.swift`).
   Two independent guardrails apply: (a) sidecar-rewriting entry points
   call `gates.sidecarRewriteRefusal()` first and abort on a non-nil
   reason (`Session/SessionGates.swift`) — the gate exists because "every
   sidecar rewrite restates the CURRENT view's specification," so a save
   after a failed crop restore would silently relabel preserved
   scan-indexed results as full-extent; (b) provenance is composed in one
   place per fact (`originFitProvenance`, `strainFrameProvenance` in
   `ResultExport.swift`) specifically so two export paths can't disagree,
   and is snapshotted **at compute time**, not read live off current
   calibration, per a dated, cited defect ("Gate B, 2026-08-28").
   `Support/ResultMetadata.swift` supplies the `kind`/`displayName`/
   `valueUnits` triple that seeds this provenance per analysis mode, and
   was itself split out of `ResultExport.swift` purely to stay under the
   §2 size budget.

## 4. Where new code goes

- **A new file format or reader** → `Core/Data/`, conforming to
  `FourDDataSource` (an `actor`).
- **A new classical analysis algorithm** → `Core/Analysis/`. If it ports a
  py4DSTEM routine and departs from it, mark the departure with an inline
  `DEVIATION` comment citing the upstream file/line and, ideally, a
  measured effect (33 existing examples under `Core/`, the convention is
  followed even inside `.metal` shaders). Add the new source file to the
  right group in `tools/lib/sources.manifest` (groups are dependency-closed
  — asking for one group pulls in everything it needs, in compile order)
  or an existing standalone harness will silently stop compiling against
  it, which is the exact 2026-08-17 failure the manifest's header
  documents.
- **A new GPU kernel** → a `.metal` file in `Shaders/`, a matching
  `package nonisolated struct ...Params` in `Core/Compute/MetalEngine.swift`
  with a `// MUST match <Struct> in MetalEngine.swift (all 4-byte fields)`
  comment on the Metal side, and a `package func` on `MetalEngine`
  following the existing synchronous-`waitUntilCompleted` pattern.
- **Crystallography / ACOM / phase-mapping** → `Core/Crystal/`, downstream
  of `Core/Analysis` (`BraggVectors`) and calibration
  (origin/Å⁻¹-per-pixel).
- **A learned/Core ML path** → `Core/ML/`, kept deliberately self-contained
  rather than sharing a base with the classical orchestrator it augments
  (`Core/ML/LearnedDiskDetection.swift`'s own comment states this is
  intentional); guard Apple-Silicon-only code with `#if !arch(arm64)
  #error(...)`, not a silent `#if arch(arm64)`, per the documented reason
  (a bare `#if` would ship a broken x86_64 slice instead of failing the
  build).
- **Cross-cutting session state, a product, a policy gate, recipes/replay**
  → `Session/`. No SwiftUI. Hold it in `AppState` as a `let` with no
  forwarding properties.
- **Pure app-level view-state with no science** (navigation, focus, a
  route) → `App/`, same "no forwarding properties" rule; consider an
  `AppState+<Feature>.swift` extension file if the orchestration needs
  `AppState`'s other state (dataset, calibration, cancellation) but the
  retained state itself lives in a Session/ product type.
- **Any view** → `UI/`, SwiftUI only, reads `AppState` via
  `@Environment(AppState.self)`, adds no stored state, respects
  `LayoutPolicy.swift`'s numbers and the chrome/frame exemption list (see
  §7). `PaneOverlays.swift` is the one file where ad hoc drawing geometry
  is expected — its own header: "the ONE UI file where custom drawing is
  expected... none of it sizes text for a form."
- **A new standalone harness** → `tools/<name>/`, with a `run.sh` that
  sources `tools/lib/sources.manifest` (or says in one comment line why
  not) and is added to exactly one of `run-tests.sh`'s classification
  arrays (see §6) or the `inventory` gate fails on an `UNCLASSIFIED` entry.
- **A unit test** → `mac4DSTEMTests/`, XCTest (see §6).

## 5. Presentation contract

UI/, enforced by grep in `tools/run-tests.sh`'s `inventory` function, not
by a test:

- No custom `.background(.bar)` or `Color….opacity(...)` wash in the chrome
  outside `ImagePanes.swift`, `PaneOverlays.swift`, `LoadConfigurator.swift`,
  `MetalImageView.swift`, `HistogramView.swift` (rule 3's exempt list).
- No fixed numeric `.frame(...)` outside `LayoutPolicy.swift`'s named
  constants, `ImagePanes.swift`, `PaneOverlays.swift`, `HistogramView.swift`,
  `ResultsWorkspace.swift`, and `LoadConfigurator.swift` (rule 4's exempt
  list — note it swaps in `ResultsWorkspace.swift` and drops
  `MetalImageView.swift` relative to rule 3's list just above; the two
  grep patterns are independent and not identical). `LayoutPolicy.swift`
  calls itself "UI's whole number budget, in one file," under the rule
  "SwiftUI decides size, we decide bounds." *Caveat:* a comment two lines
  above rule 4's grep pattern in `run-tests.sh` names
  `FormPolicy`/`WindowPolicy`/`FormControls.swift` — none of those symbols
  or that file exist anywhere in the tree today (confirmed independently
  twice in this audit). The grep itself matches `LayoutPolicy\.`, which is
  correct and current; the comment beside it is stale, presumably from
  before a rename/consolidation.
- No `HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`
  anywhere in `UI/`, and no `import AppKit`. `ContentView.swift`'s own doc
  comment states the frozen structure this protects: `NavigationSplitView`
  + the native `.inspector`, nothing else, "no call into a view under
  `UI/`" from outside it — "UI reads and drives the shared `App/`,
  `Session/` and `Core/` logic, and nothing else." The draggable divider
  between the two image panes is a hand-rolled `PaneSplit<Leading,Trailing>`
  (`WorkspaceView.swift`, `GeometryReader` + `HStack` + a `Divider`,
  fraction persisted in `@SceneStorage`) rather than `HSplitView` — its own
  comment records the Gate D investigation into why `HSplitView` nested
  inside `NavigationSplitView` + `.inspector` aborted the app at launch in
  AppKit's constraint machinery, and is explicit that the *mechanism* was
  never fully established, only that the replacement is safe either way.

Two small, independent navigation/selection types worth knowing before
adding a third: `WorkspaceRoute` (`UI/WorkspaceRoute.swift`) is a derived,
not stored, `enum` read by the sidebar's `List(selection:)`, computed fresh
from `AppState.navigation` on every read rather than cached; and
`ActivePane` (`enum ActivePane { case diffraction, realSpace }`, defined in
`App/AppState.swift`, not `UI/`) tracks which image pane last received a
click, for routing ROI tools. `UI/PaneOverlays.swift` separately defines
its own small, file-private `enum Pane { case diffraction, result }` scoped
to one chip view — the two "pane" enums are unrelated and neither is a
shared protocol; there is no `Pane` protocol in the codebase.

## 6. Test structure

`mac4DSTEMTests/` — 65 files, ~17,600 lines, one Xcode target
(`mac4DSTEMTests.xctest`), built via `xcodebuild test
-only-testing:mac4DSTEMTests` (`tools/run-tests.sh`'s `unit_tests`
function; run in an isolated `DerivedData` under `$TMPDIR`, never the
signed app's own, "HDF5 is loaded lazily... overwriting a running app can
otherwise... make macOS reject the library," per that function's comment).
All 65 files use **XCTest**; none use the newer Swift Testing (`@Test`,
`import Testing`) framework, and no test file imports `SwiftUI` or renders
a view — tests exercise `AppState`'s non-View surface, `Core`/`Session`
types directly, and the small pure UI-geometry helpers (`ZoomPan`,
`ComparisonHoverMapping`, `RealSpacePointerPolicy`), never a `View.body`.
Tests `@testable import mac4DSTEM` plus `import DSTEMCore`/`DSTEMSession`,
and are `@MainActor` whenever they construct a real `AppState`. File names
and header comments tie many tests to a numbered development session,
review gate, or finding rather than only to the type under test — session
numbers (`S1`…`S22e`, e.g. `S22ePolishTests.swift`), gate letters (`Gate
A`–`Gate D`, e.g. `LearnedDiskDetectorGateBTests.swift`), "Track B" finding
numbers (`TB1StallProbeTests.swift`), and lettered review-finding IDs
(`C4(a)`, `C5`, …) all recur across file headers, e.g.
`SessionGatesTests.swift`: "Wiring tests go through a REAL AppState (the
S5/F8 lesson: pure-type tests leave every wiring line deletable with the
suite green)." `ErrorRoutingTests.swift` pins a routing rule directly:
recoverable compute failures stay on the status bar + log; only
session-level failures (file open/read, dataset activation) raise the
modal alert, "because the modal swallows every later interaction in the
window." The presentation-contract rules in §5 have **no** XCTest
counterpart — a repo-wide search for `LayoutPolicy`/`HSplitView`/
`NSSplitView` inside `mac4DSTEMTests/` turns up only one incidental,
narrower check (`StatusBarMetricsTests.swift` pins one string against
`LayoutPolicy.operationReadoutWidth`); the structural rules are enforced
solely by the shell grep gates in §5.

## 7. `tools/` harness structure

~70 directories, one discoverable entry point: `tools/run-tests.sh
{unit|scientific|core|inventory|benchmark|campaign|all}`. Every directory
must appear in exactly one of five arrays defined at the top of that
script — `scientific` (~50 entries, CI-gated), `diagnostic` (needs
gitignored/machine-local data, never gated), `owner_only`, `retired`,
`support` (`lib`, `release`, `crystal-structures`) — plus
`real-data-acceptance`/`package-test`, gated only under `all`. The
`inventory` function fails on any directory not in that classification.

Most harnesses are zsh `run.sh` scripts that compile a handful of
production `Core/` sources directly with `xcrun swiftc`, sourcing
`tools/lib/sources.manifest` first to get a correct, deduplicated,
dependency-closed file list for a named group (e.g. `mac4dstem_sources
"$REPO" readers calibration`) — the manifest's header explains why this
file exists: on 2026-08-17 the same source list, hand-spelled three
different ways across `run.sh` files, drifted and silently broke 5 of 8
harnesses when one `Core/Data` file was added. A harness needing the
bundled HDF5 dylibs copies and ad-hoc-codesigns them into a temp
directory first (`tools/calibration-test/run.sh`), since the repo's own
signed copies won't validate for an unsigned tool. A harness needing GPU
kernels compiles `Shaders/*.metal` to `.air` and links a `default.metallib`
by hand (`tools/performance-baseline/run.sh`), since only the Xcode bundle
build does that automatically. `tools/package-test/run.sh` instead does a
full `xcodebuild -configuration Release` using the same destination/arch
pin as the real release-archive build, specifically because a prior gate
that used a different destination stayed green an hour before an actual
release archive failed to compile.

Scientific parity harnesses compare against `References/py4DSTEM-dev`, a
gitignored checkout fetched at one pinned upstream commit by
`tools/lib/fetch-py4dstem.sh`; `tools/lib/py4dstem-ci-constraints.txt` pins
the Python numerical stack so an unrelated upstream release can't shift the
gate. `.gitattributes` marks `References/**` `linguist-vendored` so GitHub's
language detection doesn't report the repo as majority Python. Inline
`DEVIATION` comments in `Core/` cite this pinned commit's files/lines, which
is why the pin — not a moving upstream — is treated as load-bearing.

Not every harness is Swift: `tools/disk-detector/` is a Python training/
export/evaluation pipeline (`train.py`, `export.py`, `simulate.py`,
`evaluate.py`) for the Core ML disk detector, with its own frozen,
gitignored hand-labelled test set (`tools/disk-detector/labels/`, excluded
in `.gitignore` with a note that its hash/count are recorded elsewhere).
`tools/comparator-test/` is pure Python with no Swift compilation at all —
it exists to mutation-test `tools/real-data-acceptance/compare.py` itself
("break the real-data-acceptance comparator before trusting it," its
header), on the stated premise that a comparator that has quietly stopped
checking something looks exactly like a passing gate.

`tools/free-space.sh` is the disk-space preflight remedy: `run-tests.sh`
refuses to start `unit`/`scientific`/`benchmark` below 4 GB free and
`all`/`campaign` below 8 GB (exit 69) because a near-full disk has
produced spurious, non-code-related failures before; `free-space.sh`
reports (or, with `--clear`, deletes) known regenerable build debris only,
never touching `References/` or the repo itself.

## 8. Other invariants a newcomer must not break

- The redistributed HDF5/libaec/libsz dylibs are named and SHA-256-pinned
  in `NOTICE`; the `inventory` gate recomputes each hash and fails on a
  mismatch, and separately fails if `otool -L` shows an absolute
  (non-relocatable) load path on any of them.
- Every file inside a bundled Xcode folder reference (`project.pbxproj`
  `lastKnownFileType = folder` — currently `Models/DiskDetector` and
  `Licenses`) must be tracked in git, or it is silently present on the
  machine that built it and silently missing from a fresh clone; the
  `inventory` gate checks this with `git ls-files`. `.gitignore` documents
  a real past instance: `*.mlmodel` swallowed the shipping detector's
  model spec inside its own `.mlpackage`, so the gate was later widened to
  re-include that one path explicitly (`!Models/DiskDetector/...`).
- `CFBundleDocumentTypes` in `Info.plist` (h5, hdf5, emd, dm4, dm3, mib)
  mirrors the importer's accepted extensions in `ContentView.swift` minus
  `raw`/`xml` — deliberately: Info.plist's own comment says declaring
  those two "would put mac4DSTEM in the Open With menu of every XML file
  on the machine." The importer (Cmd-O / drag-in) still accepts a broader
  set than Finder's Open-With registration does.
- File-path citations inside any doc that claims current truth are
  gate-checked against the real tree (a `docs/*.md` file, if present, is
  not exempt just because it's prose) — a cited path that doesn't resolve
  fails `inventory`. This snapshot has no such docs to check, but the
  mechanism is real and worth knowing before adding one back.
- Comments are not guaranteed current: this audit found at least two
  concrete instances of a comment naming a symbol or file that no longer
  exists (`FormPolicy`/`WindowPolicy`/`FormControls.swift`, §5; a test
  header citing `App/StrainProduct.swift` for a type that now lives in
  `Session/StrainProduct.swift`). Prefer the enforced mechanism (a grep
  pattern, a compiler boundary) over a nearby comment's file path when the
  two disagree.
