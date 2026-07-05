# mac4DSTEM

A native **macOS Swift / SwiftUI / Metal** application for analyzing **4D-STEM** datasets.

The goal is feature parity with [py4DSTEM](https://github.com/py4dstem/py4DSTEM) — reused here as the reference implementation — rebuilt on Apple-Silicon-native compute (Metal, and later MLX) for interactive, real-time analysis on lab Macs, with additional features over time.

Algorithms are ported from py4DSTEM and validated against it; deviations are documented inline in the source with a `DEVIATION` note and the reason.

---

## Current state

The app is being built by **migrating features in small, buildable slices** from `References/MigrationSource/` (read-only reference code). Each slice ends green (`⌘B`) and is verified before the next begins.

### Working now

**Data & display (Slice 1)**
- Open HDF5 (`.h5` / `.hdf5` / `.emd`) 4D-STEM files. The datacube is auto-discovered across common py4DSTEM / Gatan (`dm_dataset_root`) / HyperSpy path layouts; a manual dataset-path override is available.
- HDF5 is loaded at runtime via `dlopen`/`dlsym` (no link-time dependency) — see [HDF5 notes](#hdf5).
- Live CBED (diffraction) viewer, GPU-rendered through a Metal display pipeline with colormap LUTs (Viridis / Inferno / Gray / RdBu) and optional log scaling.
- Scan-position scrubbing (X/Y sliders), dataset inspector with shape/dtype/chunking/voltage metadata.

**Virtual detector imaging (Slice 2)**
- Whole-cube virtual-detector imaging on the GPU: bright-field / ADF / HAADF presets plus a draggable annular aperture (analytic fast path) and rectangle / point detectors (general mask kernel).
- Two-pane layout: diffraction on the left, real-space virtual image on the right. Click the real-space image to select a scan position; the diffraction pane follows.

**Calibration (Slice 3)**
- **Origin calibration** (py4DSTEM `get_probe_size` → `get_origin` → `fit_origin`): estimates the probe radius from the max diffraction pattern, measures the unscattered-beam position per scan point on the GPU, and fits a smooth origin map (constant / plane / parabola). Reports probe radius and fit RMS residual.
- **R–Q rotation calibration**: solves for the scan↔detector rotation (and detector transpose) by minimizing the curl of the center-of-mass field. Runs origin calibration first if needed.
- **Diffraction statistics**: max and mean patterns over the whole cube, selectable as CBED display modes.

**DPC / iDPC (Slice 4)**
- Center-of-mass differential phase contrast with four views off one cached CoM field: **magnitude**, **angle**, an **HSV color wheel** (hue = deflection direction, brightness = magnitude, with an on-image legend), and **iDPC** via Fourier integration of the vector field. The calibrated R–Q rotation is applied so the field is in the scan frame.

**Bragg disk detection (Slice 5)**
- Synthetic probe-kernel generation (logistic disk minus a sine² sigmoid trench, zero-sum), hybrid cross-correlation (`corrPower`), maxima finding with the intensity/spacing/edge/count filter cascade, and sub-pixel refinement (parabolic or DFT-upsampled `multicorr`). Live per-pattern overlay while scrubbing, plus a full-scan pass (parallelized over scan rows) producing a Bragg vector map.

**Strain mapping**
- Strain from the detected Bragg vectors (py4DSTEM `process/strain`): auto-picks two reference lattice vectors, indexes each pattern's peaks to integer (h, k), fits the local lattice by intensity-weighted least squares, and computes the infinitesimal strain tensor (**εxx, εyy, εxy**) and **rotation θ** relative to the scan-mean lattice. Displayed per component on a diverging colormap. (User-selected reference region and manual g1/g2 refinement are planned.)

**ACOM — crystal orientation mapping**
- A `Crystal` model (lattice/metric + kinematic structure factors, Lobato scattering factors) with FCC/BCC/diamond presets and named materials, verified against known selection rules.
- Orientation matching via a simplified **polar-correlation** route (the same principle as py4DSTEM's `crystal_ACOM`, without the spherical-harmonic machinery): sample zone axes, project each crystal's excited reflections to a polar (radial × azimuthal) template, and match each pattern's Bragg peaks against the library — recovering the zone axis and in-plane angle in one shot via azimuthal FFT correlation, with an EBSD-style reliability. Result maps: reliability, in-plane angle, score.
- *Limitations (v1):* needs a Q-pixel-size scale to map detector pixels → Å⁻¹ (exposed as a slider; qualitative without it); high-symmetry zone axes are ambiguous (no fundamental-zone sampling yet — flagged by low reliability); no IPF orientation coloring yet.

### Project structure

```text
mac4DSTEM/                       # Xcode project root (git repo)
  mac4DSTEM/                     # app sources (file-system-synchronized — see below)
    App/                         # entry point + AppState (single source of truth)
    Core/
      Data/                      # H5Reader, FourDArray, DatasetDescriptor,
                                 #   DiffractionPattern, Calibration
      Compute/                   # MetalEngine, MTLTexture+Float
      Analysis/                  # VirtualDetector, OriginCalibration,
                                 #   RotationCalibration, OrientationResult
    Shaders/                     # .metal kernels (display, virtual detector,
                                 #   DP statistics, origin measure, center of mass)
    UI/                          # ContentView, Diffraction/StemImageView,
                                 #   MetalImageView, ApertureControl, Colormaps, …
    Support/                     # bridging header
  References/                    # read-only, git-ignored
    MigrationSource/             # prior codebase; port features FROM here
    py4DSTEM-dev/                # algorithm reference
    training_dataset/            # sample .h5 files
  libhdf5.dylib, libaec.0.dylib, libsz.2.dylib   # vendored HDF5 (for bundling)
```

The Xcode project uses **synchronized folder groups** (`objectVersion 90`): files placed under `mac4DSTEM/` are added to the target automatically — no manual "target membership" step, and `.metal` files auto-route to the Metal compile phase.

---

## Requirements

- macOS with **Xcode 16 / Xcode 26** (the project uses synchronized folders and the Metal toolchain component).
- **Homebrew HDF5** for development builds: `brew install hdf5` (see [HDF5 notes](#hdf5)).

## Build & run

1. Open `mac4DSTEM.xcodeproj` in Xcode.
2. Select the `mac4DSTEM` scheme.
3. Build and run (`⌘R`). Open a `.h5` dataset (e.g. from `References/training_dataset/`).

**Command-line builds** (optional) require pointing at the full Xcode toolchain, since `xcode-select` may target CommandLineTools:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

---

## <a name="hdf5"></a>HDF5 notes

`H5Reader` has **no link-time HDF5 dependency**. It `dlopen`s `libhdf5.dylib` at launch and binds every function via `dlsym`. It searches, in order:

1. the app bundle's `Contents/Frameworks/` (for a self-contained release build), then
2. Homebrew / system locations (`/opt/homebrew/opt/hdf5/lib`, `/usr/local/...`) for development.

**App Sandbox is currently disabled** so the Homebrew fallback can load. Bundling the vendored dylibs into `Contents/Frameworks`, re-enabling the sandbox, and notarizing are grouped into a later **distribution milestone** — at which point the bundled path (tried first) takes over automatically with no code change. The vendored dylibs at the repo root are already prepared for this (`libhdf5` resolves `libsz`/`libaec` via `@loader_path`).

---

## Roadmap

Migration slices, in order:

1. ✅ **Metal display** — file I/O, CBED rendering, scan scrubbing.
2. ✅ **Virtual detector** — BF/ADF/HAADF, draggable aperture, real-space pane.
3. ✅ **Calibration** — origin + R–Q rotation, DP max/mean.
4. ✅ **DPC / iDPC** — center-of-mass magnitude/angle, HSV color-wheel vector display, Fourier iDPC integration.
5. ✅ **Disk detection** — synthetic probe kernel, hybrid cross-correlation, sub-pixel Bragg-disk detection (parabolic + `multicorr`), Bragg vector maps.

**The five migration slices plus strain mapping are complete** — the py4DSTEM core-analysis path (I/O → virtual imaging → calibration → DPC → disk detection → strain) is in place.

Still ahead (each its own focused effort):

- **ACOM refinements** — fundamental-zone (symmetry-reduced) zone-axis sampling to resolve high-symmetry ambiguity, IPF-colored orientation maps, automatic Q-calibration, and measured-probe templates. (The core crystal model + orientation matching is in place.)
- **Parallax / ptychography** — iterative phase reconstruction, where **MLX** is introduced for GPU-batched FFTs and solvers. Multi-session.
- **Broader readers** (DM4/MIB/EMPAD), EMD-compatible export.
- **Distribution milestone** — HDF5 bundling + App Sandbox + notarization.
- An **open-issues pass** and a dedicated **UI/UX refinement** cycle.

---

## Open issues / known limitations

- **Whole-cube analyses require the cube to fit in the GPU working-set budget.** Virtual detector, calibration, and DPC stream the full cube into one MTLBuffer; datasets beyond ~half the GPU budget throw a friendly "try a smaller crop" error. Out-of-core tiling is planned.
- **Cube is expanded to float32** on load (HDF5 converts on read). Native-dtype (uint8/16) residency with in-kernel conversion is a planned memory optimization.
- **HDF5 not yet bundled**; App Sandbox is off for development (see above).
- **R–Q rotation has an inherent 180° ambiguity** (the curl/divergence metric is unchanged by flipping both CoM components). If iDPC contrast comes out inverted, the true rotation is θ + 180°; a manual override is a planned convenience.
- **Origin coarse search deviates from py4DSTEM** (binned block-sum argmax instead of a Gaussian-blur argmax) for GPU efficiency; the windowed center-of-mass refinement that dominates the sub-pixel result is identical.
- **No automated test suite yet.** Ports are validated by (a) numeric checks of the algorithms against known inputs during development, and (b) matching the py4DSTEM reference; a golden-value harness against py4DSTEM outputs is a candidate for later.
- Bundle identifier is still a development placeholder.

### UI / UX (polish cycle in progress)

Done: toolbar mode switcher (all modes reachable), independently hideable tools + inspector panels, live-drag detector → real-space and real-space marker → diffraction, shape-correct + grid-snapped detector overlays, centered pattern-mode picker, higher-contrast position marker.

Still open:

- **Virtual diffraction** — a grid-snapped region tool on the real-space image that sums the selected positions' patterns into the CBED pane (reciprocal of virtual imaging), plus **active-pane** focus that scopes the tools panel to the clicked pane. In progress.
- **Per-view histogram + draggable contrast** (min/max/gamma), shown in the inspector panel.
- **Scale bars and colorbars with units** (nm real-space, Å⁻¹ / mrad diffraction) — needs the pixel-size calibration.
- **Preprocessing / import** — no `.dm4` (or other raw TEM formats) support yet. A future import pipeline reads a raw `.dm4` from the microscope and writes a working `.h5`, with an **automatic calibration** step (origin, rotation, pixel sizes) and a **manual** override path when wanted — mirroring py4DSTEM's calibrate-and-export flow (kept separate from the main analysis UI). The DM4 binary format is fully specced and verified in [`docs/dm4-format.md`](docs/dm4-format.md), ready to implement.
- **Results persistence + file tree** — save calibration, Bragg vectors, and result maps/plots into a companion sidecar `.h5` next to the original (never modifying the source), with load-on-reopen. The inspector's **bottom-right file tree** shows where things are stored (virtual images, disk detection, calibrations) so it's clear what's already been computed.
- **Performance panel** (inspector, above the file tree) — live view of active processes, memory occupied, iterations/second, and a progress bar highlighting the running operation.
- **Per-view histogram** with draggable contrast (min/max/gamma) for the real-space image, styled, in the inspector panel. The histogram exists; still to add is a **range slider on it that clips which intensities map into the image** (and it must interoperate cleanly with the log-count toggle).
- **DP mean / max** views regressed out of easy reach — they should live in the tools panel when the diffraction (CBED) pane is the active (blue) pane, alongside the detector controls.
- **macOS menu bar** — File / Edit / View / Window menus are still defaults; to be populated with commands + shortcuts.

---

## Developer notes

- **One `@main`** app type in `App/mac4DSTEMApp.swift`; root UI in `UI/ContentView.swift`.
- **State**: `AppState` is the observable single source of truth (`@Observable`). Views describe UI only; loading/parsing/compute live in `Core`.
- **Concurrency**: the project builds in Swift 5 language mode with *approachable concurrency* and **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**, so types are MainActor-isolated by default. Compute types that run blocking GPU work off the main thread are marked **`nonisolated`** (e.g. `MetalEngine`, and the `VirtualDetector` / `OriginCalibration` / `RotationCalibration` entry points), and `AppState` invokes them via `Task.detached`.
- **Metal parameter structs** in `MetalEngine.swift` must stay byte-for-byte identical to the `struct`s in the matching `.metal` files (all 4-byte fields).
- Treat `References/` as read-only. Bring code over in small batches, convert `@EnvironmentObject`/`@Published` to the Observation framework, and build after each batch. Do not copy old project scaffolding (`.xcodeproj`, `Package.swift`, build folders) into this project.
