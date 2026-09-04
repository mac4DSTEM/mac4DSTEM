# Changelog

## v2.5.1 — 2026-09-04

Lowers the system requirement and fixes a reader defect found by the gate on
release night.

- **macOS 14 or later**, down from 26. Exactly two symbols stood above the old
  floor, both cosmetic and both now behind an availability check: the toolbar's
  flexible spacer and the pane divider's resize cursor. Below macOS 15 the
  divider still drags, it just does not change the pointer. macOS 13 is not
  reachable — `@Observable` is macOS 14 and the application's state layer rests
  on it. **v2.5.0 cannot launch below macOS 26**; only this build reaches older
  systems. Development and testing are on macOS 26, and 14–25 has not been
  exercised on hardware, so a report naming your macOS version is useful.
- **A saved result is no longer mistaken for a datacube.** Opening a session
  sidecar directly — easy to do, since it sorts next to the dataset in the open
  panel — could return a saved RGBA orientation map as though it were the data,
  with a four-pixel detector, instead of saying what the file is. It now names
  the file and points at its dataset. The wider class behind this is recorded
  in `docs/open-items.md` and is not yet fixed: discovery still accepts any
  rank-3 array as a datacube.

### Verified by

- `tools/run-tests.sh all` — **exit 0**: 458 passed / 0 failed / 0 skipped,
  44 harnesses including `real-data-acceptance` and `package-test`, read from
  the gate's own exit line. This is the aggregate v2.5.0 could not claim.
- Gate B: four independent refuters, each building its own fixtures. They
  rejected the first version of the reader fix; what shipped is the reworked
  one, and what they left open is filed rather than quietly closed.
- **The shipped artefact.** Built from `a9a0437`, Developer ID archive,
  notarized twice as the procedure requires — the app
  (`fb693c50-c3c2-49a3-a851-b6da20668cff`, Accepted) and then the disk image
  built from that stapled app (`f3d05e79-0ede-4912-a52f-b35ad367db2c`,
  Accepted). Both stapled and validated; `spctl` on the DMG returns `accepted`,
  `source=Notarized Developer ID`. The app inside the shipped image declares
  `LSMinimumSystemVersion 14.0` — checked by mounting it, because that is the
  whole point of this release. `mac4DSTEM-2.5.1.dmg`, 6 157 051 bytes, SHA-256
  `302822063df22399d0fc4a8810fca6a55e53379df34ec4a37a0e0a738b8031af`.

## v2.5.0 — 2026-09-04

Rehearse an analysis on a cropped or binned view, then promote it to the
full cube unattended. Validated against py4DSTEM 0.14.19. (v2.0.0 was tagged
2026-09-02 and never built; the consolidation below supersedes it, and the tag
stays as the pre-consolidation anchor.)

### What is new

- **Load pipeline.** Open with options (scan crop, detector crop, detector
  bin), streaming residency for cubes larger than memory, and a promote run
  that replays the rehearsed recipe on the full cube, re-referencing
  detector-pixel parameters into the full frame. Reduced-file export carries
  the recipe.
- **Sidecar format.** Every session sidecar now names the oldest reader that
  interprets it without misreading. A v1.0.0 build silently restores
  reduced-view results against the full extent, which is why this is a major
  version, not 1.1.
- **Calibration honesty.** Q calibration from a known crystal, ellipse
  distortion, R–Q rotation; a fit that fails its gate reports "not
  quantitative" rather than a number. Probe radius is measured on the mean
  pattern. The DPC angle's 2π unit error is fixed and legacy sidecars migrate.
- **Refusals over guesses.** CIF import refuses what it cannot expand or was
  cut mid-row; ACOM replay refuses a phase model it cannot resolve by id and
  lattice constant; session calibration from a different frame is
  re-referenced or refused, never applied twice.
- **Workflow.** Prepare / Imaging / Strain & ACOM / Phase / Results, a system
  inspector column, a permanent status footer, colormaps on each pane's
  colorbar chip, detached long runs with live progress and Cancel.
- **Speed.** An exact Bluestein FFT for any detector size: Detect All Disks
  on a 250-px cube went from 14 min to under 15 s in Release, same peaks.
- **Consolidation (v2.5, 2026-09-02/03).** `Core/` and `Session/` are Swift
  packages; one product value carries pixels, units, frame, validity and
  provenance from compute to export; calibration, readiness, strain and ACOM
  state have single owners; the Phase workspace lists DPC & iDPC, Parallax and
  Single-slice ptychography as independent tasks with revisitable stages; each
  workspace has its own sidebar; the IPF map is confidence-gated with a slider
  on the colorbar chip. No scientific number changed. *(Amended 2026-09-04: the
  pane-focus routing described here — "the inspector follows the pane with the
  focus ring" — was deleted with the AppKit window. The rebuilt inspector has
  two tabs, Settings and Info, and renders both unconditionally.)*
- **The window is SwiftUI, and the AppKit one is gone (2026-09-04).** The
  hosted AppKit window's 32 files are deleted; `UI/` IS the rebuild, a
  `NavigationSplitView` with the native `.inspector` and no flag selecting
  between them. The inspector has two tabs, Settings and Info. The
  saved-session sidecar's contents — Calibration, BraggVectors, the saved
  results and the actions on them — moved out of Info into the left sidebar's
  Session section, so what came with a dataset is on the left where the
  dataset is; Info keeps the explanations for a sidecar that could not be read
  or did not fit. The status bar gained elapsed / throughput / ETA in a
  reserved fixed-width slot, and the output log moved off `AppState`.

- **Split view.** ~~The sidebar and inspector are AppKit split-view columns~~
  *(superseded 2026-09-04: the AppKit shell was deleted in `d5786e2` and the
  window is a SwiftUI `NavigationSplitView` with the native `.inspector`. The
  behaviour below described the retired columns.)* drag far, collapse past the
  minimum, reopen at the last width, the inspector gives way first, the
  sidebar may be up to 600 pt wide. Fixes the constraint-loop crash on a
  sidebar drag (SwiftUI's split view let the divider violate its own
  content minimum).

### Verified by

- **The full gate was attempted and did NOT pass, and this release does not
  claim it.** `tools/run-tests.sh all` ran on the release tree (2026-09-04,
  retained log) and **exited 1**: unit and 42 scientific harnesses green, then
  a failure in `real-data-acceptance` on a session-sidecar file — a defect that
  predates this release and is recorded, undiagnosed, in `docs/open-items.md`.
  `tools/package-test/run.sh` is sequenced after that step and did not run in
  that pass.
- **What this release IS gated on**, both re-run on the final tree and each
  exit code read on its own line: `tools/run-tests.sh unit` — **457 passed /
  0 failed / 0 skipped, exit 0** across 63 suites (counted by `Suite.method`;
  one log line was chopped mid-name by an interleaved xcodebuild timestamp and
  was reconciled against the source file's 8 test methods, not assumed) — and
  `tools/package-test/run.sh` — **exit 0**, which clean-builds a hardened
  Release and audits the artefact itself: nested signatures, sandbox and
  bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, the
  embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version
  `2.5 (4)` with the macOS 26 floor as the project declares them.
- On screen: the owner drove the rebuilt SwiftUI app on 2026-09-04. A
  full-scan Bragg detection on `sim_Au_data_all_binned.h5` confirmed the status
  bar's live elapsed / throughput / ETA and the output log still updating after
  `ActivityLog` took it off `AppState`; the sidecar contents were checked in
  their new home in the left sidebar. Two things remain unverified on screen —
  a cropped save → quit → reopen, and every divider, which no gate can measure.
- **The shipped artefact.** Built from `3c0a3eb`, Developer ID archive, then
  notarized TWICE as the procedure requires — the app
  (`af7cc0f4-d354-4c7a-bcb9-d245deda5ea1`, Accepted) and then the disk image
  built from that stapled app (`f4aa1d12-91a4-412d-8ad9-979289aede6c`,
  Accepted), because Gatekeeper assesses the thing the user opens. Both stapled
  and validated; `spctl` on the DMG returns `accepted`,
  `source=Notarized Developer ID`. `mac4DSTEM-2.5.dmg`, 6 074 038 bytes,
  SHA-256 `d55821a11dde44b6fc2d1337f43b5eb3ec2342fe6374d0dcc3f72d13ee234c75`.
- Superseded and never released: builds from `df80e8e`, `b026cd7` and `749dbb2`
  (2026-09-03). The first was notarized but carried the AppKit UI retired the
  next day in `d5786e2`. Their provenance is in `docs/archive/v2/`.
  Known issues ship listed in `docs/open-items.md`.

## v1.0.0 — 2026-08-06

Native macOS 4D-STEM analysis for Apple Silicon, validated against
[py4DSTEM](https://github.com/py4dstem/py4DSTEM) 0.14.19.

First tagged release.

### The workflow

A frozen five-stage product workflow — **Prepare → Image / Map / Reconstruct →
Results** — with task-scoped controls and per-task readiness. Every result
carries its model, scale, units and validity through display, export and
reopen.

### Analysis

- **Calibration** — origin/probe fitting, detector-ellipse correction, R–Q
  rotation, Q and R pixel scales, each with explicit provenance and a stated
  consequence when missing. No missing value is ever synthesized.
- **Virtual imaging** — BF/ADF/HAADF and custom annular, rectangular and point
  detectors, dragged live on the diffraction pane.
- **DPC / iDPC** — beam-deflection mapping and integrated projected phase,
  measured against fitted per-position origins.
- **Bragg disk detection** — GPU cross-correlation with parabolic, pixel and
  Fourier (multicorr) subpixel refinement.
- **Strain mapping** — reference region or whole-scan mean, automatic or manual
  g₁/g₂ basis, with basis consensus, fit residual, indexed fraction and
  reference-inlier diagnostics published alongside every map.
- **ACOM orientation** — template matching against a built-in crystal library
  or an imported CIF, with symmetry expansion, IPF·Z colouring and a
  reliability read-out.
- **Parallax / ptychography** — coarse-to-fine bright-field alignment,
  aberration fitting, phase correction, depth sectioning, and single-slice
  iterative object/probe recovery.

### Data

- HDF5/EMD, DM4/DM3, MIB, RAW and vendor XML readers.
- EMD export of Bragg vectors, calibrated datacubes and preprocessed products,
  published atomically via a same-volume scratch directory so a sandboxed save
  cannot leave a partial file.
- Publication figures burn in scale bar, colorbar and caption — including the
  display orientation when one is applied, because an applied-but-unrecorded
  rotation is not acceptable.

### Verification

`tools/run-tests.sh all` — **exit 0, 30 harnesses**: 105 unit tests, 28
scientific parity harnesses, real-data acceptance, and packaging. *(Those are
v1.0.0's numbers, measured at the tag on 2026-08-06, and they are left as the
record of what this release was verified by. The gate has grown since; the
current reproducible figures are in [`README.md`](README.md).)* Parity is
measured against py4DSTEM 0.14.19 on a four-dataset training set, with records
in `References/parity_records/`.

A separate on-screen QC playthrough (`tools/ui-qc-playthrough/run.sh`, since
removed) drove the real app through the canonical py4DSTEM pipelines and logs every number it
reads from the app's own controls. Its last full run was green on all four
datasets.

**What this release was *not* verified by, stated plainly:** no visual QC
baseline exists. Every playthrough run to date used `--no-screenshots`, so the
acceptance evidence for v1.0.0 is numeric only — the numbers the app reports
through its own controls, not what it draws. Creating that baseline needs
Screen Recording granted to the ad-hoc-signed test runner; it was deliberately
deferred rather than faked, and it is the first entry in
[`docs/open-items.md`](docs/open-items.md).

### Fixed at the close of the phase (2026-08-06)

- **Q calibration could be stamped "Measured in app" from an origin the app had
  already flagged as unusable.** On one training dataset that produced a Q pixel
  size 2.56× too large, and the label — not the warning — is what travelled into
  export, reopen and the QC log. `calibrateQFromCrystal` now refuses on the same
  predicate the Prepare readiness row uses, so the badge, the app's behaviour
  and the parity records cannot disagree. The underlying estimator is *not*
  fixed and is fragile to origin error well below that threshold — recorded in
  [`docs/archive/v2/post-v1-ideas.md`](docs/archive/v2/post-v1-ideas.md) as a deliberate scope
  decision, not an oversight.
- **The Result colormap was unreachable from the Results workspace**, the one
  screen built for looking at results.
- **The readiness row called a measured origin "Missing"** directly above a
  detail line reporting it as measured. It now reads "Not quantitative".
- **Split-view height regression (#16/#22)** — a single `fixedSize` propagated a
  minimum height past the window's own, making the sidebar's top rows inert.

### Distribution

Hardened runtime, sandboxed, self-contained, no Homebrew dylib dependency,
macOS 14 floor — **declared, never tested below macOS 26** (corrected 2026-08-28; the clean-account launch was on macOS 27 only). The supported floor is now macOS 26, stated in `README.md`. Developer ID signing, notarization and a clean-account launch
remain release-owner actions.

### Deliberately out of scope

Cropping and partial/binned loading, multi-slice ptychography, and a WS₂ crystal
model. See [`docs/archive/v2/post-v1-ideas.md`](docs/archive/v2/post-v1-ideas.md).

---

## Working notes

The v1.0 development phase's item-level record — 46 numbered findings, the
design passes, and the QC-evaluation prompts — is archived under
[`docs/archive/v1.0/`](docs/archive/v1.0/). It is history, not guidance; nothing
in the current docs points into it. `docs/open-items.md` carries forward only
what is still live.
