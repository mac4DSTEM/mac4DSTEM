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
- Open Gatan DM3/DM4 datacubes directly, including dimension and pixel-size metadata where present.
- HDF5 is loaded at runtime via `dlopen`/`dlsym` (no link-time dependency) — see [HDF5 notes](#hdf5).
- Live CBED (diffraction) viewer, GPU-rendered through a Metal display pipeline with colormap LUTs (Viridis / Inferno / Gray / RdBu) and optional log scaling.
- Scan-position scrubbing (X/Y sliders), dataset inspector with shape/dtype/chunking/voltage metadata.

**Virtual detector imaging (Slice 2)**
- Whole-cube virtual-detector imaging on the GPU: bright-field / ADF / HAADF presets plus a draggable annular aperture (analytic fast path) and rectangle / point detectors (general mask kernel).
- Two-pane layout: diffraction on the left, real-space virtual image on the right. Click the real-space image to select a scan position; the diffraction pane follows.

**Calibration (Slice 3)**
- **Origin calibration** (py4DSTEM `get_probe_size` → `get_origin` → `fit_origin`): estimates the probe radius from the max diffraction pattern, measures the unscattered-beam position per scan point on the GPU, and fits a smooth origin map (constant / plane / parabola). Reports probe radius and fit RMS residual.
- The Calibration panel shows whether the aperture center is a geometric default, a py4DSTEM file-provided mean, a fit performed in the app, or a manual override.
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

**Current focus:** continue numeric parity with py4DSTEM one workflow at a time. Virtual-detector imaging is now covered by a source-locked Metal parity harness; per-position origin-map import is next.

Still ahead (each its own focused effort):

- **ACOM refinements** — fundamental-zone (symmetry-reduced) zone-axis sampling to resolve high-symmetry ambiguity, IPF-colored orientation maps, automatic Q-calibration, and measured-probe templates. (The core crystal model + orientation matching is in place.)
- **Parallax / ptychography** — iterative phase reconstruction, where **MLX** is introduced for GPU-batched FFTs and solvers. Multi-session.
- **Broader readers** (MIB/EMPAD) and EMD-compatible export; DM3/DM4 direct reading is already implemented.
- **Distribution milestone** — HDF5 bundling + App Sandbox + notarization.
- An **open-issues pass** and a dedicated **UI/UX refinement** cycle.

---

## Direction notes (2026-07-06 evaluation)

- **.h5 calibration**: the py4DSTEM EMD files carry a full calibration bundle
  (`<root>/metadatabundle/calibration/{Q,R}_pixel_size` + units, `QR_flip`) and
  EMD `dim0–dim3` vectors — now read automatically (see Fixed list).
- **DM4 self-calibration (future)**: when a raw `.dm4` is opened, the app should
  be able to produce this calibration itself — origin + rotation + pixel sizes
  written as a py4DSTEM-style calibration bundle into the exported `.h5`
  (mirrors the current external preprocessing flow). Q-calibration from a known
  crystal (fit Bragg radius of a known lattice spacing) is the missing piece.
- **Large datasets, decided approach** (ladder): ① real-space crop at load,
  ② detector (Q) binning at load = binned preview, ③ native-dtype residency,
  ④ out-of-core tiled streaming for whole-cube passes, ⑤ streamed
  preprocess/export to a new calibrated `.h5` (pending), ⑥ true sparse
  (electron-counted) formats only when such data exists.
- **Speed vs py4DSTEM+CUDA (assessment)**: whole-cube ops are memory-bandwidth
  bound — we beat py4DSTEM-CPU by orders of magnitude, are competitive with
  mid-range CUDA, won't out-bandwidth a 4090; our win is end-to-end interactive
  latency (no Python, no PCIe copies). Disk detection is the exception (CPU
  FFTs) — moving correlation to the GPU is the big remaining lever.
- **Feature-revision plan**: DPC in physical units (mrad, needs voltage + Q cal);
  measured vacuum probe from ROI; strain reference region + manual g1/g2 +
  robust basis; ACOM symmetry reduction, Euler angles, IPF; colorbars;
  results persistence to a sidecar `.h5` (py4DSTEM round-trip).

## Open issues / known limitations

- **Whole-cube analyses require the cube to fit in the GPU working-set budget.** Virtual detector, calibration, and DPC stream the full cube into one MTLBuffer; datasets beyond ~half the GPU budget throw a friendly "try a smaller crop" error. Out-of-core tiling is planned.
- **Cube is expanded to float32.** Rows now stream directly into a page-aligned allocation handed to Metal via `bytesNoCopy` (the former duplicate-copy peak is gone), but native-dtype residency (e.g. uint16) would still halve memory for integer data.
- **No Xcode test target yet.** Standalone harnesses cover calibration import and virtual-detector parity, but the remaining scientific workflows still need golden-value comparisons against py4DSTEM.
- **`AppState` is a large workflow coordinator.** It currently owns UI state, file I/O orchestration, calibration, analysis dispatch, result state, and progress reporting; this is becoming a maintainability and coupling risk.
- **Long-running analyses are not cancellable.** They now carry a dataset-generation epoch, so results from a previously-open file are dropped instead of landing in the new file's state — but a running pass still cannot be stopped mid-flight.
- **Calibration metadata propagation is partial.** DM4 pixel sizes/units now populate `Calibration` (scale bars + ACOM scale use them; manual entry covers HDF5), but colorbars and persistence of calibration are still missing.
- **ACOM orientation output is incomplete.** The matcher currently reports the best template and in-plane angle but returns zero Euler angles; full crystallographic orientation maps are not yet available.
- **Virtual diffraction is an all-scan-position reduction.** Each detector pixel loops over every scan position in the selected mask, so live selected-area diffraction can become expensive for large scans and detectors.
- **Strain mapping uses the scan-mean lattice as the reference.** There is no user-selected unstrained region yet, so global strain or gradients can be normalized away.
- **Strain basis selection is automatic and fragile.** The shortest non-collinear peak pair is chosen globally; false positives or mixed phases can poison indexing across the map.
- **Origin coarse search deviates from py4DSTEM.** It uses a binned block-sum argmax instead of Gaussian-blur argmax for GPU efficiency; the fallback path can produce a usable-looking calibration even when py4DSTEM would signal failure.
- **iDPC currently assumes unit scan pixels and uses power-of-two padding.** Physical scaling and edge artifacts need more explicit handling for quantitative interpretation.
- **No graceful non-Metal fallback.** `MetalEngine` uses fatal initialization failures if no Metal device, command queue, or default library is available.
- **HDF5 discovery is path-list based.** Valid datasets outside the known py4DSTEM/Gatan/HyperSpy layouts need manual path entry.
- **HDF5 not yet bundled.** App Sandbox is off for development (see above).
- **R-Q rotation has an inherent 180° ambiguity.** The curl/divergence metric is unchanged by flipping both CoM components. If iDPC contrast comes out inverted, use the **Flip 180°** button in the Calibration section.
- Bundle identifier is still a development placeholder.

### Fixed / completed

- Virtual-detector parity harness (`tools/virtual-detector-test/run.sh`) exercises the production mask builder and Metal kernels on a non-square synthetic cube. Annulus, circle, rectangle, point, edge and exact-boundary cases match source-locked py4DSTEM results with zero error. This exposed and fixed the annulus inner boundary (`rIn² < r² < rOut²`, both strict); BF now uses a true circle so it retains the center pixel.
- Origin provenance is explicit and visible: geometric default, file-provided `qx0_mean`/`qy0_mean`, fitted in-app, or manually moved aperture center. BF/ADF/HAADF presets change radii without discarding that center.
- DM4 `ByteReader` is now bounds-checked end-to-end — malformed/truncated files throw `truncated` instead of crashing; tag counts are sanity-capped.
- Rank-3 HDF5 datasets now read correctly (hyperslab selection matches the file's real rank).
- Stale-result guard: analyses capture a dataset epoch and drop results if a different dataset was activated mid-run.
- `DiskDetection.detectAll` `failed`-flag data race fixed; disk detection and ACOM matching now use one worker-pooled detector/matcher per core (strided rows) instead of one per scan row.
- Display normalization ignores NaN/Inf (finite min/max; non-finite pixels map to the low end).
- Rotation calibration (and the 180° flip) immediately refresh a displayed DPC/iDPC result; the full objective curves are now plotted in the inspector ("Rotation diagnostics").
- Cube upload no longer double-allocates (`bytesNoCopy` into a page-aligned buffer).
- Normalized display pixels are cached per version counter instead of being recomputed on every SwiftUI render.
- Scattering factors now cover all 103 elements (generated from py4DSTEM's Lobato table); unknown elements fail loudly. ACOM offers a **Custom** cubic crystal (element × FCC/BCC/SC/diamond × lattice constant). Materials Project lookup is a future step.
- Export: result image / diffraction pattern as PNG (rendered as displayed), Bragg peaks as CSV (File section).
- DP mean/max picker lives in the tools panel when the CBED pane is active, with a standalone "Compute Mean / Max" pass (no origin calibration required).
- Histogram gained a draggable contrast window (applied in the fragment shader; independent of the log-counts toggle).
- Output log strip below the image panes (toggleable) shows timestamped operation history.
- Arrow keys step the scan position (Shift = 10 px).
- Histogram range slider rewritten: the whole histogram takes the drag and moves the nearest handle (the old per-handle hit areas clipped at the row edge, so the hi handle was ungrabbable).
- Split-view squeeze limits: sidebar capped at 300 pt, detail area has a 480 pt floor, window min width 1080 — panes can no longer be crushed into distorted slivers.
- PNG exports now burn the scale bar into the image (bottom-left, same 1-2-5 quantization and units as on screen); small maps are integer-upscaled (nearest neighbor) to ≥512 px so the label stays legible without altering data pixels.
- **Zoom + calibrated scale bars.** Both panes zoom (pinch; diffraction also pans by dragging the background; double-click resets). Image and overlays share one transformed container so the aperture, peaks, crosshair, and ROI stay pixel-accurate at any zoom (this also fixed the pre-existing overlay misalignment when the real-space view was zoomed). Each pane shows a 1-2-5 scale bar that re-quantizes with zoom — calibrated (nm / 1/nm) when pixel sizes are known, px otherwise. DM4 pixel sizes + units now flow into `Calibration` automatically (and auto-fill the ACOM Å⁻¹/px scale when units are convertible); manual pixel-size fields in the Calibration section cover plain HDF5.

### UI / UX (polish cycle in progress)

Done: toolbar mode switcher (all modes reachable), independently hideable tools + inspector panels, live-drag detector → real-space and real-space marker → diffraction, shape-correct + grid-snapped detector overlays, centered pattern-mode picker, higher-contrast position marker.

Still open:

- **Virtual diffraction** — a grid-snapped region tool on the real-space image that sums the selected positions' patterns into the CBED pane (reciprocal of virtual imaging), plus **active-pane** focus that scopes the tools panel to the clicked pane. In progress.
- **Per-view histogram draggable contrast**: min/max range slider is done (real-space view); gamma and a CBED-side window are still open.
- ~~Scale bars with units~~ — done (zoom-aware 1-2-5 bars, px fallback). **Colorbars** (numeric color ↔ value legend) still open; mrad diffraction units (needs voltage) still open.
- **Preprocessing / import** — direct DM3/DM4 reading is implemented. Still missing is a preprocessing workflow that reads raw microscope data, performs **automatic calibration** (with manual overrides), and writes a canonical calibrated `.h5`, mirroring py4DSTEM's calibrate-and-export flow. The verified format notes live in [`docs/dm4-format.md`](docs/dm4-format.md).
- **Results persistence + file tree** — save calibration, Bragg vectors, and result maps/plots into a companion sidecar `.h5` next to the original (never modifying the source), with load-on-reopen. The inspector's **bottom-right file tree** shows where things are stored (virtual images, disk detection, calibrations) so it's clear what's already been computed.
- **Performance panel** (inspector, above the file tree) — live view of active processes, memory occupied, iterations/second, and a progress bar highlighting the running operation.
- ~~Histogram range slider~~ and ~~DP mean/max in the tools panel~~ — done (see Fixed list below).
- **macOS menu bar** — File / Edit / View / Window menus are still defaults; to be populated with commands + shortcuts.

---

## Developer notes

- **One `@main`** app type in `App/mac4DSTEMApp.swift`; root UI in `UI/ContentView.swift`.
- **State**: `AppState` is the observable single source of truth (`@Observable`). Views describe UI only; loading/parsing/compute live in `Core`.
- **Concurrency**: the project builds in Swift 5 language mode with *approachable concurrency* and **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**, so types are MainActor-isolated by default. Compute types that run blocking GPU work off the main thread are marked **`nonisolated`** (e.g. `MetalEngine`, and the `VirtualDetector` / `OriginCalibration` / `RotationCalibration` entry points), and `AppState` invokes them via `Task.detached`.
- **Metal parameter structs** in `MetalEngine.swift` must stay byte-for-byte identical to the `struct`s in the matching `.metal` files (all 4-byte fields).
- Treat `References/` as read-only. Bring code over in small batches, convert `@EnvironmentObject`/`@Published` to the Observation framework, and build after each batch. Do not copy old project scaffolding (`.xcodeproj`, `Package.swift`, build folders) into this project.
