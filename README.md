<div align="center">

# mac4DSTEM

**4D-STEM analysis that runs on your Mac, at the speed of a conversation.**

</div>

<!-- TODO: hero screenshot or short screen recording goes here.
     Suggested: the Map workspace with a strain map beside the live CBED and
     its fit overlay — diffraction pattern, result, and diagnostics in one frame. -->

---

## What it is

4D-STEM produces enormous datasets: a full diffraction pattern recorded at
every position the electron beam visits. Getting science out of them usually
means writing Python, waiting on a cluster, and squinting at a notebook.

mac4DSTEM does it on your own machine, interactively. Drag a virtual detector
across a diffraction pattern and watch the image form. Map strain across a
sample. Index crystal orientations. See a result, change a parameter, see the
new result — instead of re-running a script.

It is built on Apple Silicon's GPU from the ground up, and validated against
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), the standard toolkit in the
field, so the numbers it gives you are the numbers you would have got there.

## What you can do with it

- **Look at your data immediately** — open a dataset and explore real and
  diffraction space side by side, with no setup step
- **Form images from any detector** — bright field, annular dark field, HAADF,
  or a custom shape you drag into place
- **Measure strain** across a sample, with the fit quality shown next to the
  map rather than buried in a log
- **Map crystal orientation** against a built-in materials catalogue or your
  own structure file
- **Reconstruct phase** — DPC, iDPC, parallax and ptychography
- **Export what you see**, with scale bar, units and calibration attached

Every result carries its calibration and its provenance. When a number is not
quantitative, the app says so instead of showing it anyway.

<!-- TODO: 2-3 screenshots — virtual imaging, a strain map, an orientation map. -->

## Status

**v1.0.0** — the first release. The full analysis workflow is implemented and
covered by 30 automated test suites, including parity checks against py4DSTEM
on real experimental data.

Being straight about the limits: that verification is *numeric* — the app is
checked against known-correct values, not against how it looks. The Merlin MIB
and EMPAD RAW readers are preview-quality until more vendor data is available.
The current list is in [`docs/open-items.md`](docs/open-items.md).

## Requirements

macOS 14 or later, Apple Silicon. No Python and nothing to install alongside it —
everything the app needs is inside it.

## Building it yourself

Open `mac4DSTEM.xcodeproj` in Xcode and press Run.

Architecture, the test suites, file-format notes and known limitations are in
[`docs/technical-overview.md`](docs/technical-overview.md). Scope and release
contracts are in [`docs/v1-scope.md`](docs/v1-scope.md) and
[`CHANGELOG.md`](CHANGELOG.md); the analysis pipelines and how they map onto
py4DSTEM are in [`docs/py4dstem-pipelines.md`](docs/py4dstem-pipelines.md).

## Credit and licence

mac4DSTEM's algorithms are ported from
**[py4DSTEM](https://github.com/py4dstem/py4DSTEM)** and validated against it.
That project is the reason this one can exist — if you use mac4DSTEM in
published work, please cite py4DSTEM for the underlying methods.

Licensed under the **GNU General Public License v3.0**. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contact

Questions, bug reports, or interest in contributing: **mail@mac4dstem.com**
