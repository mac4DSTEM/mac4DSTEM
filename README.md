<h1 align="center">mac4DSTEM</h1>

<p align="center">
  <strong>Interactive 4D-STEM analysis, native to Apple Silicon.</strong>
</p>

<p align="center">
  <a href="https://github.com/mac4DSTEM/mac4DSTEM/actions/workflows/ci.yml"><img src="https://github.com/mac4DSTEM/mac4DSTEM/actions/workflows/ci.yml/badge.svg" alt="CI: unit, scientific, inventory and core gates on every push"></a>
</p>

<p align="center">
  <img src="docs/images/strain-map-workspace.png" alt="mac4DSTEM v2.5.0: a convergent-beam diffraction pattern with detected Bragg disks and lattice fit overlay, beside the resulting epsilon-yy strain map, with fit diagnostics in the inspector" width="100%">
</p>

<p align="center"><sub>v2.5.0 — the Strain &amp; ACOM workspace.</sub></p>

---

4D-STEM records a full diffraction pattern at every probe position. Analysing
those datasets — virtual imaging, strain, orientation, phase — usually happens
offline, in scripts, away from the data. mac4DSTEM does it interactively:
detector geometry, calibration and reconstruction parameters change against a
live view, so you see what a choice does while you make it.

Algorithms are ported from [py4DSTEM](https://github.com/py4dstem/py4DSTEM) and
gated against it, so results trace back to the reference implementation.

## New in v2.5.0

- **Rehearse, then promote.** Work out an analysis on a cropped or binned view,
  then replay it on the full cube unattended. Detector-pixel parameters are
  re-referenced into the full frame; the reduced-file export carries the recipe.
- **Streaming residency** for cubes larger than memory.
- **The window is rebuilt in SwiftUI** — five workspaces, and a Session section
  in the sidebar showing what was saved beside your dataset and restored with it.
- **Speed.** An exact Bluestein FFT for any detector size: Detect All Disks on a
  250 px cube went from 14 minutes to under 15 seconds in Release, same peaks.
- **Refusals over guesses.** A calibration fit that fails its gate reports "not
  quantitative" instead of a number. CIF import refuses what it cannot expand.

Full notes: [`CHANGELOG.md`](CHANGELOG.md).

## What it does

- **Explore** real and reciprocal space together, calibrated and GPU-rendered.
- **Virtual imaging** — BF, ADF, HAADF, plus annular, rectangular and point
  detectors placed by hand.
- **Calibration** — probe and origin fitting, elliptical distortion,
  real–reciprocal rotation, reciprocal sampling from a known crystal.
- **Bragg disks** — GPU cross-correlation, parabolic and DFT-upsampled subpixel,
  live acceptance diagnostics.
- **Strain** — robust local lattice fitting, with basis consensus, residual and
  indexed fraction on every map.
- **Orientation** — polar-correlation template matching against a validated
  catalogue or your own CIF, with reliability and IPF output.
- **Phase** — DPC, iDPC, parallax, single-slice ptychography.
- **Export** — EMD Bragg vectors, datacubes and products, readable in py4DSTEM.

Every quantity carries its calibration and provenance through display, export
and reopening. Where a measurement is not quantitatively supported, it says so.

## Verification

Every number here is quoted from the run that produced it.

- `tools/run-tests.sh unit` — **457 passed, 0 failed, 0 skipped**, exit 0
  (2026-09-04, the release tree).
- `tools/package-test/run.sh` — **exit 0**: nested signatures, entitlements,
  embedded HDF5, and the declared version and macOS floor.
- The shipped `mac4DSTEM-2.5.dmg` is signed and notarized (app and image both),
  stapled, and `spctl`-accepted as `Notarized Developer ID`. SHA-256
  `d55821a11dde44b6fc2d1337f43b5eb3ec2342fe6374d0dcc3f72d13ee234c75`.
- `tools/run-tests.sh all` — **exit 1** (2026-09-04). Unit and 42 scientific
  harnesses green, then a failure in `real-data-acceptance` on a session-sidecar
  file. That defect predates this release and is recorded, undiagnosed, in
  [`docs/open-items.md`](docs/open-items.md). **No aggregate exit 0 is claimed.**

The badge covers four jobs on every push: unit, scientific, the repository's own
`inventory` review, and `core`, which fails the moment `Core/` reaches up into
the app.

All of that is numerical — the app is tested against known-correct values, not
against what it draws. What it draws is checked by a person driving it, because
the numerical gate has stayed green through real on-screen defects.

Merlin MIB and EMPAD RAW readers are preview-grade. Current limitations:
[`docs/open-items.md`](docs/open-items.md).

## Requirements

macOS 14 or later on Apple Silicon. Nothing else to install — every dependency
ships inside the application.

Development and testing happen on macOS 26. The build supports 14 and later —
that is the enforced minimum, not a claim every version has been exercised — so
if something misbehaves on an older system, a report with the version in it is
especially useful.

## Building

Open `mac4DSTEM.xcodeproj` and build the `mac4DSTEM` scheme.

Architecture and supported formats: [`docs/architecture.md`](docs/architecture.md).
What is live now: [`docs/status.md`](docs/status.md). The pipelines and their
correspondence to py4DSTEM: [`docs/py4dstem-pipelines.md`](docs/py4dstem-pipelines.md).

## Contributing

Issue reports — especially parity discrepancies with numbers attached — are
welcome. [`CONTRIBUTING.md`](CONTRIBUTING.md) covers what makes a scientific bug
report actionable.

## Citing

Please cite mac4DSTEM and py4DSTEM, the origin of the underlying methods.
Metadata for both: [`CITATION.cff`](CITATION.cff).

## Licence

Algorithms ported from [py4DSTEM](https://github.com/py4dstem/py4DSTEM) and
validated against it. Released under the **GNU General Public License v3.0 or
later** — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contact

**mail@mac4dstem.com**
