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

Xcode 26 or later (development is on 27.0, CI on macos-26) on Apple Silicon,
and a **full Xcode** — the Command Line Tools alone cannot build this project.
Build and test commands: `CLAUDE.md` § Build / test.

Everything under `tools/` resolves its own toolchain via
`tools/lib/developer-dir.sh`: an explicit `DEVELOPER_DIR` wins, then whatever
`xcode-select` points at, then any Xcode in `/Applications`. The scientific
harnesses also need a Python with NumPy and py4DSTEM installed; set
`PYTHON=/path/to/python` if it is not discovered.

## Pushing

All work lands directly on `main`; there are no feature branches (owner
directive, 2026-09-17). Install the pre-push hook once per clone so a push
that CI would reject never leaves the Mac — it runs the inventory gate and an
app-target build into `build/prepush/`, never into the bundle you may be
running:

```sh
git config core.hooksPath tools/hooks
```

To push once without it (a full disk, an emergency): `touch .git/skip-prepush`.

## Where code goes

The Xcode project uses synchronized folder groups, so **placement is
wiring** — a file added under `mac4DSTEM/` joins the app target
automatically. Layering, ownership and where a new file goes: `docs/architecture.md`.

## The rules that actually matter

The full set is `CLAUDE.md` § Hard rules — Gate D (diagnosis before a fix,
independent refuter after), Gate B for anything science-affecting, inline
`DEVIATION` notes against the pinned py4DSTEM source, Metal struct
byte-identity, and never widening a gate that fails silently. Read it before
touching `Core/`.

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
