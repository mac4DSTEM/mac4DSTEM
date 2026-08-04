# mac4DSTEM

A native **macOS Swift / SwiftUI / Metal** application for interactive analysis of
**4D-STEM** datasets on Apple Silicon.

The goal is feature parity with [py4DSTEM](https://github.com/py4dstem/py4DSTEM) —
reused here as the reference implementation — rebuilt on Apple-native compute for
real-time analysis on lab Macs. Algorithms are ported from py4DSTEM and validated
against it; deviations are documented inline in the source with a `DEVIATION` note
and the reason.

- The frozen v1 workflow, feature tiers, and acceptance gates: [`docs/v1-scope.md`](docs/v1-scope.md)
- Current priorities and scope rules: [`ROADMAP.md`](ROADMAP.md)
- Canonical py4DSTEM analysis pipelines + UI evaluation: [`docs/py4dstem-pipelines.md`](docs/py4dstem-pipelines.md)
- Ranked UI/workflow backlog: [`docs/ui-workflow-backlog.md`](docs/ui-workflow-backlog.md)
- Superseded point-in-time notes (reviews, dated evaluations): [`docs/archive/`](docs/archive/)
- Where historical checkpoint detail lives: [`docs/development-history.md`](docs/development-history.md) (short answer: Git history)

## Status

The frozen v1 workflow is implemented and the project is in **stabilization**:
scientific-contract corrections, task-focused UI consolidation, incremental
architecture extraction, and distribution readiness. The only aggregate
repository claim is a passing `tools/run-tests.sh all` (native XCTest suite,
24 standalone scientific/interoperability harnesses, the real-data manifest,
and the hardened Release packaging audit).

## What it does

**Workflow.** Five outcome-based workspaces — **Prepare**, **Image**, **Map**,
**Reconstruct**, **Results** — with `⌘1…⌘5` navigation. Navigation is
side-effect free; expensive whole-scan work starts only from an explicit
primary action. Progress and cancellation live in the workspace header;
prerequisite guidance links back to the calibration or detection step that is
actually missing.

**Data & display.** Opens HDF5 (`.h5`/`.hdf5`/`.emd` — py4DSTEM, Gatan,
HyperSpy, and arbitrary EMD layouts via link traversal), Gatan DM3/DM4
directly, plus Preview-tier EMPAD RAW/XML and Merlin MIB readers. HDF5 is
loaded at runtime via `dlopen` (no link-time dependency — see
[HDF5 notes](#hdf5)). GPU-rendered CBED viewer with colormap LUTs, log
scaling, per-view contrast/gamma, zoom, and calibrated 1-2-5 scale bars.
Whole-cube passes stream bounded scan-row tiles, so peak memory is independent
of scan size.

**Virtual imaging & diffraction.** BF/ADF/HAADF presets, a draggable annular
aperture (analytic fast path), rectangle/point detectors (general mask
kernel), and the reciprocal operation: point/rectangle/circle real-space ROIs
drive selected-area diffraction.

**Calibration.** Origin calibration (py4DSTEM `get_probe_size` → `get_origin`
→ `fit_origin`), R–Q rotation via CoM-field curl minimization (with explicit
180°-flip control), elliptical-distortion fitting (conic + 11-parameter
amorphous-ring model), and Q calibration against a known crystal. Every value
carries provenance — file import, session restore, measured in-app, manual, or
mixed — and task-specific readiness reporting replaces global gating.

**DPC / iDPC.** Four views off one cached CoM field: magnitude (px or mrad),
angle, HSV color wheel, and Fourier-integrated iDPC. iDPC is quantitative
projected phase (radians) only when origin maps, rotation, and both sampling
calibrations are present; otherwise it is explicitly qualitative.

**Bragg disk detection.** Port of `find_Bragg_disks`: synthetic or measured
probe kernel, hybrid cross-correlation, maxima cascade, and pixel / parabolic
/ DFT-upsampled `multicorr` subpixel refinement. Live per-pattern overlay with
an acceptance-funnel diagnostic; full-scan pass with staleness tracking so
changed settings can never silently misrepresent strain/ACOM inputs.

**Strain mapping.** py4DSTEM `process/strain` pipeline with a consensus-based
automatic basis (or manual g₁/g₂), robust local lattice fits, a
component-median reference (whole scan or unstrained ROI), and εxx/εyy/εxy/θ
maps whose unfittable positions render as explicit no-data, never as zero
strain.

**ACOM orientation mapping.** Polar-correlation template matching against a
validated `CrystalModel` catalog (FCC/BCC/diamond presets, HCP magnesium,
custom cubic, or your own structure via **Import CIF…**). Imported CIFs go
through the same `CrystalModel` validation as the built-in catalog and are
labelled *Imported* in the phase picker and in result provenance; cells
outside the cubic and hexagonal point groups are rejected, not coerced.
Preview/region/full-scan scopes with measured ETA, CPU/Metal
backends with parity gating, EBSD-style reliability, IPF-Z maps, and Bunge
Euler output. Physical matching requires calibrated Q sampling; anything else
is permanently labeled **Exploratory**. Phases without a validated model
(including WS₂) are rejected, never inferred.

**Parallax / ptychography (Advanced).** Staged workflow: calibrated virtual-BF
preprocessing → coarse-to-fine alignment → low/higher-order aberration fitting
→ CTF phase correction → KDE subpixel upsampling → depth sectioning, plus a
full-batch single-slice iterative ptychography engine (GD and DM/AP with
py4DSTEM constraint options). Every stage is memory-bounded, cancellable, and
source-locked against py4DSTEM.

**Results & interoperability.** A dedicated Results workspace with retained
result identity/units, comparison slots, and saved-product browsing. Exports:
PNG (as displayed, with burned-in scale bar), Bragg peaks CSV, native
py4DSTEM 0.14 / EMD 1.0 `BraggVectors` sidecar, calibrated (cropped/Q-binned)
`DataCube`, and a stable `<source>.mac4dstem.h5` session companion holding
named RealSlice/RGBA results, full calibration, and BraggVectors — all written
atomically, never touching the source file, and py4DSTEM-readable.

## Project structure

```text
mac4DSTEM/                       # Xcode project root (git repo)
  mac4DSTEM/                     # app sources (file-system-synchronized groups)
    App/                         # entry point, AppState (window-level coordinator),
                                 #   workflow + recovery
    Core/
      Data/                      # readers (H5/DM4/vendor), FourDArray, calibration,
                                 #   EMD session writer, product model
      Compute/                   # MetalEngine, FFTs, multicorr, cancellation
      Analysis/                  # virtual detector, calibration solvers, disks,
                                 #   strain, DPC, parallax, ptychography
      Crystal/                   # crystal models, scattering factors, ACOM matching
      Workflow/                  # AnalysisOperationController
    Shaders/                     # Metal kernels (display + compute)
    UI/                          # ContentView, viewers, controls, inspectors
    Support/                     # export, system monitor, bridging header
  mac4DSTEMTests/                # fast XCTest production/workflow contracts
  mac4DSTEMUITests/              # visible XCUITest QC playthrough (drives the
                                 #   real app through py4DSTEM pipelines);
                                 #   evaluation only, never modifies app logic
  tools/                         # scientific/interoperability harnesses,
                                 #   real-data acceptance, packaging audit,
                                 #   UI smoke + ui-qc-playthrough, aggregate runner
  docs/                          # design/scope/process docs (dated + superseded
                                 #   notes live in docs/archive/)
  References/                    # vendored external material + data (gitignored)
    py4DSTEM-dev/                # checked-in py4DSTEM 0.14.19 source lock
    py4DSTEM_tutorials-main/     # canonical tutorial notebooks (pipeline source)
    training_dataset/            # machine-local real-data corpus
    training_runs/               # QC playthrough outputs (screenshots, logs, PNGs)
  libhdf5.dylib, libaec.0.dylib, libsz.2.dylib   # bundled HDF5 closure
```

The Xcode project uses **synchronized folder groups**: files placed under
`mac4DSTEM/` join the target automatically, and `.metal` files auto-route to
the Metal compile phase.

## Requirements

- macOS 14+ with **Xcode 16 / Xcode 26** (synchronized folders + Metal toolchain).
- No separately installed HDF5 — the dependency closure is embedded.

## Build & run

1. Open `mac4DSTEM.xcodeproj`, select the `mac4DSTEM` scheme, build and run (`⌘R`).
2. Open a `.h5`, `.dm4`, or supported vendor dataset.

Command-line builds need the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -destination 'platform=macOS' build
```

Do not add `CODE_SIGNING_ALLOWED=NO` to an app build you intend to launch;
use `tools/run-tests.sh unit` for unsigned XCTest work (it builds into
disposable DerivedData and cannot disturb Xcode's normal Debug product).

## Testing

```sh
tools/run-tests.sh unit         # native XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific   # 24 standalone py4DSTEM-parity harnesses
tools/run-tests.sh all          # the aggregate repository gate
tools/run-tests.sh benchmark    # non-gating performance baseline (JSON)
```

The performance harness emits schema-v2 JSON (warm-up/repeat samples, medians,
checksums, memory); `tools/performance-baseline/compare.py` diffs two runs.
Wall-clock results are trend evidence, not CI pass thresholds.

## <a name="hdf5"></a>HDF5 notes

`H5Reader` and the session writer have **no link-time HDF5 dependency**. They
`dlopen` `libhdf5.dylib` and bind every symbol via `dlsym`, searching in order:

1. `MAC4DSTEM_HDF5_PATH` (standalone source harnesses only),
2. the app bundle's `Contents/Frameworks/`,
3. dyld's bare-name lookup (standalone harnesses).

The target embeds and signs all three dylibs and enables App Sandbox
(user-selected read/write + app-scoped bookmarks). Release enables Hardened
Runtime; local ad-hoc Debug builds leave it off so macOS does not reject the
separately signed HDF5 closure. Distribution must always use the hardened
Release configuration. `tools/package-test/run.sh` performs a clean Release
audit; Developer ID signing and notarization require release-owner credentials
(see [`docs/distribution.md`](docs/distribution.md) and
[`docs/releasing.md`](docs/releasing.md)).

## Known limitations

- **Tiles are expanded to float32.** Peak memory is bounded, but native-dtype
  tile kernels (e.g. uint16) would reduce reader bandwidth and staging memory.
- **`AppState` remains a large workflow facade.** Operation lifecycle is
  extracted (`AnalysisOperationController`); file I/O orchestration,
  calibration, analysis dispatch, and result publication still need
  incremental extraction as their campaigns touch them.
- **Metal commands cannot be interrupted after submission.** Cancel invalidates
  the result immediately; the in-flight GPU command finishes in the background.
  CPU loops stop cooperatively at row/template boundaries.
- **Session rehydration is pixel/metadata-level.** Saved maps, calibration, and
  BraggVectors restore; the app does not reconstruct every transient scientific
  array or create EMD plot nodes.
- **ACOM point-group coverage is deliberate, not generic.** Symmetry reduction
  and IPF coloring are implemented for the cubic and hexagonal point groups
  only. The CIF importer therefore accepts cubic and hexagonal cells and
  rejects everything else outright rather than coercing it onto `.cubic`,
  which would fabricate an IPF key and a fundamental-zone sampling that do not
  correspond to the crystal. An imported phase is user-supplied evidence, not
  a validated material: the built-in catalog is backed by ground-truth
  fixtures (ROADMAP P1.2), imported CIFs are not.
- **Virtual diffraction is an all-scan-position reduction** and can become
  expensive for large scans and detectors.
- **Origin coarse search deviates from py4DSTEM** (binned block-sum argmax
  instead of Gaussian-blur argmax, for GPU efficiency); the fallback can look
  usable where py4DSTEM would signal failure.
- **No graceful non-Metal fallback** — `MetalEngine` fails fatally without a
  Metal device.
- **R–Q rotation has an inherent 180° ambiguity** — use **Flip 180°** in
  Calibration if iDPC contrast is inverted.
- **MIB/EMPAD readers are Preview** until real vendor acquisitions are supplied.
- Bundle identifier is `com.paullobpreis.mac4DSTEM`; changing it after release
  would break bookmark/container continuity.

## Developer notes

- **One `@main`** app type in `App/mac4DSTEMApp.swift`; root UI in
  `UI/ContentView.swift`.
- **State:** `AppState` is the observable single source of truth
  (`@Observable`). Views describe UI only; loading/parsing/compute live in
  `Core`.
- **Concurrency:** Swift 5 language mode with approachable concurrency and
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types are MainActor-isolated
  by default. Blocking GPU/compute types are `nonisolated` and invoked via
  `Task.detached`; readers are actors; long analyses use dataset-epoch +
  operation-token guards before publishing.
- **Metal parameter structs** in `MetalEngine.swift` must stay byte-for-byte
  identical to the structs in the matching `.metal` files (all 4-byte fields).
- **Debug builds compile the app module at `-O`** (XCTest stays debuggable) so
  interactive science is never accidentally benchmarked at `-Onone`.
