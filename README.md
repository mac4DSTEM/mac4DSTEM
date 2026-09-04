<h1 align="center">mac4DSTEM</h1>

<p align="center">
  <strong>Interactive 4D-STEM analysis, native to Apple Silicon.</strong>
</p>

<p align="center">
  <a href="https://github.com/mac4DSTEM/mac4DSTEM/actions/workflows/ci.yml"><img src="https://github.com/mac4DSTEM/mac4DSTEM/actions/workflows/ci.yml/badge.svg" alt="CI: unit, scientific, inventory and core gates on every push"></a>
</p>

<p align="center">
  <img src="docs/images/strain-map-workspace.png" alt="mac4DSTEM v1.0.0 Map workspace: diffraction fit overlay, strain map, and diagnostics" width="100%">
</p>

<p align="center"><sub>Captured from v1.0.0 (2026-08-06). The window was rebuilt in SwiftUI on 2026-09-04 and the workspaces renamed (Prepare / Imaging / Strain &amp; ACOM / Phase / Results); a current capture is owed.</sub></p>

---

## Overview

Four-dimensional scanning transmission electron microscopy records a complete convergent-beam electron diffraction pattern at every probe position. The resulting datasets are large, and the analysis that extracts science from them, including virtual imaging, strain, orientation, and phase reconstruction, has conventionally been performed offline in scripted environments, at a remove from the data.

mac4DSTEM brings that analysis into an interactive application. Detector geometry, calibration, and reconstruction parameters can be adjusted against a live view of the data, so the effect of a decision is visible as it is made rather than after a batch run completes.

The application is built directly on Apple Silicon's unified memory and GPU. Its algorithms are ported from [py4DSTEM](https://github.com/py4dstem/py4DSTEM) and validated against it, so results are traceable to the established reference implementation in the field. The gated harnesses compare against py4DSTEM on synthetic and analytic fixtures; parity on experimental acquisitions is `tools/training-dataset-campaign`, which needs multi-GB datasets that are not in the repository and is therefore not part of the public gate.

## Capabilities

- **Data exploration**: real and reciprocal space presented together, with calibrated scale bars, contrast control, and GPU-rendered CBED display.
- **Virtual imaging**: bright-field, annular dark-field, and HAADF geometries, plus arbitrary annular, rectangular, and point detectors positioned interactively on the diffraction plane.
- **Calibration**: probe and origin fitting across the scan, elliptical distortion correction, real-reciprocal rotation, and reciprocal-space sampling against a known crystal.
- **Bragg disk detection**: GPU cross-correlation with parabolic and DFT-upsampled subpixel refinement, and live acceptance diagnostics.
- **Strain mapping**: robust local lattice fitting against a whole-scan or region reference, with basis consensus, residual, and indexed fraction reported alongside every map.
- **Orientation mapping**: polar-correlation template matching against a validated crystal catalogue or an imported CIF, with reliability and inverse-pole-figure output.
- **Phase reconstruction**: DPC, iDPC, parallax, and single-slice ptychography.
- **Interoperability**: EMD export of Bragg vectors, calibrated datacubes, and preprocessed products, readable directly in py4DSTEM.

Every quantity carries its calibration and provenance through display, export, and reopening. Where a measurement is not quantitatively supported, the result is labelled accordingly rather than presented as though it were.

## Status

**v2.5.0** is the shipped release (2026-09-04). The analysis workflow is covered by gates anyone with the repository can reproduce, and each number below is quoted from the run that produced it rather than from an average:

- `tools/run-tests.sh unit` — **457 passed, 0 failed, 1 skipped**, exit 0, 2026-09-04.
- `tools/run-tests.sh all` — last run 2026-09-03: 43 harnesses green — py4DSTEM 0.14.19 parity against the pinned upstream source on synthetic and analytic fixtures, plus `real-data-acceptance` on experimental acquisitions against its own recorded baseline — and **exit 1** at `package-test`, whose literal version assertion the 2.5 bump turned red. The audit now derives the version from the project and passed on that same tree, but **the aggregate has not been re-run since**, so no aggregate exit 0 is claimed here.

The scientific set is 42 harnesses. The badge above covers four jobs on every push: the unit gate, the scientific gate, the repository's own `inventory` review, and `core`, which fails the moment `Core/` reaches upward into the app.

That verification is numerical: the application is tested against known-correct values, not against its rendered output. What it does **not** cover is what the app draws. That is checked by a person driving the app, which exists because the numerical gate has stayed green through real on-screen defects — most recently a status-bar readout that crashed the app on a real dataset while every gate stayed green. The scripted visual checklist that used to sit here was retired on 2026-09-03 and is archived at [`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`](docs/archive/v2/visual-acceptance-checklist-2026-09-03.md). The Merlin MIB and EMPAD RAW readers remain preview-grade pending further vendor data. Current limitations are documented in [`docs/open-items.md`](docs/open-items.md).

## Requirements

macOS 26 or later on Apple Silicon. No external runtime, toolchain, or library installation is required; all dependencies are contained within the application.

## Building from source

Open `mac4DSTEM.xcodeproj` in Xcode and build the `mac4DSTEM` scheme.

Architecture, test suites, supported file formats, and known limitations are documented in [`docs/architecture.md`](docs/architecture.md). What each release is: [`CHANGELOG.md`](CHANGELOG.md); what is live now: [`docs/status.md`](docs/status.md). The analysis pipelines and their correspondence to py4DSTEM are described in [`docs/py4dstem-pipelines.md`](docs/py4dstem-pipelines.md).

## Contributing

Issue reports, and especially parity discrepancies with numbers attached, are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for what makes a scientific bug report actionable and for the conventions that govern changes to the analysis code.

## Citing

If mac4DSTEM contributes to published work, please cite both it and py4DSTEM, which is the origin of the underlying methods and the reference implementation this port is validated against. Citation metadata for both is in [`CITATION.cff`](CITATION.cff).

## Attribution and licence

mac4DSTEM implements algorithms ported from [py4DSTEM](https://github.com/py4dstem/py4DSTEM) and validated against it.

Released under the **GNU General Public License v3.0 or later**. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contact

Enquiries, issue reports, and collaboration: **mail@mac4dstem.com**
