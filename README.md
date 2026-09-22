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

## New in v4.0.0 (2026-09-23)

- **Requires macOS 27.** The major version marks the new system requirement;
  v3.0.0 stays the download for older systems.
- **A rebuilt interface, on Apple's own design guidance.** One flat inspector
  for every step — labels on the left, values at the edge, the step's main
  action in the toolbar; image contrast in each image's own popover; a window
  that never lets the inspector cover an image.
- **Calibration foundation.** A beamstop-tolerant origin (py4DSTEM's
  `get_origin_friedel` and beamstop mask, at ~1e-6 px parity), an origin
  validity mask, a probe kernel from a separate vacuum scan, and faster
  Friedel and R–Q solves proven bit-identical to the serial code.
- **Materials Project import** by mp-id, standardised to the conventional
  cell, and an **experimental, unvalidated** known-variants phase classifier —
  labelled unvalidated in the app. Known limitations are at the end of the
  v4.0.0 notes.

Full notes: [`CHANGELOG.md`](CHANGELOG.md).

## What it does

- **Explore** real and reciprocal space together, calibrated and GPU-rendered.
- **Virtual imaging** — BF, ADF, HAADF, plus annular, rectangular and point
  detectors placed by hand.
- **Calibration** — probe and origin fitting, elliptical distortion,
  real–reciprocal rotation, reciprocal sampling from a known crystal.
- **Bragg disks** — cross-correlation on the CPU over an exact Bluestein FFT
  (no GPU correlation kernel exists), parabolic and DFT-upsampled subpixel,
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

Every number behind a release — gate exit status and counts, DMG hash,
notarization and staple details — is quoted from the run that produced it in
[`docs/releasing.md`](docs/releasing.md) § Releases, with the full history in
[`CHANGELOG.md`](CHANGELOG.md).

The badge covers four jobs on every push: unit, scientific, the repository's own
`inventory` review, and `core`, which fails the moment `Core/` reaches up into
the app.

All of that is numerical — the app is tested against known-correct values, not
against what it draws. What it draws is checked by a person driving it, because
the numerical gate has stayed green through real on-screen defects.

Merlin MIB and EMPAD RAW readers are preview-grade. Current limitations:
[`docs/open-items.md`](docs/open-items.md).

## Requirements

macOS 27 or later on Apple Silicon. Nothing else to install — every dependency
ships inside the application. Older systems: the v3.0.0 download (macOS 14+)
stays available.

Development and testing happen on macOS 27. The build supports 27 and later —
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
