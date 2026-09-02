# Architecture

What the app is made of, how the layers depend on each other, where a new
file goes, and where the consolidation is taking the ownership model. Product
scope is `README.md` and `CHANGELOG.md`; live status is `status.md`; the
sequence of the consolidation is `v2.5-plan.md`.

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
| Vendored material and machine-local data | `References/` (gitignored except the py4DSTEM source lock) |

`References/` is tiered, not bloat: tiny tracked fixtures for every gate;
locally staged representative datasets; multi-GB acceptance data on the
owner's machines; the pinned py4DSTEM source that `DEVIATION` notes cite.

## Ownership today and where it is going

Today `AppState` (`App/AppState.swift`) owns loading, session state, calibration,
every analysis's parameters and dispatch, product publication, replay and
recovery; `ContentView` reconstructs workflow rules from it. Extracted seams
already exist (`DatasetResidency`, `SessionGates`, `WorkspaceNavigation`,
`StrainProduct`, `ReplayRun`, `QCalibrationRun`, `SessionCalibrationFramePolicy`).

The target (`v2.5-plan.md` §4): three local packages — `DSTEMCore` (Data,
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

## Requirements, build, test

- macOS 14+; Xcode 16 / Xcode 26 (synchronized folders, Metal toolchain).
  No separately installed HDF5.
- Build: open `mac4DSTEM.xcodeproj`, scheme `mac4DSTEM`, `⌘R`; or
  `xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build`.
  Tools resolve their own toolchain via `tools/lib/developer-dir.sh`
  (`DEVELOPER_DIR` wins; the Command Line Tools directory is rejected).
- Test: `tools/run-tests.sh unit | scientific | all | benchmark | inventory`.
  The `scientific` array in that script is the harness roster; no count is
  stated anywhere else. Track B is a person driving
  `visual-acceptance-checklist.md`.
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

- One `@main` in `App/mac4DSTEMApp.swift`; root UI in `UI/ContentView.swift`.
- Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
  blocking compute types are `nonisolated` and run via `Task.detached`;
  readers are actors; long analyses guard publication with dataset epoch and
  operation token. Never conscript the main thread with `concurrentPerform`
  (the frozen-Detect-All-Disks lesson).
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the
  `.metal` structs (all 4-byte fields).
- Debug builds compile the app module at `-O` so interactive science is never
  benchmarked at `-Onone`.
