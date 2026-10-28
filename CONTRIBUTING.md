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

## Building and testing

You need a full Xcode 27 or Xcode 26.6 (the Command Line Tools alone cannot build this project) on an Apple silicon Mac;
the app's minimum system is macOS 26. Open `mac4DSTEM.xcodeproj` and build the `mac4DSTEM` scheme, or from the shell:

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
tools/run-tests.sh unit         # the unit tests: run these before you open a pull request
tools/run-tests.sh core         # checks that Core/ never reaches up into the app
tools/run-tests.sh inventory    # repository checks (notices, large files, harness list)
tools/run-tests.sh scientific   # the parity harnesses against py4DSTEM (slow; needs Python)
```

Run the app in the `Develop` configuration, not `Debug`: Xcode builds the kits at `-O` for it, and a Debug build runs
them unoptimised and many times slower.

Everything under `tools/` resolves its own toolchain via `tools/lib/developer-dir.sh`: an explicit `DEVELOPER_DIR`
wins, then whatever `xcode-select` points at, then any Xcode in `/Applications`. The scientific harnesses also need a
Python with NumPy and py4DSTEM; `tools/lib/fetch-py4dstem.sh` fetches py4DSTEM at the pinned commit, and
`PYTHON=/path/to/python` overrides the interpreter if it is not found.

## Where code goes

The Xcode project uses synchronized folder groups, so **placement is wiring**: a file added under `mac4DSTEM/` joins
the app target automatically. Views describe the interface only; loading, parsing and computing live in `Core/` (the
`DSTEMCore` package), which never imports anything above it. Layering and ownership in more detail:
[`docs/architecture.md`](docs/architecture.md).

Science that has a kit equivalent (EDX, file readers, crystallography, the 4D-STEM core, FFTs and image maths) is fixed
in the kit's own repository and reaches the app when `Package.swift` moves to the kit's new tag.

## The rules that matter

- **Tests move with the code.** A change comes with tests that fail before it and pass after it.
- **Numbers are checked against the Python reference.** A number a scientist reads is compared with the pinned py4DSTEM
  result within the tolerance py4DSTEM's own tests use for that function, never widened to hide a bug. Readers, I/O,
  indices and metadata are tested exact. A change that moves a pinned number updates the fixture on purpose, in its own
  commit, with the reason. [`docs/parity.md`](docs/parity.md) lists each function and its tolerance.
- **One focused change per commit**, with a clear message, and CI green.
- Mark every deviation from py4DSTEM with an inline `DEVIATION` note giving the reason and the py4DSTEM source it
  departs from, keep Metal parameter structs byte-identical to their `.metal` counterparts, and never loosen a check
  that fails silently.
- A result that has not been compared with a dataset of known truth is shown with `validation: none` until it has.

## Scope

A feature that fixes a known problem or follows from an open issue is welcome. For anything larger, please open an
issue to talk it through before building it.

## Licence

By contributing you agree that your contribution is licensed under the
**GNU General Public License v3.0 only (GPL-3.0-only)**, consistent with the project and
with py4DSTEM, from which its algorithms are derived. See `LICENSE` and
`NOTICE`.
