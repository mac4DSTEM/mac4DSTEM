# Changelog

## v2.5.0 — unreleased (after the presentation pass)

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
- **Split view.** ~~The sidebar and inspector are AppKit split-view columns~~
  *(superseded 2026-09-04: the AppKit shell was deleted in `d5786e2` and the
  window is a SwiftUI `NavigationSplitView` with the native `.inspector`. The
  behaviour below described the retired columns.)* drag far, collapse past the
  minimum, reopen at the last width, the inspector gives way first, the
  sidebar may be up to 600 pt wide. Fixes the constraint-loop crash on a
  sidebar drag (SwiftUI's split view let the divider violate its own
  content minimum).

### Verified by

- `tools/run-tests.sh all` on `e2284f1` (2026-09-03, retained log): unit 467
  passed / 0 failed / 3 skipped, 43 harnesses green including the real-data
  acceptance, but **exit 1** at `package-test`, whose literal version assertion
  the 2.5 / 3 bump turned red; the audit was then changed to derive the version
  from the project and passed on the same tree (`b026cd7`, docs and tooling
  only). No aggregate exit 0 is claimed for this tree.
- **Superseded, never released.** Built from `df80e8e` (2026-09-03) and
  notarized, but the AppKit UI it contained was retired the next day
  (`d5786e2`); `docs/status.md` records v2.5.0 as parked. Two earlier builds,
  b026cd7 and 749dbb2, were
  superseded before release: the split-view contract, then the AppKit
  columns): Developer ID archive, app notarization `8fbd3004-199e-46f2-bcb0-0fb5bb9c595f`,
  `mac4DSTEM-2.5.dmg` notarization `cc743aef-165d-4861-b818-9f3eeb1fd669`, stapled, Gatekeeper-accepted;
  DMG SHA-256 `892974e9ae2467a2dfdd5b9c0b23e580dbc9b556c21864ed1c447ef7e9013dd8`. Unit gate on the build tree: 471 passed / 0 failed /
  3 skipped (2026-09-03).
- On screen: the owner's own driving pass (there is no v2.5.0 tag; the human
  checklist was retired 2026-09-03 and its record is in `docs/archive/v2/`).
  That pass predates the 2026-09-04 SwiftUI rebuild, so it is **not** on-screen
  evidence for the current tree.
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
