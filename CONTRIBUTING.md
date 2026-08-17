# Contributing

Thanks for looking. mac4DSTEM is a scientific instrument as much as an
application: a wrong number that looks plausible is worse than a crash, so the
conventions below are mostly about making correctness checkable by someone
other than the author.

## Reporting a problem

Open an issue. A scientific bug report is much more useful with:

- **The dataset shape and format** — e.g. `128×128×128×128 float32`, HDF5/EMD,
  DM4, MIB, RAW. Real geometry matters; several bugs here only appeared on
  non-square scans.
- **What the app reported** — the calibration provenance badges, the readiness
  row, and any diagnostic the result carries (fit residual, indexed fraction,
  basis consensus, reliability). These are on screen for exactly this reason.
- **macOS version and Mac model.** Apple Silicon only.
- **What py4DSTEM produced**, if you have it. A parity discrepancy with numbers
  attached is the most actionable report this project can receive.

Please do not attach datasets to issues. Describe them, or link to a published
one.

## Building

macOS 14 or later on Apple Silicon, and a **full Xcode** — the Command Line
Tools alone cannot build this project.

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
```

```sh
tools/run-tests.sh unit          # fast XCTest suite
tools/run-tests.sh scientific    # py4DSTEM-parity harnesses
tools/run-tests.sh all           # the acceptance gate
```

Everything under `tools/` resolves its own toolchain via
`tools/lib/developer-dir.sh`: an explicit `DEVELOPER_DIR` wins, then whatever
`xcode-select` points at, then any Xcode in `/Applications`. The scientific
harnesses also need a Python with NumPy and py4DSTEM installed; set
`PYTHON=/path/to/python` if it is not discovered.

## Where code goes

The Xcode project uses synchronized folder groups, so **placement is wiring** —
a file added under `mac4DSTEM/` joins the app target automatically, and `.metal`
files route to the Metal compile phase on their own.

| Adding | Goes under |
|---|---|
| Window/workflow state, app entry | `mac4DSTEM/App/` |
| Readers, calibration model, export, product model | `mac4DSTEM/Core/Data/` |
| GPU engine, FFTs, cancellation | `mac4DSTEM/Core/Compute/` |
| Analysis algorithms | `mac4DSTEM/Core/Analysis/` |
| Crystal models, ACOM matching | `mac4DSTEM/Core/Crystal/` |
| SwiftUI views and controls | `mac4DSTEM/UI/` |
| Metal kernels | `mac4DSTEM/Shaders/` |
| Unit / workflow-contract tests | `mac4DSTEMTests/` |
| Parity or packaging harnesses | `tools/<name>/` |

## The rules that actually matter

- **Views describe UI only.** Loading, parsing and compute live in `Core/`.
  `AppState` is the single source of truth.
- **A change to `Core/` or to anything science-affecting needs a parity fixture
  in `tools/`**, and a review that tries to *refute* it rather than confirm it.
  A green build is not evidence of parity. This is not ceremony: fixes here
  have twice passed every test written for them and still been wrong.
- **A test written for your own fix proves nothing until you have watched it
  fail without the fix.**
- **Departures from py4DSTEM get an inline `DEVIATION` note** giving the reason
  and citing the corresponding location in `References/py4DSTEM-dev/`, which is
  the pinned py4DSTEM 0.14.19 source those citations refer to.
- **Metal parameter structs in `MetalEngine.swift` must stay byte-for-byte
  identical** to the matching `.metal` structs — all 4-byte fields.
- **Acceptance is evaluation only.** Never change app code to make an
  acceptance step pass. If the app blocks the pipeline, that is a finding, not a
  bug to paper over. Acceptance means `tools/run-tests.sh` (Track A) plus the
  human visual pass in `docs/visual-acceptance-checklist.md` (Track B) — the
  XCUITest QC playthrough was retired 2026-08-17 and is unmaintained.
- **Never widen a gate that fails silently.** A check that degrades to a
  warning nobody reads is worse than no check.

## Scope

`ROADMAP.md` carries the standing priorities and `docs/open-items.md` is the
live list of what is known-broken or unverified. A feature that closes neither
a documented gap nor a stated priority is likely out of scope — worth opening
an issue to discuss before building it.

## Licence

By contributing you agree that your contribution is licensed under the
**GNU General Public License v3.0 or later**, consistent with the project and
with py4DSTEM, from which its algorithms are derived. See `LICENSE` and
`NOTICE`.
