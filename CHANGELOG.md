# Changelog

## Unreleased — next v2.5.x patch

- **Labels that could misstate a number, from the 2026-09-04 UI review.** The
  inspector's pattern statistics say "Mean pattern", "Max pattern" or
  "ROI-sum pattern" when that is what is on screen; the A/B/A−B comparison
  panels carry a colorbar with range, units and a zero mark; the cursor
  readout prints four significant digits instead of a raw float; a strain or
  orientation map computed from Bragg disks whose settings have since
  changed is flagged in the sidebar and the inspector with the same words as
  the result pane; the scale bar never prints a unitless sampling as "px";
  and without a probe kernel detected peaks are marked with a cross rather
  than circled at an invented radius.
- **Pane headers compress instead of clipping**, with an overflow menu for
  the controls that no longer fit, and the diffraction/real-space divider
  keeps its position across loads, trips to Results and reopening.

## Unreleased — the v2.6.0 science lane

- **A flat measured kernel, and the file's own probe as a kernel source.**
  py4DSTEM's `Probe.get_kernel` recommends the FLAT mode — the probe
  normalised and shifted, nothing subtracted — "for bullseye or other
  structured probes"; the app's measured kernel could only subtract the
  sine² trench, which at the estimator's under-read radius (7.4 px for a
  ring that ends at ~10–12) leaves the beam never the brightest correlation
  peak on the bullseye probe — flat needs no radius. Map ▸ Bragg disks gains
  a measured-kernel mode (flat by default / sigmoid trench) and **Use File's
  Probe**, which reads py4DSTEM's probe from the file on the cube's detector
  grid in both layouts: legacy v0.12 `probe_template` (Qx, Qy, N) and the
  modern `Probe` node (2, Qx, Qy), slice 0 either way. On
  `calibrationData_bullseyeProbe` the app's flat file-probe kernel
  reproduces py4DSTEM's flat route peak for peak — 878 of 878 within
  0.0013 px and 164 of 164 exactly at two thresholds, both sides pinned to
  the template's centre (125, 125), poly subpixel, 90 positions — and the
  kernel built at the app's own probe centre matches to 3e-6. Provenance
  records `kernel_mode` and `kernel_probe_path`; a file-probe kernel refuses
  to replay rather than substitute (the recipe names the path; rebuilding it
  is owed). Unverified on screen. The probe-size estimator still reads a
  ring-shaped probe small — open item.
- **The one-peak-per-pattern warning names the threshold.** When full-scan
  detection keeps at most one peak in the median pattern, the Bragg panel
  used to say "spacing or thresholds may be too restrictive". It now names
  Min relative intensity with its value, says that with Relative to peak 0
  the reference is the brightest peak — the central beam when it is in the
  pattern — and offers the two remedies. WS₂ is the case: its disks are
  ~0.2 % of the beam and the shipped 0.5 % rejects every one. Unverified on
  screen. The default itself is unchanged: measured on six training cubes,
  moving the reference to the brightest disk floods noise (WS₂ 1 → 45 peaks
  per position where ~13 are disks; sim_Au and MgO saturate the 70-peak cap),
  so the remedy stays a lower threshold per dataset
  (`docs/archive/closed-items-2026-09.md`).
- **The diffraction origin is measured where the beam is.** The per-pattern
  centre of mass took one pass in a window of 1.2 × the probe radius around a
  coarse block centre; on a small beam the window could not reach it and
  every position read 0.25 px toward the block (WS₂: 63.99 for a beam at
  63.74, which every radius, Q scale and strain number then carried). The
  window now recentres on its own estimate and is never smaller than the
  probe radius plus 1.5 px, so the beam's soft edge is inside it (Gate D
  and Gate B, `docs/q-calibration-design.md` §9). How far an origin moves
  depends on where the beam sat in the coarse block grid, not on the disk
  size: across ten training cubes the mean origin shifts between 0.001 px
  and 0.77 px, single patterns by up to 1.3 px, and the new values track an
  independent wide-window reference within 0.02 px on every clean cube.
  Translating a pattern now moves the measured origin by exactly the
  translation (it was off by up to 0.65 px).
- **A legacy py4DSTEM v0.12 `realslices` stack is refused as a datacube.**
  The string-label rule applied only to `diffractionslices`, so a strain
  stack stored (R, R, 4) with label strings in `dim3` opened as a cube with a
  four-pixel detector. The check pinning this had been committed red on
  2026-09-05 and no gate ran after it; the `peak-overlay-test` harness had
  also stopped compiling the same day. Both fixed, the gate rerun in full.
- **Q calibration from a known crystal averages the innermost shell's
  equivalents instead of taking the smallest.** The smallest radius was the
  same spoke almost everywhere — a small origin offset makes one side of the
  ring read short — so the pixel size came out 2.1 % high on the WS₂ training
  set; the cluster mean cancels the offset for a symmetric set and agrees
  with the file's second shell to 0.001 px (Gate D and B,
  `docs/q-calibration-design.md` §8). The estimate reports how many peaks it
  averaged. Known limit: on a single crystal whose Friedel pairs differ in
  radius the band can truncate the cluster (recorded).
- **A recipe cannot replay against the wrong CIF.** Imported phase models are
  identified by their file stem, so two different CIFs named alike shared an
  id and a saved recipe resolved either. The ACOM step now records a content
  fingerprint of the cell, symmetry and atomic basis, and replay refuses by
  name when the session's same-named import differs; older recipes without
  the key still resolve as before.
- **Origin calibration refuses instead of inventing a probe.** A mean pattern
  with no intensity above zero used to yield a 1 px probe at the detector's
  geometric centre, stored with "measured" provenance, and the calibration
  carried on against it. `probeSize` now reports nothing to measure, both
  calibration entry points refuse with a sentence, and a NaN or infinite pixel
  is one dead pixel rather than a poisoned maximum or a NaN centre (py4DSTEM's
  `np.max` would void the measurement; inline DEVIATION). The threshold-slope
  median now matches `np.median` for an even count — the port took the upper
  middle value alone, a Gate B finding; the probe radius can move by a
  fraction of a pixel on some patterns.
- **ACOM bundles carry the origin they were computed against.** The origin
  reference, fit residual and excluded fraction are snapshotted when the map
  is computed, as the strain bundle already did, instead of being omitted.
- **Selected-area diffraction's tile masks are pinned** by a ground-truth
  case whose region excludes whole scan rows; the mutation that survived every
  harness on 2026-08-27 now fails it.
- **Gatan STEM-SI DM4 files open with their axes in the calibrated roles.**
  Empty DM tag labels are resolved by physical sibling position (ncempy's
  rule), so the included `Si-SiGe.dm4` is discovered at all. Its calibration
  units name the leading pair real space and the trailing pair diffraction
  space, and the reader now uses that, so the file loads as a 77 × 17 scan of
  448 × 480 patterns with 2 nm and 0.062 nm⁻¹ pixels; before, the previews
  showed diffraction spots under "Scan" and the scan under "Diffraction", and
  py4DSTEM's reader loads the same file swapped, with pixel units (inline
  `DEVIATION`). **Whether the pattern's x and y are the right way round for
  this layout is not yet established** — the tags' x-first convention says
  448 wide, the reader currently says 480 wide — and is a Gate D item in
  `docs/open-items.md` awaiting the owner's GMS observation. A full-cube read
  of that file went from 19 s to under a second (a blocked transpose replaced
  the pattern-at-a-time gather). A DM4 whose four axis units cannot name one
  real and one reciprocal pair opens in the legacy layout with NO pixel
  sizes and a logged reason, instead of being refused. Ordinary
  detector-fastest DM4 files report their scan-crop pushdown again.
- **Manual Q and R pixel scales stay editable.** The field no longer vanishes
  when its row turns green: R is always editable, and Q is editable for every
  provenance except a value measured in the app from a known crystal, with
  the hover text saying which value an entry replaces. Both Prepare and the
  export sheet share the rule (`PrepareSettings.shouldShowManualScaleEditor`).
- **Discovery no longer takes any rank-3 array for a datacube.** py4DSTEM
  stacks (a strain map, a probe stack, any `_labels_` array) and this app's
  saved RGBA maps are refused by their own labels wherever they sit, and a
  genuine 4D cube anywhere in a file now outranks a rank-3 array anywhere —
  before, a shallow rank-3 sibling could be returned AS the data, and the
  pinned real files escaped only by where their nodes sorted alphabetically.
  Legacy py4DSTEM v0.12 slice stacks are refused too, by the string-typed
  label vector that format keeps. A file whose best node is an unlabelled
  rank-3 array still opens as one scan row, as before, and the v2.5.1 sidecar
  location guard stays. Gated by the new `tools/datacube-discovery-test`
  harness (27 fixtures) and five unit tests. The unit gate passed with
  463/0/1 and the scientific gate passed all 43 harnesses on 2026-09-05;
  the closed item is recorded in `docs/archive/closed-items-2026-09.md`.
- **A rank-3 EMD file's pixel sizes were read from the wrong axes.** For a
  file stored as (N, Qy, Qx) the reader took the detector spacing as the
  real-space pixel size and found no Q size; it now reads the scan axis and the
  detector axis. Found by the Gate B refuter on the change above; only files
  with rank-3 data and EMD dim vectors are affected.

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
