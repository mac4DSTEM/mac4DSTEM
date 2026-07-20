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
4. **Re-run this QC playthrough as the acceptance check** for each UI change —
   a workflow that a scripted run can complete without hand-holding is, by
   construction, one a new user can complete too.

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

## 10. The closed evaluation loop (the intended workflow)

The goal is one loop: **run py4DSTEM's canonical workflow on a dataset →
replicate it in mac4DSTEM → quantify the deviation → feed that into a better
UI → repeat.** Today that loop is realized by two tracks that both exist but
are **not yet joined**:

| Half | Track | What it produces | Level |
|------|-------|------------------|-------|
| Replicate + check deviation | `tools/training-dataset-campaign/` (`run.sh`, `main.swift`, `verify_py4dstem.py`) | mac4DSTEM Core results on each dataset, read back through py4DSTEM for parity/interop | **headless, algorithm-level** |
| Use it to improve the UI | QC playthrough (`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/`) | screenshots, per-datacube logs, exported maps; friction → `docs/ui-workflow-backlog.md` | **visible, workflow-level** |

**The missing wire:** the UI playthrough does not itself diff against
py4DSTEM, and the campaign's deviation numbers don't attach to UI findings.
Closing the loop means letting a UI-QC run cite the parity result for the
same dataset — so a UI finding reads "this step is confusing *and* its output
is within/without X% of py4DSTEM." Until then, treat them as two evidence
streams that a human joins.

**How the loop drives v1.0:** each QC prompt (`docs/qc-playthrough-prompts.md`)
advances the UI half; `tools/run-tests.sh scientific` + the campaign advance
the parity half; a finished v1 is *both halves green* + the
`docs/ui-workflow-backlog.md` items closed + release-owner signing. Doing real
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
