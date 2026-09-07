# QC-run findings, 2026-07-21 → 2026-08-04 (archived 2026-09-07, C1)

Verbatim: `docs/py4dstem-pipelines.md` §9 and §10 as they stood until
2026-09-07. Why a new file: no archive file is the QC playthrough's own run
record — `archive/v2/visual-acceptance-checklist-2026-09-03.md` is Track B's
checklist and `archive/2026-09-01-trackb-playthrough.md` is one drive. The
playthrough these runs used was retired 2026-08-17 and its target and
`tools/ui-qc-playthrough/` were deleted; every path below is history. The
lessons that outlived it are in `docs/development-process.md` and
`docs/decisions.md`.

---

## 9. Empirical findings from QC runs so far (history — nothing here runs today)

The QC playthrough was retired 2026-08-17 and its target and
`tools/ui-qc-playthrough/` were deleted; the runs below are records, and the
paths they name no longer exist. The pipeline definitions in §1–§8 stay the
reference.

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

### 9.3 Full fan-out: one run, every dataset (2026-08-03; retired)

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
