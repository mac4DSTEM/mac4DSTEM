# Canonical py4DSTEM Analysis Pipelines

**Purpose.** This document reconstructs the *standard* 4D-STEM analysis
workflows as taught by the py4DSTEM authors, straight from the tutorial
notebooks in `References/py4DSTEM_tutorials-main/notebooks/` (current /
top-level versions, v0.14.8–0.14.19). It is deliberately written from the
science down — **not** reverse-engineered from mac4DSTEM's UI — so it can
serve two jobs:

1. Define the pipelines the QC playthrough should actually drive the app
   through (an evaluation grounded in real workflows, not in whichever
   buttons happen to have accessibility identifiers).
2. Be a reference for refining mac4DSTEM's UI — every place the app's
   structure diverges from the canonical workflow is a candidate for making
   the app more intuitive. Divergences are collected in
   [§7 UI observations](#7-ui-observations--gaps).

Each pipeline lists, per step: **what** it does, **inputs/prerequisites**,
**key parameters**, and **outputs**. Notebook sources are cited as
`notebooks/<name>.ipynb`.

> Scope note: this is the *documentation-first* deliverable. Executing these
> pipelines through mac4DSTEM and reporting findings is the next phase,
> pending review of this document.

---

## 0. The shared front-end (every pipeline starts here)

py4DSTEM notebooks almost all open with the same sequence before they branch
into a specific analysis. Source: `basics_00`…`basics_03`, and the opening
sections of the DPC/parallax/ptycho/ACOM/strain notebooks.

| # | Step | What / why | Key inputs & params | Output |
|---|------|-----------|--------------------|--------|
| 0.1 | **Load** | `import_file` (vendor formats: .dm4/.mib/…) or `read` (native .h5). Large sets can bin-on-load. | filepath; `datapath`/`data_id` to pick a block; `binfactor` | `DataCube` (Rx,Ry,Qx,Qy) |
| 0.2 | **Inspect shape & calibration** | Confirm R-shape (scan) and Q-shape (detector); see which calibrations came from file metadata. | — | pixel sizes/units (often "pixels" = uncalibrated) |
| 0.3 | **Set known real-space pixel size** | If the scan step is known (e.g. 5 nm), set it explicitly. | `set_R_pixel_size`, `set_R_pixel_units` | R calibrated |
| 0.4 | **Filter hot pixels** | Remove x-ray/detector artifacts brighter than local neighborhood. | `filter_hot_pixels(thresh=8)` | cleaned cube |
| 0.5 | **Bin / crop** | Downsample Q (`bin_Q`) or crop R to reduce size / focus ROI. | `bin_Q(4)` | smaller cube |
| 0.6 | **Mean & max diffraction patterns** | First real look at the data: single-crystal? poly? amorphous? mean shows dominant features, max shows *all* Bragg scattering. | `get_dp_mean()`, `get_dp_max()` | `VirtualDiffraction` images |

**Key idea:** calibration values are either scraped from the file, set by
hand from known acquisition parameters, or *measured later from the data
itself* (origin/ellipse/pixel-size — see §2). py4DSTEM never silently
invents them; an uncalibrated axis stays in "pixels".

---

## 1. Virtual imaging (real-space images from the 4D cube)

Source: `basics_01_visualization_and_virtualimaging.ipynb`. This is the
"virtual DF/BF" family — the simplest analysis, and the one the QC run calls
"Virtual DF".

| # | Step | What / why | Key params | Output |
|---|------|-----------|-----------|--------|
| 1.1 | **Find probe center & size** | Locate the direct beam and its radius, either by hand or programmatically. | `get_probe_size(dp_mean)` → `probe_semiangle, qx0, qy0` | center + radius |
| 1.2 | **Virtual bright field** | Circular detector over the direct beam → BF image. | `get_virtual_image(mode='circle', geometry=(center, radius))` | BF image |
| 1.3 | **Virtual annular dark field** | Annulus (e.g. `r_inner=3×`, `r_outer=6×` probe radius) → ADF image sensitive to scattered intensity. | `get_virtual_image(mode='annulus', geometry=(center,(ri,ro)))` | ADF image |
| 1.4 | **Off-axis dark field** | Small circular detector on a specific Bragg spot → image of grains diffracting into that spot. | `get_virtual_image(mode='circle', geometry=((qx,qy), r))` | DF image |
| 1.5 | **Virtual diffraction from an ROI** | Inverse: average DP over a real-space mask → what a region scatters like. | `get_virtual_diffraction(mask=...)` | DP |

**Prerequisites:** none beyond load. **No calibration required** for a
qualitative virtual image (physical pixel sizes only add scale bars).

---

## 2. Bragg disk detection + calibration (the crystalline prerequisite)

Sources: `basics_02_diskdetection.ipynb`, `basics_03_calibration.ipynb`.
This block is the shared foundation for **ACOM and strain**. Its ordering is
the single most important workflow fact in this document:

> **Disk detection comes BEFORE origin/ellipse/pixel-size calibration**,
> because those calibrations are *measured from the detected Bragg vectors*.

### 2a. Disk detection (template matching)

| # | Step | What / why | Key params | Output |
|---|------|-----------|-----------|--------|
| 2.1 | **Get a vacuum probe template** | Ideally a separate vacuum scan; otherwise a probe from a vacuum region of the scan (ROI mask). | `get_vacuum_probe(ROI=mask)` | `Probe` |
| 2.2 | **Build the correlation kernel** | Sigmoid "trench" kernel (negative ring around the probe) acts as an edge filter that locks onto disk centers. | `probe.get_kernel(mode='sigmoid', radii=(α, 2α))` | kernel |
| 2.3 | **Tune detection params on a few DPs** | Test on ~6 hand-picked scan positions before running everything. | `find_Bragg_disks(data=(rxs,rys), template=kernel, **params)` | peaks (subset) |
| 2.4 | **Detect all disks** | Run over the whole scan. | same `detect_params` (see below) | `BraggVectors` |
| 2.5 | **Bragg vector map (BVM)** | 2D histogram of all Bragg positions/intensities — the diagnostic overview. | `braggpeaks.histogram(mode='raw', sampling=…)` | BVM image |

Canonical `detect_params` (from the notebooks): `minAbsoluteIntensity`,
`minRelativeIntensity`, `minPeakSpacing`, `edgeBoundary`, `sigma` (blur),
`maxNumPeaks`, `subpixel` ('poly'/'multicorr'), `corrPower`,
`upsample_factor`.

### 2b. Calibration (measured from the Bragg vectors)

| # | Step | What / why | Call | Output |
|---|------|-----------|------|--------|
| 2.6 | **Origin** | Measure per-pattern center from brightest disk, then fit a smooth plane (descan correction). Beamstop variant exists. | `measure_origin()` → `fit_origin()` | qx0,qy0 maps |
| 2.7 | **Ellipticity** | Fit an ellipse to an isolated ring of Bragg peaks; correct detector distortion. Must be manually accepted after inspecting the fit. | `fit_ellipse_1D(bvm, center, fitradii)` → `set_p_ellipse(p)` | (a,b,θ) |
| 2.8 | **Pixel size (Q)** | Match detected Bragg peaks to a **known crystal standard's structure factors** (e.g. gold, a=4.08 Å), refine `Q_pixel_size`. Done *last* — ellipticity affects it. | `Crystal(...).calculate_structure_factors(k_max)` → `crystal.calibrate_pixel_size(bragg_peaks)` | Å⁻¹/px |
| 2.9 | **Rotation (R↔Q)** | The angle between scan and detector frames; needed for strain and calibrated geometry. | `compare_QR_rotation(...)` → `set_QR_rotation_degrees(θ)` | rotation |

**Takeaway for the app:** the Q pixel-size *is* obtainable for a sample of
known structure (like our simulated gold) via the crystal-matching method —
it is not "genuinely unavailable." An uncalibrated ACOM run is a *choice to
skip step 2.8*, not an inherent limit of the dataset.

---

## 3. ACOM — Automated Crystal Orientation Mapping

Sources: `orientation_01_AuAgPd_wire.ipynb`,
`orient_strain_01_WS2.ipynb`. Method paper: Ophus et al., *Sparse
Correlation Matching* (doi:10.1017/S1431927622000101). Requires `pymatgen`
for full symmetry support.

**Prerequisites:** completed disk detection (§2a) + **physical Q pixel size**
(§2.8) + origin (§2.6). Orientation matching against a crystal template is
only physically meaningful with a calibrated reciprocal scale.

| # | Step | What / why | Key params | Output |
|---|------|-----------|-----------|--------|
| 3.1 | **Define the crystal** | Build the reference crystal (lattice + basis + Z). | `Crystal(pos, Z, a)` | crystal |
| 3.2 | **Structure factors** | Compute kinematical diffraction amplitudes out to `k_max`. | `calculate_structure_factors(k_max)` | structure factors |
| 3.3 | **Orientation plan** | Precompute a library of simulated patterns across the zone-axis range + in-plane rotations. | `orientation_plan(zone_axis_range='auto', angle_step_zone_axis=2°, angle_step_in_plane=5°, corr_kernel_size=…)` | plan |
| 3.4 | **Match all positions** | Correlate each position's Bragg peaks against the plan → best orientation. | `match_orientations(bragg_peaks)` | `orientation_map` |
| 3.5 | **Plot orientation maps** | IPF-colored orientation, correlation/reliability. | `plot_orientation_maps(orientation_map)` | IPF maps |

---

## 4. Strain mapping

Sources: `basics_04_strain.ipynb`, `strain_01_Si_SiGe.ipynb`.

**Prerequisites:** disk detection (§2a) + origin (§2.6) + rotation (§2.9).
Ellipticity/pixel-size can be inherited from a calibration dataset.

| # | Step | What / why | Key params | Output |
|---|------|-----------|-----------|--------|
| 4.1 | **BraggVectors → StrainMap** | Wrap detected + calibrated Bragg vectors. | `StrainMap(braggvectors=braggpeaks)` | strainmap |
| 4.2 | **Choose basis vectors g1,g2** | Pick the two reciprocal lattice vectors that define the reference lattice (interactive or from an ROI). | `choose_basis_vectors(...)` / `get_reference_g1g2(ROI)` | g1,g2 |
| 4.3 | **Fit basis at every position** | Index each position's peaks to (g1,g2). | `set_max_peak_spacing(...)` → `fit_basis_vectors(...)` | per-position lattice |
| 4.4 | **Compute strain tensor** | ε_xx, ε_yy, ε_xy, θ relative to reference; `coordinate_rotation` aligns output axes to the image. | `get_strain(coordinate_rotation=…)` | strain maps |
| 4.5 | **Show** | Strain component maps + reference directions. | `show_strain()` | figures |

**Reference options** (a genuine UI-relevant subtlety): reference g1,g2 can be
(a) the whole-scan average, (b) from a chosen unstrained ROI, or (c) manually
specified. The choice defines what "zero strain" means.

---

## 5. Phase-contrast pipelines (no disk detection needed)

These reconstruct the sample potential/phase directly from the redistribution
of intensity — they do **not** use Bragg disk detection or crystal
calibration. All need the **accelerating voltage (energy)**.

### 5a. DPC — Differential Phase Contrast
Source: `dpc_01.ipynb`.

| # | Step | Call | Notes |
|---|------|------|-------|
| 5a.1 | Construct + preprocess | `DPC(energy, datacube).preprocess(plot_center_of_mass='all')` | Solves R↔Q rotation by **minimizing the curl of the CoM** (curl of a gradient is 0); computes & normalizes center-of-mass. |
| 5a.2 | Reconstruct | `.reconstruct(reset=True).visualize()` | Iterative Fourier-space integration of the CoM gradient → electrostatic potential. |

### 5b. Parallax (tilt-corrected bright-field STEM)
Sources: `parallax_01.ipynb`, `parallax_02.ipynb`. Uses a highly *defocused*
probe.

| # | Step | Call | Notes |
|---|------|------|-------|
| 5b.1 | Construct + preprocess | `Parallax(datacube, energy, object_padding_px).preprocess(edge_blend=…)` | Forms virtual BF images from each BF-disk pixel (≈ tilted plane-wave images). |
| 5b.2 | Reconstruct (align) | `.reconstruct(alignment_bin_values=[32,…,8])` | Cross-correlates virtual BF images across progressively finer binning → aligned (focused) BF. |
| 5b.3 | Subpixel upsample | `.subpixel_alignment()` | Kernel-density upsampling beyond scan Nyquist. |
| 5b.4 | Aberration fit | `.aberration_fit(fit_aberrations_max_radial_order=…, max_angular_order=…)` | Fits CTF (defocus, astigmatism, higher orders) from the shift field. |
| 5b.5 | Aberration correct | `.aberration_correct()` | Phase-flips the CTF → corrected reconstruction. |

### 5c. Iterative ptychography
Sources: `ptychography_01`…`04`. Variants: `SingleslicePtychography` (thin),
`MultislicePtychography` (thick), `MixedstatePtychography` (partial
coherence), `PtychographicTomography` (tilt series).

| # | Step | Call | Notes |
|---|------|------|-------|
| 5c.1 | Construct + preprocess | `SingleslicePtychography(energy, defocus, semiangle_cutoff or vacuum_probe).preprocess()` | Aligns DPs to the probe aperture; initializes probe + object on the FOV. |
| 5c.2 | Reconstruct | `.reconstruct(num_iter=64).visualize()` | Iterative phase retrieval; constraints available (pure-phase object, fix probe, etc.). |

---

## 6. Dataset ↔ pipeline map (our training set)

| Dataset | Structure | Natural pipeline(s) | kV | Notes |
|---------|-----------|--------------------|-----|-------|
| `sim_Au_data_all_binned.h5` | simulated poly/single-crystal Au | **virtual imaging → disks → calibrate (Q from gold) → ACOM** | 200 | The exact dataset used in `basics_01–03`; Q pixel size *is* recoverable via gold structure matching. |
| `polycrystal_2D_WS2.h5` | simulated polycrystalline WS₂, known per-grain strain | **disks → calibrate → ACOM + strain** | 200 | Matches `orient_strain_01_WS2.ipynb`; strain ground truth is exact ±1% multiples. |
| `downsample_Si_SiGe_exp.h5` | experimental Si/SiGe | **disks → origin+rotation → strain** | 200 | Matches `strain_01_Si_SiGe.ipynb`. |
| `Particle_1_…_300kV_bin8.h5` | experimental particle stack | virtual imaging; disks/strain if crystalline | 300 | Only 300 kV file; `ss30nm` → 30 nm scan step, `cl-600mm` camera length. |

---

## 7. UI observations & gaps

First-pass observations comparing the canonical workflow to mac4DSTEM's
current structure (workspaces **Prepare → Image → Map → Reconstruct →
Results**; tasks Virtual Det / DPC / Disks / Strain / ACOM / Ptycho). These
are hypotheses to confirm during the execution phase, and candidate UI
improvements — not yet verified claims.

1. **Ordering: app diverges from py4DSTEM — and that's mostly fine.**
   py4DSTEM detects Bragg disks *first*, then measures origin/ellipse/
   pixel-size *from* those vectors. The app puts calibration in **Prepare**
   (workspace 1) and disk detection in **Map** (workspace 3). Crucially,
   **the app measures origin & probe independently** — in the QC run,
   "Measure Origin & Probe" succeeded in Prepare with *no* prior disk
   detection (result: "Origin: Measured in app · Probe: 6.1 px, Fit RMS
   0.16 px"). So the app has its own origin/rotation measurement and does
   **not** inherit py4DSTEM's disks-first constraint for those. That is
   arguably *better* UX than the notebooks. The genuine ordering gaps are
   narrower (see #2, #3): the *pixel-size* (Q) calibration and *ACOM* do
   still need Bragg vectors first, and the UI doesn't make that dependency
   obvious.

2. **Q pixel-size feels "unavailable" when it isn't.** In the last QC run on
   `sim_Au`, Q scale stayed *Missing* and the run self-labeled
   "UNCALIBRATED." But the canonical method (§2.8) derives Q scale by matching
   detected gold peaks to gold structure factors — the app exposes this as
   *"Calibrate Q from Selected Material"* (`calibration.action.qCrystal`),
   which only appears once Bragg vectors + a resolved crystal model exist.
   The UI could surface this path more prominently as the *normal* way to get
   Q scale for a known standard, rather than presenting manual entry as the
   primary option.

3. **ACOM prerequisites aren't sign-posted.** ACOM silently needs (a) detected
   disks and (b) a chosen crystal/phase model. In the failed runs, the ACOM
   primary action was clickable but produced nothing because disks hadn't
   been detected and no material was chosen. Canonically ACOM is
   *disks → crystal → orientation_plan → match*. The app could gate/guide
   ACOM behind an explicit prerequisite checklist (like the calibration
   readiness panel already does for Prepare).

4. **Accelerating voltage placement.** DPC, parallax, and ptychography all
   require the beam energy, and py4DSTEM passes it right into the
   constructor. In the app the kV field only lives under
   Reconstruct → Ptychography and has no accessibility identifier. If voltage
   is a first-class input to three pipelines, it may belong in a shared
   calibration/setup surface rather than buried in one task.

5. **Phase-contrast vs Bragg paths are genuinely separate — the UI could say
   so.** DPC/parallax/ptycho need *no* disk detection or crystal calibration
   (only energy + geometry), whereas ACOM/strain are built entirely on Bragg
   vectors. The app currently interleaves them (Image: VirtualDet+DPC; Map:
   Disks+Strain+ACOM; Reconstruct: Ptycho). Grouping by prerequisite
   ("needs Bragg vectors" vs "needs only energy/geometry") may map better to
   how users actually think about which analysis to run.

6. **Strain reference choice is a real decision the UI should expose.** Zero
   strain is defined by the reference g1,g2 (whole-scan / ROI / manual).
   Whether the app makes this choice visible and explicit is worth checking.

---

## 8. How this feeds the app — scope, disruption, and roadmap

This section answers the strategic question directly: *what do we do with
these findings, how much of the app changes, and is it disruptive?*

### 8.1 The core does not change

mac4DSTEM's **scientific core is already correct and validated**. The
algorithms in `Core/Analysis` (disk detection, origin/ellipse/rotation
calibration, virtual detectors, DPC, parallax, ptychography, strain),
`Core/Crystal` (structure factors, orientation plan/matching), and
`Core/Data` (readers, calibration model) implement the same operations these
py4DSTEM notebooks teach, and are checked against py4DSTEM directly by the
`tools/` acceptance campaign (`tools/training-dataset-campaign`,
`tools/acom-*`, `tools/strain-test`, etc.). **None of the findings in §7 say
"the app computes the wrong thing."** They all say "the app makes the right
computation hard to *reach* or hard to *sequence*." So the core is untouched.

### 8.2 Which layers *do* change (and how much)

The intuitiveness work lives in two layers above the core:

| Layer | Files | What changes | Risk |
|-------|-------|-------------|------|
| **Workflow orchestration** | `App/AppState.swift`, `App/ProductWorkflow.swift` | Prerequisite gating & guidance (e.g. ACOM should announce it needs disks + a phase model), which workspace a task lives in, the primary-action state machine order. | Moderate — it's app logic, but not compute. Behavior-preserving refactors. |
| **Presentation** | `UI/*.swift` | Labels, grouping of tasks by prerequisite, surfacing existing actions (e.g. "Calibrate Q from Selected Material") as the *normal* path, sign-posting, guided flow, ordering hints. | Low — views only. |

So your framing is essentially right, with one correction: it is **not
"only the SwiftUI views."** The *sequencing and prerequisite logic* lives in
`AppState`/`ProductWorkflow`, which is app logic, not view code. But that
logic sits **on top of** the validated core and is mostly re-ordering and
gating of things that already work — not new science.

### 8.3 Is it disruptive?

**Low-to-moderate, and controllable**, because:
- The heavy, risky part (the compute) is frozen and regression-tested.
- The app *already has the right building blocks*: a calibration-readiness
  checklist (great sign-posting pattern), independent origin measurement
  (better than py4DSTEM's disks-first), an explicit phase-model picker,
  export/session infrastructure. Much of the work is **re-wiring and
  re-labelling existing controls**, not building new ones.
- Changes can be staged behind the existing workspace structure rather than
  requiring a UI rewrite.

Where it *could* become disruptive is if we decided to re-order the
top-level workspaces themselves (e.g. move disk detection ahead of
calibration to mirror py4DSTEM). That would be a larger change and is **not
recommended** — the app's independent origin measurement means the current
Prepare→Map order is valid; better to *guide within* the existing structure.

### 8.4 Suggested roadmap

1. **Finish this evaluation.** Get one clean end-to-end pipeline per analysis
   type through the app (starting with `sim_Au` ACOM), driving the app's
   *real* prerequisites in the order the app supports. The per-datacube logs
   + screenshots become the evidence base.
2. **Turn §7 findings into a ranked UI backlog.** Each finding → a concrete,
   scoped UI/workflow change with a "core untouched" guarantee.
3. **Prototype the highest-value guidance changes** (ACOM prerequisite
   gating; surfacing Q-from-crystal; voltage placement) behind the existing
   workspaces.
4. ~~**Re-run this QC playthrough as the acceptance check** for each UI
   change.~~ **Superseded 2026-08-17:** the playthrough is retired; acceptance
   for a UI change is the Track B pass in
   [`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md). The
   *pipelines* below are unaffected — they are still what any acceptance run,
   scripted or human, should drive the app through.

This QC harness is therefore dual-purpose: an *evaluation* of scientific
correctness against py4DSTEM **and** a *usability regression test* for the
workflow layer.

## 9. Empirical findings from QC runs so far

Observations from the actual scripted runs against `sim_Au_data_all_binned`
(these back the §7 points with real evidence; see the run folders under
`References/training_runs/`):

- **Load + virtual DF work immediately.** On open, the app auto-produces a
  virtual detector image ("Virtual detector ✓ (Annulus, 84 × 100)") — good
  first-result-fast behavior.
- **Origin & rotation calibrate cleanly in Prepare, without disks.** Origin
  "Measured in app", probe 6.1 px, fit RMS 0.16 px; rotation θ = 1.9°.
- **Q & R pixel scale stay "Missing"** and the run correctly self-labels
  UNCALIBRATED — but Q *is* recoverable via the gold-structure match (§2.8),
  which the scripted run had not yet performed.
- **ACOM produced nothing until disks were detected.** The root cause of the
  early failures: ACOM was invoked before Bragg disk detection, so it had no
  vectors to match. Confirmed against the canonical order (disks → ACOM).
- **Phase-model selection is required for ACOM** and is not defaulted — the
  app deliberately never infers the phase from the dataset name (good
  scientific hygiene, but the requirement needs sign-posting).
- **Mechanical automation notes** (test-only, not app issues): macOS static
  text exposes content via AXValue not AXTitle; nested
  `.accessibilityElement(children: .contain)` rows don't resolve as
  queryable elements (read the whole panel instead); UI-test runner needs
  ad-hoc code signing; env vars don't reach the runner (use a file handoff).

### 9.1 First clean end-to-end ACOM pipeline (`sim_Au`, 2026-07-21)

Driving the app through the canonical order in §3 produced a **fully clean
run** (`References/training_runs/run_2026-07-21_0013/`), 0 failures, ~195 s:

| Step | Result |
|------|--------|
| Load | Virtual detector ✓ (Annulus, 84×100) auto-computed on open |
| Calibrate origin/rotation | Origin measured (probe 6.1 px, fit RMS 0.16 px); rotation θ = 1.9° |
| Virtual DF | Annular DF image of the Au nanoparticle → exported |
| Disk detection | **103,657 peaks** (parabolic subpixel) → BVM exported |
| Phase model | Gold (FCC) selected |
| **Q from crystal** | **0.0198 Å⁻¹/px** — matches the tutorial's ~0.02 guess (`basics_03`) |
| ACOM | "ACOM preview ✓ · **Physical** · 525 positions · 0.1 s" → exported |

**Two strong positive findings:**
1. The app's gold-structure pixel-size calibration reproduces the py4DSTEM
   tutorial value (0.0198 vs ~0.02 Å⁻¹/px). This is the exact §2.8 method,
   and it confirms §7.2: Q *was* recoverable all along — the earlier
   "UNCALIBRATED" runs had simply skipped this step.
2. Once Q is calibrated, ACOM automatically runs in **Physical** matching
   mode (not exploratory pixel-scale), i.e. the calibration actually flows
   through to the science.

**Remaining nuances for a "complete" ACOM (next-step options, not failures):**
- The run used **Preview** scope (525 positions, a subset) — a full-scan
  orientation map would use the full-scan scope.
- The exported product was the **Reliability** map; the IPF-Z orientation
  coloring is a separate display mode worth capturing too.

This confirms the harness now drives a real, physically-valid crystalline
pipeline end-to-end. The same skeleton (load → calibrate → virtual DF →
disks → phase model → Q-from-crystal → analysis) extends to strain and to
the other datasets.

### 9.2 Strain + phase-contrast pipelines added (all four datasets, 2026-08-03)

The harness now also drives **DPC** (§5a), **strain** (§4) and the
**Reconstruct** workspace (§5b/§5c) after the ACOM skeleton above. Run
folders: `References/training_runs/run_2026-08-03_1345/` (sim_Au — the
verification run on the final harness; `run_..._1302/` is the same result from
an earlier build), `run_2026-08-03_1309/` (Particle_1), `run_2026-08-03_1319/`
(WS₂ + Si/SiGe). Every datacube completed its run — no step aborted a datacube.

| Dataset | DPC | Disks (peaks) | Q from crystal | ACOM | Strain | Reconstruct |
|---------|-----|---------------|----------------|------|--------|-------------|
| `sim_Au` | ✅ | 103,657 | ✅ 0.0198 Å⁻¹/px | ✅ Physical, 525 pos | ✅ **ε_xx, 52% indexed** | ⛔ R pixel scale |
| `downsample_Si_SiGe_exp` | ✅ | 123,885 | ✅ 0.0372 Å⁻¹/px | ✅ Physical, 232 pos | ⛔ basis fit | ⛔ origin RMS + R scale |
| `polycrystal_2D_WS2` | ✅ | 16,384 | — (no model) | ⛔ no WS₂ in library | ⛔ basis fit | ⛔ Q + R scale |
| `Particle_1…300kV` | ✅ | 42,734 | — (no model) | — (no model) | ⛔ basis fit | ⛔ origin RMS + Q scale |

**What this settles for the three new pipelines:**

- **DPC works on every dataset, with no prerequisites at all.** It publishes
  "DPC ✓ (Magnitude (detector px) vs calibrated origins)" straight after
  virtual DF. This matches `ProductWorkflow.prerequisites(for: .dpc)` being
  empty, and confirms §7.5: the phase-contrast path really is independent of
  the Bragg path. Note the *default* display mode is magnitude in detector
  pixels, which needs no voltage — a quantitative phase image would.
- **Strain succeeds on `sim_Au` with the app's own defaults** (whole-scan mean
  reference, automatic basis): 100% basis support (95,229/95,257 peaks), basis
  fit RMS 1.06 px, κ 4.78, 52% of positions locally indexed, 3,853/4,365
  reference inliers. ε_xx was the displayed and exported component.
- **Strain fails on the other three, always at the same place** — automatic
  basis fitting: *"No well-conditioned lattice explains at least half of the
  detected peak population."* The three failures are *not* the same problem
  underneath, which is the useful part (see 9.2.1).
- **The accelerating voltage is now reachable and settable through the UI.**
  The field has no accessibility identifier, but it can be located
  structurally by its "Voltage" row label, and the test typed 200/300 kV into
  it successfully on all four datasets. So §7.4's concern is confirmed as a
  *discoverability* problem, not an automation dead end — the earlier plan to
  log kV as unreachable is superseded.
- **No dataset in the training set can reach a Reconstruct run**, but not
  because of kV. Once voltage is filled in, the remaining gate is always one
  of the other four prerequisites, and it differs per dataset (see the table).
  On `sim_Au` the *only* missing item is the R pixel scale.

#### 9.2.1 Why strain's automatic basis fails — three different causes

The app's error text is the same, but the diagnostics it prints separate the
cases cleanly, and none of them is a wrong computation:

- **`polycrystal_2D_WS2` — starved input.** Median **1.0 peaks per pattern**
  across 16,384 positions, i.e. essentially only the direct beam was accepted.
  The default disk-detection thresholds simply do not transfer to WS₂'s much
  weaker 2D-material diffraction. The app says as much ("spacing or thresholds
  may be too restrictive"). This is a *parameter* problem the user must fix in
  the Bragg panel.
- **`downsample_Si_SiGe_exp` and `Particle_1` — adequate input, ill-conditioned
  whole-scan basis.** Median 12.0 and 16.0 peaks per pattern respectively, 0%
  empty positions. There are plenty of peaks; the whole-scan *average* lattice
  is just not well-conditioned. This is exactly the reference-choice subtlety
  in §4 and §7.6: `strain_01_Si_SiGe.ipynb` picks g₁,g₂ from an unstrained
  reference region, not from the whole scan. The app supports this (Reference →
  "Current real-space ROI", Basis → "Manual g₁ / g₂"), so the capability is
  present — it is the *default* that does not generalize.

The QC run deliberately does **not** tune the thresholds or pick a reference
ROI. Both are scientific judgements a user makes while looking at the data;
a scripted run choosing them would be inventing the analysis rather than
evaluating the app's out-of-the-box path. That is the finding.

#### 9.2.2 Other observations from these runs

- **Origin readiness is stricter than "origin measured".** On
  `downsample_Si_SiGe_exp` (fit RMS 11.66 px, probe 5.03 px) and `Particle_1`
  (RMS 18.29 px, probe 10.6 px) the app measures an origin but reports the row
  as **Missing**, with "exceeds probe radius; recalibrate before quantitative
  use". That is good scientific hygiene — and it is also the hidden reason
  Reconstruct stays disabled on those two, which the Reconstruct task itself
  never explains.
- **`polycrystal_2D_WS2` has no phase model in the app's crystal library.**
  `CrystalModel` ships FCC/BCC/diamond/HCP metals + Si (`CrystalModel.swift:135`);
  WS₂ is hexagonal 2D and absent, so both ACOM and Q-from-crystal are
  unavailable for it. §6 lists WS₂ as an ACOM+strain dataset, so this is a real
  coverage gap rather than a UI issue.
- **`Particle_1` imports its R pixel scale from the file: 49.5 nm/px** — which
  disagrees with the `ss30nm` token in its own filename. The app correctly
  prefers file metadata over the filename (and the harness only types a manual
  R value when the field is still empty), but the discrepancy is worth knowing
  before quoting real-space distances from that dataset.
- **A failed compute leaves a modal sheet that swallows every later click.**
  `AppState.present(error:)` renders SwiftUI's `.alert("Something went wrong")`
  as a window-modal sheet. In `run_2026-07-21_0153` the strain failure left it
  up and the whole rest of that datacube's run was lost. Fixed on the harness
  side (`AXDriver.dismissErrorAlertIfPresent` now finds the sheet, verifies it
  closed, and captures its message into the log) — but a user hits the same
  wall, just interactively.
- **Mechanical note (runner flakiness).** One `run.sh` invocation died with
  *"Failed to initialize for UI testing … Timed out while enabling automation
  mode"* before launching the app, and the identical rerun passed. `run.sh`
  ad-hoc re-signs the runner on every invocation, which changes its code
  identity and can invalidate the Accessibility (TCC) grant. If it recurs,
  rerun once before debugging anything; if it persists, re-grant Accessibility
  to the driving process in System Settings → Privacy & Security.
- **Mechanical note (test-only).** Controls with no accessibility identifier
  are still reachable: locate the visible row label and take the control on the
  same row (`AXDriver.control(_:inRowWithLabel:)`). This is how kV, the Strain
  Reference/Basis/Component pickers, and the strain diagnostic read-outs are
  now driven and logged, with no change to app code.

### 9.3 Full fan-out: one run, every dataset (2026-08-03)

A single no-argument `tools/ui-qc-playthrough/run.sh` drove all four training
datacubes back to back: **`References/training_runs/run_2026-08-03_1404/`**,
**30 m 22 s, 0 test failures**, every datacube with its own folder of
screenshots, PNG exports and `log.md`. Datasets are processed in
case-insensitive filename order, each in a freshly launched app.

| Dataset | Wall clock | Screens | Exports | Outcome |
|---------|-----------|---------|---------|---------|
| `downsample_Si_SiGe_exp` (1.2 GB) | 9 m 05 s | 8 | 4 | virtual DF, DPC, 123,885 disks, Q = 0.0372 Å⁻¹/px, ACOM 232 pos · strain ⛔, reconstruct ⛔ |
| `Particle_1…300kV` (253 MB) | 8 m 12 s | 6 | 3 | virtual DF, DPC, 42,734 disks · no phase model → no ACOM/Q · strain ⛔, reconstruct ⛔ |
| `polycrystal_2D_WS2` (1.0 GB) | 8 m 14 s | 6 | 3 | virtual DF, DPC, 16,384 disks · no WS₂ model → no ACOM/Q · strain ⛔, reconstruct ⛔ |
| `sim_Au_data_all_binned` (501 MB) | 4 m 46 s | 9 | 5 | **complete**: virtual DF, DPC, 103,657 disks, Q = 0.0198 Å⁻¹/px, ACOM 525 pos, **strain ε_xx** · reconstruct ⛔ |

**Robustness holds at scale — this is the load-bearing result.** Three of the
four datacubes hit a genuine app-side failure (strain non-convergence, each
raising the modal "Something went wrong" sheet), and in every case the harness
logged it, dismissed the sheet, carried on to the Reconstruct step, wrote that
datacube's `log.md`, terminated the app and moved to the next file. The suite
reports 0 failures because a *logged, non-throwing* skip is the designed
outcome for an app-side gate; a thrown step would still be captured per
datacube (`ERROR_state.png` + `failedDatacubes`) without aborting the run.

**Every number reproduced the §9.2 standalone runs exactly** — same peak counts
(123,885 / 42,734 / 16,384 / 103,657), same Q pixel sizes, same ACOM position
counts, same strain diagnostics (52% indexed, RMS 1.06 px, κ 4.78, 3,853/4,365
reference inliers), same median peaks-per-pattern in each failure. Running the
datasets together rather than one at a time changed nothing, so the §9.2
findings are not artefacts of how the harness was invoked.

**Routing.** Each log now opens with a `## Routing` section naming the pipeline
§6 assigns to that dataset and the steps the run will attempt. Routing is by
*capability gate*, not a per-file script: every dataset is offered the full
pipeline and each step self-gates on what the app actually has (a phase model
for ACOM, Bragg vectors for strain, the five calibration prerequisites for
reconstruct). A skipped step is therefore always a recorded finding about the
app or the data — never a routing choice made to avoid an awkward result.

**Nothing new broke, and nothing new was learned about the app** beyond §9.2 —
which is itself the point of this task: the harness is now a repeatable
whole-suite acceptance run, so a future UI change can be measured against this
exact baseline.

### 9.4 ACOM rounded out: full-scan + IPF·Z (`sim_Au`, 2026-08-03)

§9.1's ACOM ran at **Preview** scope and exported the **Reliability** map. The
harness now also runs the full scan and captures the IPF-colored orientation —
the display py4DSTEM's `plot_orientation_maps` leads with (§3.5). Run:
`References/training_runs/run_2026-08-03_1459/`, **0 errors**, all three ACOM
products exported (`orientation_map.png`, `orientation_map_full_scan.png`,
`orientation_map_ipf_z.png`).

| Step | Scope | Work | Result |
|------|-------|------|--------|
| 6 | Preview | 525 positions | `ACOM preview ✓ · Physical · 0.1 s` |
| 6c | **Full scan** | **8,400 positions × 200 templates** | `ACOM full ✓ · Physical · 0.7 s` |
| 6d | (re-render) | — | `ACOM · IPF · Z`, Categorical, cubic IPF legend |

**Full-scan ACOM is not slow — it is essentially free here.** The task brief
budgeted ≥600 s; the whole 84 × 100 scan matched against 200 templates in
**0.7 s** (the panel's own estimate said "about 2 s"). Preview scope samples at
most 32 × 32 positions to keep an interactive feel, but on a dataset this size
that caution costs the user the full-resolution map for no meaningful wait. The
generous timeout stays in the harness for larger scans, but §9.1's "the run used
Preview scope" is a *default* worth revisiting, not a performance constraint.

**Both controls were reachable without touching app code.**
- `acom.scope` is a `.segmented` Picker, so its selection is not readable as
  text — but its segments are individually clickable by visible label
  ("Preview" / "Region" / "Full scan"). The switch is confirmed by the panel's
  own Work read-out jumping 525 → 8,400 positions *before* the run, and by the
  result afterwards.
- The **display-mode picker has no accessibility identifier** and its label
  ("Display") collides with a sidebar section header — so it was located by the
  option it was *currently showing* ("Reliability"), which is unique in the
  window. So this is a discoverability finding, not an automation dead end —
  the same conclusion §9.2 reached for the kV field. No identifier was added
  (eval-only).

**A full-scan result title carries no scope qualifier.** Preview publishes
"ACOM preview · Reliability", full scan publishes plain "ACOM · Reliability"
(`Support/ResultExport.swift:901`); the export *kind* likewise drops the
qualifier only for full scan. Consequences worth knowing:
- Any wait keyed on "ACOM" alone silently matches the *previous* preview result
  and reports success before the new run starts. The harness now waits for a
  title containing "ACOM" **and not** "preview".
- For a reader, "ACOM · Reliability" is the *less* qualified label for the
  *more* complete result — the full-resolution map is the one whose title says
  least about how it was produced.

**Switching display does not recompute.** `acomDisplay`'s `didSet` calls
`applyACOMDisplay()`, which re-renders the cached `orientationMap` — IPF·Z
swaps `resultImage` for `resultRGBA` (`App/AppState.swift:3383`). So the status
bar still shows the previous step's message while the result title and the
exported product are already IPF·Z. Cheap and correct, but it means the status
bar is not a reliable signal that a display change landed — the result title is.

## 10. The closed evaluation loop (the intended workflow)

The goal is one loop: **run py4DSTEM's canonical workflow on a dataset →
replicate it in mac4DSTEM → quantify the deviation → feed that into a better
UI → repeat.** Today that loop is realized by two tracks that both exist but
are **not yet joined**:

| Half | Track | What it produces | Level |
|------|-------|------------------|-------|
| Replicate + check deviation | `tools/training-dataset-campaign/` (`run.sh`, `main.swift`, `verify_py4dstem.py`) | mac4DSTEM Core results on each dataset, read back through py4DSTEM for parity/interop | **headless, algorithm-level** |
| Use it to improve the UI | QC playthrough (`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/`) | screenshots, per-datacube logs, exported maps; friction → `docs/open-items.md` | **visible, workflow-level** |

**The wire that joins them** (added 2026-08-04, ui-implementation-prompts.md
Prompt A): the campaign now exports, per dataset, the exact arrays the app
produced for the products a user actually looks at — the strain map and the
full-scan ACOM orientation map — alongside the Bragg vectors they were
computed from (`<stem>.parity_input.json` next to the EMD sidecar).
`tools/training-dataset-campaign/parity_py4dstem.py` recomputes the same
products with py4DSTEM's own code from the same Bragg vectors and writes one
machine-readable parity record per dataset+product to
`References/parity_records/latest/` (`{dataset, product, metrics, tolerance,
tolerance_basis, pass}`; `pass: null` marks a recorded non-comparable, e.g. a
dataset with no phase model). The comparisons are designed to isolate blame:
strain feeds py4DSTEM the app's own basis so the record measures the
index/fit/tensor port, with reference-selection deviation reported separately;
ACOM lets py4DSTEM build its own template bank and measures cubic-symmetry
misorientation, since the two implementations sample orientation space
differently by design. Tolerances are recorded first proposals — each record
carries its `tolerance_basis` string. The QC playthrough cites the matching
record in its per-datacube `log.md` right after the strain and full-scan ACOM
exports (`mac4DSTEMUITests/Support/ParityRecords.swift`), so a UI finding now
reads "this step is confusing *and* its output agrees/disagrees with py4DSTEM
by this much." A failing record is a finding to report, never a tolerance to
widen. The campaign (and with it the parity step) is run explicitly via
`tools/training-dataset-campaign/run.sh`, which fails on a failing record
unless `MAC4DSTEM_PARITY_REPORT_ONLY=1`; it is deliberately not part of
`tools/run-tests.sh scientific` (real-data runtime).

**First records (2026-08-04, all four datasets):** sim_Au strain **PASS**
(estimator-matched, ~2e-4 median per component; the unmatched-estimator
weighting DEVIATION is ~5e-3 median, documented in
`Core/Analysis/StrainMapping.swift`). sim_Au ACOM **FAIL** — 8.0° median
misorientation vs py4DSTEM; Si_SiGe ACOM **FAIL** harder (40° median). Also
recorded: the app's ACOM reliability (1 − second/best) is ≈0 at nearly every
position and cannot rank confidence. WS2 and Particle_1 have no phase model →
recorded non-comparable. **The ACOM numbers in this paragraph are superseded
by §10.1 — the comparator that produced them was itself wrong.**

### 10.1 The comparator was wrong, and so was the app (2026-08-04, later)

Before trusting the numbers above, the comparator was checked on its own.
Two defects, one in the instrument and one in the app.

**Instrument.** `misorientation_deg` inserted the symmetry operator between
the two matrices (`A @ op @ B.T`), which minimises over LAB-side operators.
Both codebases store orientation matrices with *columns = lab axes in crystal
coordinates* (py4DSTEM `crystal_ACOM.py:762` uses `M.T @ g_vec_all`), so
symmetry is a crystal-axis relabelling and acts on the **left**. The shipped
metric was therefore invariant under the lab-frame difference it existed to
measure and sensitive to the relabelling it was supposed to absorb — exactly
backwards. `tools/training-dataset-campaign/test_parity_metric.py` pins this:
relabelling moved the old metric by up to 51°, while a genuine frame change
moved it by 0°. The `lab_swap`-on-the-left "fix" was a no-op for a correct
metric (that matrix *is* a cubic symmetry operator), and it had been tuned on
sim_Au — where py4DSTEM puts every sampled position within 10° of one
orientation, so the region is a single grain and *any* constant frame map fits.
The correct map is derived, not fitted: `M_app = M_py @ P`, a right
multiplication. The metric is now gated by `tools/run-tests.sh scientific`.

**App.** Correcting the metric did not rescue the app: over the entire
plausible lab-frame family (in-plane rotation × handedness) the best sim_Au
median was 8.9° and Si_SiGe stayed ~39°. So the divergence was real. It was
then localised against ground truth — patterns synthesised from *known*
orientations with py4DSTEM's own forward model, matched by both
implementations (`tools/acom-groundtruth/`):

- The app's **zone axis was fine** (3.15° median, vs py4DSTEM 1.45°, on a
  96-template bank whose sampling is ~2–3°). The error was almost entirely
  **in-plane**, and bimodal: 0° or ±180°, i.e. a coin flip.
- Cause, provable from the source and confirmed to machine precision: the plan
  used a flat Ewald sphere, `sg = g·n`, which is **odd** under g → −g while its
  Gaussian weight is **even**. Every template came out exactly π-periodic in
  azimuth (measured asymmetry `0.000e+00` for all 96), so the azimuthal
  correlation had two identical maxima 180° apart and the argmax had nothing
  to choose between them. This is one cause with two symptoms: it is also why
  the reliability metric is ≈0 — though bank density contributes too, since
  reliability is still only ~0.03 even at 8.5° template spacing.
- Adding the curvature (`sg = g·n + λ|g|²/2`) breaks the periodicity but on its
  own does **not** fix the match: with raw intensities the brightest ring
  dominates the correlation and swamps the asymmetry. py4DSTEM's
  `power_intensity = 0.25` is what makes it visible. That exponent is **read
  from py4DSTEM's source, not fitted**: `crystal_ACOM.py` declares
  `power_intensity: float = 0.25` (line 33, templates) and
  `power_intensity_experiment: float = 0.25` (line 34, experimental image) as
  `orientation_plan`'s defaults, applied at lines 809/816 and 1062. Note the
  same signature carries `power_radial: float = 1.0` (line 32), an outer-shell
  up-weighting the app does **not** implement — an un-ported deviation, so far
  untested. Both of the changes below are needed:

  | plan | π-asym | zone axis | full orientation |
  |------|--------|-----------|------------------|
  | flat, power 1 (as shipped) | 0.000 | 3.15° | **23.7°** |
  | flat, power 0.25 | 0.000 | 2.10° | 14.5° |
  | curved, power 1 | 0.282 | 3.09° | 26.3° |
  | **curved, power 0.25** | 0.206 | **2.10°** | **3.05°** |
  | py4DSTEM control | — | 1.45° | 1.16° |

Both changes are now in `Core/Crystal/OrientationPlan.swift` (see the
`DEVIATION (sign)` note — py4DSTEM's lab z is the negative of this plan's zone
axis, so the curvature term's sign differs between the two forms) and threaded
from `AppState` and the campaign, which pass the beam wavelength.

**Re-measured on real data:** sim_Au ACOM 8.0° → **5.21°** median, and the
app's match score rose from 0.087 to 0.453 — still FAIL at that point. The
residual was the radial representation, resolved in §10.2.

**Si_SiGe is not a valid ACOM comparison.** py4DSTEM's own map on this dataset
is spatially incoherent — adjacent scan positions disagree by 39.6° median,
against a ~40° random baseline for cubic — and stays that way when its
template bank is widened from 1.2 to 2.0 Å⁻¹ so that all peaks fall inside it.
Grains are far larger than a scan step, so the reference is not resolving the
microstructure here; this is py4DSTEM's *strain* tutorial specimen and ACOM is
not a workflow its own notebooks run on it. The comparator now measures
neighbour coherence on both sides and records the dataset as **not comparable**
rather than reporting an app failure. The previous "Si_SiGe FAILs harder"
reading blamed the app for the reference's noise.

### 10.2 Radial representation, reliability, and the first ACOM PASS (2026-08-04)

**The radial hypothesis from §10.1, tested and confirmed.** The app deposited
each peak into its single nearest radial bin (width kMax/32 ≈ 0.0375 Å⁻¹);
py4DSTEM convolves with a Gaussian of `corr_kernel_size` = 0.08 Å⁻¹. This is
invisible on synthetic peaks — they land at exactly the radii the templates
were built from, so template and pattern round into the same bin — which is
why §10.1's synthetic result was already 3.05°. It is only testable with
radial error injected, so `tools/acom-groundtruth/` was driven with two kinds,
both real: per-peak jitter (disk-fit noise) and a systematic scale error (the
Q calibration is estimated from the first ring). Everything else held fixed;
the only variable is the deposition kernel. Full-orientation median error:

  | radial error | nearest-bin (as shipped) | 0.08 Å⁻¹ kernel |
  |---|---|---|
  | none | 3.05° (score 0.925) | 3.05° (score 0.936) |
  | 0.5% scale | **32.07°** (score 0.810) | 3.05° (score 0.935) |
  | 1% scale | 30.40° (score 0.737) | 3.05° (score 0.933) |
  | 2% scale | 34.45° (score 0.490) | 3.05° (score 0.928) |
  | 4% scale | 40.95° (score 0.223) | 3.05° (score 0.910) |
  | 0.01 Å⁻¹ jitter | 24.86° | 3.05° |
  | 0.04 Å⁻¹ jitter | 30.75° | 2.98° |

**Half a percent** of Q-calibration error — 0.13 of a bin at 1 Å⁻¹ — was
enough to take the app from 3° to 32°. The kernel is flat across the entire
sweep. That also explains the real-data score of 0.453 against 0.925 on
synthetic. `OrientationPlan.buildPolar` now spreads each spot over the
neighbouring shells by its true unrounded radius, defaulting to py4DSTEM's
0.08 Å⁻¹; pinned by `testPeaksSurviveRadialErrorSmallerThanABin`.

**Reliability now ranks.** `1 − second/best` was measured against the best of
*all* other templates, which on any dense bank is the winner's own neighbour a
couple of degrees away — near-identical by construction. The runner-up is now
the best template at least 10° away in zone axis, matching py4DSTEM's
`min_angle_between_matches_deg` rule in `match_single_pattern`. A confidence
measure's job is to *rank*, so it was scored on a population with a real
spread of quality (clean / starved of peaks / polluted with spurious peaks /
radial error):

  | | old (any template) | new (≥10° away) |
  |---|---|---|
  | range | 0.001–0.161 | 0.001–0.457 |
  | Spearman vs error | −0.069 | −0.291 |
  | top-quartile error | 2.30° | **2.25°** |
  | bottom-quartile error | 4.45° | **30.99°** |

The old metric barely separated the best quarter from the worst and ranked
*spurious* patterns above clean ones (0.052 vs 0.022). On real sim_Au the new
metric has median 0.327 (was ~0.02), Spearman −0.47 against measured error,
and its top half is 1.93° vs 3.48° for the bottom half — recorded per dataset
as `app_reliability_*`. The comparator still picks the confident subset with
py4DSTEM's correlation, not the app's reliability, so the app cannot select
the answers it is graded on.

**All four datasets, one run (stride 4).** `sim_Au` ACOM **PASS** — 2.14°
median, 98.5% within 5°, p90 3.69°, against the 3° / 80% tolerance; the app's
neighbour coherence is 2.81° against py4DSTEM's 1.68°. This is the first ACOM
PASS. `sim_Au` strain **PASS** (~2e-4 median per component, unchanged).
`Si_SiGe` ACOM **not comparable** — py4DSTEM's own map is spatially incoherent
there (§10.1). `WS2` and `Particle_1` ACOM **not comparable** — neither has a
phase model (`manifest.json` sets `phaseModelID: null`), so the app does not
compute ACOM at all; for WS2 that is the ROADMAP P1.3 rule working as intended
(no validated hexagonal WS₂ model exists, and the app must reject rather than
infer), and Particle_1's material is genuinely unknown.

**Open, and not an ACOM problem:** strain is `not comparable` on three of four
datasets because the app produced no strain map — the campaign reports "No
sufficiently supported, well-conditioned lattice basis was found" for
`Si_SiGe`, `WS2` and `Particle_1`. Si_SiGe is py4DSTEM's *strain* tutorial
specimen, so the app failing to find a lattice basis there is a real gap in
the strain prerequisite chain, untested and unexplained so far. All three also
carry "Origin fit RMS exceeds the fitted probe radius", which is the more
likely upstream cause.

### 10.3 The strain blocker was the disk-spacing default — and that is only half of it (2026-08-04)

**§10.2's attribution above is wrong and is left in place only as the record of
what was believed.** "Origin fit RMS exceeds the fitted probe radius" is not
what blocked strain: the release owner produced a clean, physically sensible
SiGe-fin strain map *in the app* on `downsample_Si_SiGe_exp` — 100% indexed,
100% basis support, RMS 0.885 px, κ 4.80 — while that same warning was showing
and the calibration was still marked incomplete.

**What was actually wrong.** `DiskDetectionParams.detectorAdapted` set
`minPeakSpacing = qMin/8`, rescaling py4DSTEM's 60 px default (written for
~512 px patterns) by detector size. Bragg spacing is set by camera length,
voltage and d-spacing; it does not scale with the detector. Measured with the
new `tools/bragg-spacing-probe/` (40 patterns per dataset, each dataset's own
fitted probe radius):

  | dataset | probe r | true nearest-neighbour | qMin/8 gate | % of peaks below the gate |
  |---|---|---|---|---|
  | downsample_Si_SiGe_exp | 5.03 px | **14.9 px** | 16 px | **96.9%** |
  | Particle_1…bin8 | 10.6 px | **12.7 px** | 16 px | **94.4%** |
  | sim_Au_data_all_binned | 6.1 px | 21.4 px | 16 px | 0.0% |
  | polycrystal_2D_WS2 | 1.86 px | n/a — 1 peak/pattern | 16 px | n/a |

On the first two the gate sits *above* the lattice, so it suppresses the
shortest g-vectors — exactly the ones that define the strain basis. Isolated
one parameter at a time: correlation smoothing and edge exclusion contribute
nothing; `minPeakSpacing` accounts for the entire effect.

**The fix.** `minPeakSpacing` now derives from the fitted probe radius
(1.0·r) whenever one is known, since this filter exists to stop one disk
producing two maxima, not to enforce a lattice period. 1.5·r and 2.0·r were
measured and rejected — they regress Particle_1, whose disks overlap. Without
a probe radius the old detector-scaled value is retained, which keeps
`tools/disk-correlation-parity`'s recorded 2697-peak baseline valid.

**Clamped to only ever loosen.** The probe-scaled value is capped at the
detector-scaled one. Every training dataset has r < qMin/8, so *only the
loosening direction was ever measured*; a large convergence semi-angle puts r
above that (300 kV / 25 mrad ⇒ r ≈ 60 px on a 128 px detector) where the
unclamped rule would suppress **more** than the value it replaced — and 60 px
sits below the `detectorMinimum / 2` validation warning, so it would have
failed silently at ~1 peak per pattern. Pinned by
`testProbeScaledSpacingNeverExceedsTheDetectorScaledValue`.

**Two caveats on the evidence above, both filed** (backlog #19, #20): the
"true nearest-neighbour" figures are measured through a 10 px gate and so are
floored at 10 px — the medians clear it but the low tail is truncated; and
`Particle_1` may have **no Bragg reflections on its detector at all** (at
α = 0.48 mrad the smallest reachable d-spacing is ~6.8 Å), in which case its
maxima are intra-disk structure and it should not have been used to reject
1.5·r and 2.0·r. The Si_SiGe and sim_Au evidence is unaffected by either.

**Measured effect of the fix (full campaign, all four datasets):**

  | dataset | peaks before | peaks after | strain |
  |---|---|---|---|
  | Si_SiGe | 123,885 | **248,384** | still no map |
  | Particle_1 | — | 71,764 | **now computes** (57.7% indexed, κ 7.9) — parity **FAIL** |
  | sim_Au | 103,657 | 103,657 | PASS, unchanged |
  | WS2 | — | 16,384 | still no map |

`sim_Au`'s strain and ACOM parity records are **bit-identical before and after
— all 47 metrics** — so the one dataset carrying passing records is provably
unaffected.

**What is still unexplained, and matters more than the above.** Si_SiGe strain
*still* fails in the campaign. Re-running the campaign with the release
owner's exact hand-tuned detector settings detects **250,195 peaks — the same
number to the peak as their successful app session** — and the campaign's
strain still returns no basis. So:

- the failure is **not** in disk detection; that input is now identical;
- the app and the campaign call `StrainMapping.compute` the same way, on
  vectors calibrated the same way, with the same `.plane` origin fit, and the
  campaign does fit an ellipse before detection;
- therefore **the campaign harness diverges from the app somewhere in the
  strain path, and that divergence has not been located.**

The consequence is the important part: every previous "app produced no strain
map for this dataset" record was evidence about *the campaign*, not
necessarily about the app. Those records cannot be cited as an app finding
until the divergence is found. Locating it is the next strain task —
`tools/training-dataset-campaign/main.swift` now honours
`MAC4DSTEM_DISK_SIGMA_CC`, `MAC4DSTEM_DISK_MIN_SPACING` and
`MAC4DSTEM_DISK_EDGE` so a hand-tuned session can be reproduced exactly, which
is how the above was established.

**Particle_1 strain now has a real number and it disagrees:** e_xx median
absdiff 0.054 against a 0.001 gate (54×), with `reference_g1_absdiff_px` 0.89.
That dataset has an 18.3 px origin RMS against a 10.6 px probe, so the robust
and median reference bases diverge badly. A measured disagreement is strictly
more information than the previous no-map, but it is a finding to investigate,
not a tolerance to widen.

**How the loop drives v1.0:** each QC prompt (archived — `docs/archive/v1.0/qc-playthrough-prompts.md`)
advances the UI half; `tools/run-tests.sh scientific` + the campaign advance
the parity half; a finished v1 is *both halves green* + the
`docs/open-items.md` cleared + release-owner signing. Doing real
science = running the calibrated pipelines (e.g. the physical-scale ACOM in
§9.1) on your data and trusting the numbers because the parity half backs them.

## Appendix: source notebooks consulted

`basics_00_load_and_preprocess`, `basics_01_visualization_and_virtualimaging`,
`basics_02_diskdetection`, `basics_03_calibration`, `basics_04_strain`,
`dpc_01`, `parallax_01`, `parallax_02`, `ptychography_01`,
`orientation_01_AuAgPd_wire`, `orient_strain_01_WS2`, `strain_01_Si_SiGe`
(all under `References/py4DSTEM_tutorials-main/notebooks/`, current versions
v0.14.8–0.14.19). The `_00` notebooks in the DPC/parallax series are data
*simulation* only, not analysis.
