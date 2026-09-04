# Architecture

What the app is made of, how the layers depend on each other, where a new
file goes, and where the consolidation is taking the ownership model. Product
scope is `README.md` and `CHANGELOG.md`; live status is `status.md`; the
sequence of the consolidation is `archive/v2/v2.5-plan.md`; the feature plan is `v3-plan.md`.

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
builds `Core/` as `DSTEMCore` and `Session/` as `DSTEMSession`; the app
target depends on both products and excludes those folders from its own
synchronized group; their declarations use the `package` access level (the
app and test targets set `SWIFT_PACKAGE_NAME = mac4dstem`).
`tools/run-tests.sh core` builds the packages alone, also in CI. A new type
in either package must be `package` and, if constructed from App, carry an
explicit `package init`.

## What it does, by subsystem

**Workflow.** Five workspaces — **Prepare / Imaging / Strain & ACOM / Phase /
Results** (`⌘1…⌘5`). Navigation is side-effect free; whole-scan work starts
only from an explicit primary action, runs detached with live progress and
Cancel, and reports in the permanent status footer.

**Data and display.** HDF5 (`.h5`/`.hdf5`/`.emd` — py4DSTEM, Gatan, HyperSpy
and arbitrary EMD layouts via link traversal), Gatan DM3/DM4 (`dm4-format.md`),
Preview-tier EMPAD RAW/XML and Merlin MIB. HDF5 is loaded at runtime via
`dlopen` (see HDF5 notes). Open with options: scan crop, detector crop,
detector bin; streaming residency bounds peak memory independent of scan size.
GPU-rendered viewers with colormap LUTs on each pane's colorbar chip, log
scaling, per-view contrast and gamma, calibrated 1-2-5 scale bars.

**Virtual imaging and diffraction.** BF/ADF/HAADF presets, draggable annular
aperture, rectangle and point detectors, and the reciprocal operation:
real-space ROIs drive selected-area diffraction.

**Calibration.** Origin (py4DSTEM `get_probe_size` → `get_origin` →
`fit_origin`, probe measured on the mean pattern), R–Q rotation via CoM-curl
minimisation with explicit 180° flip, elliptical distortion (conic and
11-parameter amorphous-ring), Q calibration against a known crystal
(`q-calibration-design.md`). Every value carries provenance; a fit that fails
its gate reports "not quantitative" rather than a number. Session calibration
from a different frame is re-referenced or refused (`SessionCalibrationFramePolicy`).

**DPC / iDPC.** Four views off one cached CoM field; iDPC is quantitative
projected phase only when origin, rotation and both samplings are present.

**Bragg disk detection.** Port of `find_Bragg_disks` with synthetic or measured
probe kernel, hybrid cross-correlation, and pixel / parabolic / DFT-upsampled
subpixel refinement. `FFT2D` is an exact Bluestein transform for any detector
length. Staleness tracking keeps changed settings from silently feeding strain
or ACOM.

**Strain mapping.** py4DSTEM `process/strain`: consensus or manual g₁/g₂,
robust local lattice fits, component-median reference, εxx/εyy/εxy/θ with
unfittable positions as explicit no-data.

**ACOM orientation mapping.** Polar-correlation template matching against a
validated `CrystalModel` catalogue (cubic presets, HCP magnesium, 2H-WS₂,
custom cubic, imported CIF through the same validation). CPU and Metal
backends with parity gating, reliability, IPF-Z maps, Bunge Euler output.
Physical matching requires calibrated Q sampling; otherwise **Exploratory**.
Point-group coverage is cubic and hexagonal only, by decision: CIFs outside
them are refused, not coerced.

**Parallax and ptychography.** Staged parallax (calibrated virtual-BF
preprocessing → alignment → aberration fitting → CTF correction → subpixel
upsampling → depth sectioning) and a single-slice iterative ptychography
engine, each memory-bounded, cancellable and source-locked to py4DSTEM.

**Sessions, recipes, export.** A `<source>.mac4dstem.h5` sidecar holds named
results, calibration, BraggVectors and the replay record; every sidecar names
the oldest reader that interprets it without misreading. A rehearsal on a
view records a recipe; promote replays it on the full cube, re-referencing
detector-pixel parameters into the source frame and refusing by name what it
cannot re-express. Exports: PNG as displayed, Bragg peaks CSV, py4DSTEM
`BraggVectors`, calibrated reduced `DataCube` carrying the recipe.

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

## Ownership today and where it is going

Today `AppState` (`App/AppState.swift`) owns loading, session state, calibration,
every analysis's parameters and dispatch, product publication, replay and
recovery; `ContentView` reconstructs workflow rules from it. Extracted seams
already exist (`DatasetResidency`, `SessionGates`, `WorkspaceNavigation`,
`StrainProduct`, `ReplayRun`, `QCalibrationRun`, `SessionCalibrationFramePolicy`).

The target (`archive/v2/v2.5-plan.md` §4): three local packages — `DSTEMCore` (Data,
Compute, Analysis, Crystal, Shaders), `DSTEMSession` (calibration, products,
recipes and replay, operation lifecycle) and the app; `ScientificProduct` as
an immutable value owning pixels, axes, units, frame, calibration snapshot,
validity and provenance, with `ProductPresentation` separate; narrow
per-analysis controllers; a typed task registry that is also the recipe
vocabulary, so live runs and replay share one execution path; `AppState`
reduced to composition and window coordination.

Rules while migrating: no new stored state in `AppState`; a feature names its
owner first; adapters carry an expiry condition; numerical code is split only
at scientifically meaningful boundaries.

## Presentation contract (owner decision 2026-09-03)

The app should feel and behave like it shipped with macOS. That is a
contract, not taste, and it is checkable:

1. **Structure is fixed, content is fluid.** The window is a toolbar over
   three AppKit columns (`ColumnSplitController`): tools on the left,
   the workspace, the inspector on the right with information — dataset,
   product, preview, sidecar, diagnostics. Columns have bounds; nothing
   inside a column sizes itself. A control is as wide as its content, text
   wraps, images are capped, spare width is margin.
2. **Navigation is a source list, settings are forms.** *(Amended
   2026-09-04; the original rule said every group of controls is a `Form`,
   which is a category error — a grouped `Form` is System Settings' detail
   pane, it has no `selection:` parameter, and applying it to navigation left
   the app with no `List` anywhere and no way to draw a selection.)*
   Navigation is `List(selection:)` with `.listStyle(.sidebar)`. Controls are
   a grouped `Form` with `LabeledContent`, `Picker`, `Toggle`, `TextField`,
   `Slider`, `Button` as system controls; no hand-built rows with a `Spacer`
   between a label and its value. The two containers are **not**
   interchangeable: `LabeledContent` stacks a multi-element label vertically
   only inside a `Form`, so a row written for one crushes onto one line in
   the other.
3. **System materials only.** No `.background(...)` colours or tints, no
   custom bars, no opacity washes, no drawn separators: the toolbar, the
   sidebar, the inspector, the footer and the log strip take the system's
   appearance (Liquid Glass on macOS 26) from their containers. The only
   custom drawing is scientific: the Metal image panes, overlays, scale
   bars, histograms, and the small task and workspace glyphs, which are
   SF Symbols or symbol images so they render in the system's styles.
4. **No fixed frames except the science.** `.frame(width:)`/`minWidth:`
   are allowed only on image panes and their floors. Thumbnails cap their
   height by rule, not by a number per site.
5. **Every column survives its whole range.** Each sidebar and inspector
   is measured in the hosted layout tests at the column's minimum, ideal
   and maximum width. *(Amended 2026-09-04; the original rule said
   "wrapped text is fine, truncation and overflow are findings", which is
   backwards for a fixed-width column — unbounded wrapping is what made the
   old column a wall — and its gate cannot see the case anyway, because
   `controls(_:)` collects `NSControl`s and no SwiftUI `Text` is one.)*
   **Overflow is a finding; truncation is a choice.** A long value truncates
   the way Finder truncates a filename and Xcode truncates with a tooltip;
   text that must be read in full is short by construction or lives on
   `.help`. A gate that cannot see text cannot hold a rule about text.

The contract covers every surface — the window, its sheets, panels and
alerts — not only the columns. Deviations are recorded in `open-items.md`
with the reason. The rework that adopts it is the only UI target until it
is complete (`status.md`).

## The UI contract (owner decision, 2026-09-04)

`UI/` was rebuilt from scratch in SwiftUI in 2026-09-04's migration; the
AppKit-hosted window it replaced was deleted the same day, so there is one UI
again and no flag selects it. It is the presentation contract above with
AppKit removed and the shape re-cut, and it is the surface that ports to iOS.
Six rules, the first three enforced by `run-tests.sh inventory`:

1. **SwiftUI only.** No `NSSplitViewController`, no hosted AppKit shell, no
   `NSEvent` monitors, no `NSCursor`, no AppKit layout, no `import AppKit`.
   The one permitted platform bridge is `UI2MetalImage`, which is written
   with a shared body and a two-line per-OS conformance.
2. **No AppKit shell.** `HSplitView`, `VSplitView`, `NSSplitView` and
   `NSSplitViewController` are banned outright — `HSplitView` was half of a
   launch crash (`open-items.md`) and is macOS-only besides. `inventory`
   greps for all four and for `import AppKit`.
3. **`UI2Metrics` is the whole number budget.** Every column range, science
   floor, field width, thumbnail ceiling and sheet size is there and nowhere
   else. Outside it, a `.frame` is permitted only as scientific drawing
   geometry — the panes, overlays, scale bars, colorbars, histograms and
   legends, whose sizes are the image's, not the layout's.
4. **No pane focus model.** `WorkspaceNavigation.focusedPane` and
   `.inspectorContent` are retired for UI2. Where the old UI switched its
   controls on which pane was "active", UI2 offers an explicit control;
   `AppState.activePane` survives only as the ROI direction's storage.
5. **No new state on `AppState`.** UI2's selection is derived from
   `WorkspaceNavigation`, never stored beside it (`UI2Route`).
6. **The window is three columns with one job each.** Left is navigation and
   nothing else. Centre is the science, with the status strip and the output
   log on its bottom edge. Right is the inspector in two tabs — **Settings**,
   every control the selected workspace owns, and **Info**, what the dataset
   and the displayed product are. There is no workspace header: the window
   title carries the task and the toolbar carries the one action that runs
   it. Readiness has exactly one home, the Settings tab's first section.

Type names still carry a `UI2` prefix from the migration. It is a name, not a
namespace: dropping it would turn `UI2Metrics` into `Metrics` and `UI2Route`
into `Route`, which are too generic to grep, so it stays until there is a
better reason than tidiness.

## Requirements, build, test

- macOS 14+; Xcode 16 / Xcode 26 (synchronized folders, Metal toolchain).
  No separately installed HDF5.
- Build: open `mac4DSTEM.xcodeproj`, scheme `mac4DSTEM`, `⌘R`; or
  `xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build`.
  Tools resolve their own toolchain via `tools/lib/developer-dir.sh`
  (`DEVELOPER_DIR` wins; the Command Line Tools directory is rejected).
- Test: `tools/run-tests.sh unit | scientific | all | benchmark | inventory`.
  The `scientific` array in that script is the harness roster; no count is
  stated anywhere else. On-screen verification is the owner driving the app
  and reporting through `/diagnose` (the checklist was retired 2026-09-03).
- Never add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch.

## HDF5 notes

`H5Reader` and the session writer `dlopen` `libhdf5.dylib` and bind every
symbol via `dlsym`, searching `MAC4DSTEM_HDF5_PATH` (harnesses), the bundle's
`Contents/Frameworks/`, then dyld's bare-name lookup. The target embeds and
signs `libhdf5`, `libsz.2`, `libaec.0`; App Sandbox with user-selected
read/write and app-scoped bookmarks. Release enables Hardened Runtime; local
Debug builds leave it off so macOS accepts the separately signed closure.
Distribution always uses hardened Release (`releasing.md`).

## Known limitations

- Tiles are expanded to float32; native-dtype kernels would cut bandwidth.
  The app always streams; the resident path is reachable only from harnesses.
- Metal commands cannot be interrupted after submission: Cancel discards the
  cancelled run's result immediately while the in-flight command finishes.
  A streaming pass waits out at most one tile; the read, not the check, is
  where the noticeable moment lives.
- Session rehydration is pixel and metadata level; transient arrays are not
  reconstructed.
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
  `UI/UI2ContentView.swift`. See "The UI contract" below.
- Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
  blocking compute types are `nonisolated` and run via `Task.detached`;
  readers are actors; long analyses guard publication with dataset epoch and
  operation token. Never conscript the main thread with `concurrentPerform`
  (the frozen-Detect-All-Disks lesson).
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the
  `.metal` structs (all 4-byte fields).
- Debug builds compile the app module at `-O` so interactive science is never
  benchmarked at `-Onone`.
