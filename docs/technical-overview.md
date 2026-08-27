# Technical overview

The detailed engineering description of mac4DSTEM. This lived in `README.md`
until 2026-08-06, when the README was rewritten as a short public-facing
introduction; nothing was dropped, it moved here.

For scope and release contracts see [`v1-scope.md`](v1-scope.md) and
[`../CHANGELOG.md`](../CHANGELOG.md). For what is still live see
[`open-items.md`](open-items.md). Standing priorities and the scope rule are in
[`../ROADMAP.md`](../ROADMAP.md); where historical checkpoint detail lives is
answered in [`development-history.md`](development-history.md) (short answer:
Git history); superseded point-in-time notes are under
[`archive/`](archive/).

---

## What it does

**Workflow.** Five outcome-based workspaces — **Prepare**, **Image**, **Map**,
**Reconstruct**, **Results** — with `⌘1…⌘5` navigation. Navigation is
side-effect free; expensive whole-scan work starts only from an explicit
primary action. Progress and cancellation live in the workspace header;
prerequisite guidance links back to the calibration or detection step that is
actually missing.

**Data & display.** Opens HDF5 (`.h5`/`.hdf5`/`.emd` — py4DSTEM, Gatan,
HyperSpy, and arbitrary EMD layouts via link traversal), Gatan DM3/DM4
directly (tag layout and the parts of it the reader relies on:
[`dm4-format.md`](dm4-format.md)), plus Preview-tier EMPAD RAW/XML and Merlin
MIB readers. HDF5 is loaded at runtime via `dlopen` (no link-time dependency —
see [HDF5 notes](#hdf5-notes)). GPU-rendered CBED viewer with colormap LUTs, log
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
Preview/region/full-scan scopes with measured ETA, CPU/Metal backends with
parity gating, EBSD-style reliability, IPF-Z maps, and Bunge Euler output.
Physical matching requires calibrated Q sampling; anything else is permanently
labeled **Exploratory**. Phases without a validated model (including WS₂) are
rejected, never inferred.

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
  mac4DSTEMUITests/              # RETIRED 2026-08-17, unmaintained — was the
                                 #   visible XCUITest QC playthrough (drives the
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
    training_runs/               # QC playthrough outputs (logs and PNGs; no
                                 #   screenshot baseline exists yet)
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
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -destination 'platform=macOS' build
```

That uses whichever toolchain `xcode-select` points at. Everything under
`tools/` resolves its own via `tools/lib/developer-dir.sh`: an explicit
`DEVELOPER_DIR` wins, then the `xcode-select` choice, then any Xcode in
`/Applications`. The Command Line Tools directory is rejected — it ships no
`xcodebuild`, so accepting it would only defer the failure. Set
`DEVELOPER_DIR` explicitly to pin a specific Xcode.

Do not add `CODE_SIGNING_ALLOWED=NO` to an app build you intend to launch;
use `tools/run-tests.sh unit` for unsigned XCTest work (it builds into
disposable DerivedData and cannot disturb Xcode's normal Debug product).

## Testing

```sh
tools/run-tests.sh unit         # native XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific   # 28 standalone py4DSTEM-parity harnesses
tools/run-tests.sh all          # the aggregate repository gate
tools/run-tests.sh benchmark    # non-gating performance baseline (JSON)
```

The performance harness emits schema-v2 JSON (warm-up/repeat samples, medians,
checksums, memory); `tools/performance-baseline/compare.py` diffs two runs.
Wall-clock results are trend evidence, not CI pass thresholds.

## HDF5 notes

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
(see [`distribution.md`](distribution.md) and [`releasing.md`](releasing.md)).

## Known limitations

- **Tiles are expanded to float32.** Peak memory is bounded, but native-dtype
  tile kernels (e.g. uint16) would reduce reader bandwidth and staging memory.
  This is the only staging a *user* can experience, because **the app always
  streams**: no shipping control requests a resident cube
  (`App/DatasetResidency.swift:34`, and `request(_:on:)` has no caller under
  `mac4DSTEM/`). For completeness, the resident path no longer stages at all —
  the four tiled reducers bind the cube's own buffer at each tile's byte offset
  (v2 S18, 2026-08-27) where they previously copied buffer → `[Float]` → a fresh
  `MTLBuffer` per tile — but that path is reachable only from the harnesses.
- **`AppState` remains a large workflow facade.** Operation lifecycle is
  extracted (`AnalysisOperationController`); file I/O orchestration,
  calibration, analysis dispatch, and result publication still need
  incremental extraction as their campaigns touch them.
- **Metal commands cannot be interrupted after submission.** Cancel discards
  *the cancelled run's* result immediately — nothing partial is ever published —
  while the in-flight GPU command finishes in the background. CPU loops stop
  cooperatively at row/template boundaries. A **previously completed** result is
  deliberately kept rather than thrown away, and the status line names what was
  retained; if it no longer matches the settings in the panel, the viewer says
  so (backlog #34). Cancelling a long GPU pass can still take a noticeable
  moment (#37) — **and since 2026-08-27 that has a measured bound rather than an
  impression.** A streaming pass checks the token once per tile, so a cancel
  waits out at most one tile; a *resident* pass is a single whole-cube dispatch
  with checks either side, so a cancel waits out all of it — resident
  cancellation is structurally coarser, not better. **Only the streaming bound
  is reachable by a user**; the app never holds a resident cube (no shipping
  control requests one), so the resident figure describes the harnesses and any
  future admission control. On a 64×32×128×128 synthetic cube those bounds
  measured 5.4 ms per tile and 13.2 ms respectively
  (`tools/run-tests.sh benchmark`, M3). Both numbers are **dispatch-only**: the
  harness reads from memory, so the per-tile *read* — the half that dominates on
  a real file and especially over a network share — is not in them. That read is
  where the noticeable moment actually lives, which is why #37 now sits with the
  I/O work rather than with the cancellation checks.
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
- Bundle identifier is `com.mac4dstem.mac4DSTEM`. It was `com.paullobpreis.mac4DSTEM`
  through v1.0.0 and was changed before public distribution, which is the only
  point at which it is free: the identifier keys the sandbox container and the
  app-scoped security bookmarks inside it, so changing it after release would
  break bookmark/container continuity for every existing install.

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
