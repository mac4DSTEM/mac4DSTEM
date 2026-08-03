# mac4DSTEM UI / Workflow Backlog

Ranked, actionable changes derived from evaluating the app against the
canonical py4DSTEM pipelines (see `docs/py4dstem-pipelines.md` §7–§9). Every
item is a **workflow-layer or presentation-layer** change — the scientific
core in `Core/` is untouched, and each item says so explicitly.

**Layer key:** `UI` = SwiftUI views only (`mac4DSTEM/UI/`). `WF` = workflow
state/sequencing (`mac4DSTEM/App/AppState.swift`,
`mac4DSTEM/App/ProductWorkflow.swift`). No item touches `Core/`.

**Evidence base:** the clean `sim_Au` run (§9.1 of the pipelines doc) plus
the earlier failed runs. The failures were all in the *test automation*, but
each one mapped to a place where a real user would also have to "just know"
the right next move — which is what this backlog fixes.

**Updated 2026-08-03** with §9.2 — the strain / DPC / Reconstruct runs across
all four training datasets. Those runs turned several §7 hypotheses into
measured facts and added items #7–#11. The headline: DPC works everywhere with
no prerequisites, strain works on `sim_Au` with the app's defaults and fails on
the other three *for three different reasons the UI does not distinguish*, and
no dataset can reach a Reconstruct run — each blocked by a different missing
prerequisite that the Reconstruct task never names.

---

## Recommended first three

1. **#7 Reconstruct prerequisite checklist** — a disabled button with no
   explanation, on 4/4 datasets. The single largest dead end measured so far.
2. **#5 Make the strain reference/basis choice explicit** — promoted from
   MED-LOW on new evidence: the automatic whole-scan basis is the *only* thing
   standing between three datasets and a strain map, and the app already has
   the controls that would fix it.
3. **#1 ACOM prerequisite gating** — same pattern as #7, still unfixed, and
   the thing that silently produced nothing in the earliest runs.

All three are the same class of problem — *the app knows exactly what is
missing and doesn't say so* — and all three are gating/labelling work over
compute that already behaves correctly. Details below.

---

## #1 — Gate & sign-post ACOM's prerequisites  ·  Priority: HIGH  ·  Layer: WF + UI  ·  Effort: M

**Finding (§7.3):** ACOM needs (a) detected Bragg disks and (b) a chosen
crystal phase model. Today the ACOM primary action is clickable before either
exists, so it runs and produces nothing (this caused the first round of QC
failures). Nothing tells the user what's missing.

**Change:** give ACOM the same *readiness checklist* pattern the Prepare
workspace already uses (`UI/CalibrationReadinessView.swift` is the template).
Show a short prerequisite list under the ACOM task — "Detect Bragg disks",
"Choose a phase model" — each with a ✓/✗ and a direct action button, and
disable/annotate the primary action until they're satisfied.

**Files:** `App/ProductWorkflow.swift` (`prerequisites(for:.acom,…)` likely
already computes some of this — surface it), `UI/ACOMControlsView.swift`
(render the checklist; it already has a `prerequisiteStatus` view to build
on).

**Core untouched:** yes — this only reads existing state
(`hasCurrentBraggVectors`, `resolvedACOMModel`) and gates a button.

---

## #2 — Make "Calibrate Q from Selected Material" the obvious path  ·  Priority: HIGH  ·  Layer: UI  ·  Effort: S

**Finding (§7.2, §9.1):** for a known standard (e.g. gold), the canonical way
to get the Q pixel size is matching detected peaks to the crystal's structure
factors. The app does exactly this and reproduces the tutorial value
(0.0198 Å⁻¹/px) — but the action (`calibration.action.qCrystal`) only appears
*after* disks + a phase model exist, and sits beside a manual-entry field
that reads as the primary option. Early runs therefore mislabelled the data
"UNCALIBRATED" when Q was fully recoverable.

**Change:** in the Q pixel-scale readiness row, when a phase model is
available, present "Calibrate from selected material" as the primary, visually
dominant action, with manual entry as the secondary/fallback. When it's *not*
yet available, show the one-line reason ("detect disks and choose a phase
model to calibrate Q from a known crystal") instead of leading with manual
entry.

**Files:** `UI/CalibrationReadinessView.swift` (the `qScale` case of
`readinessAction`).

**Core untouched:** yes — presentation reordering of existing controls.

---

## #3 — Give accelerating voltage a first-class home  ·  Priority: MED  ·  Layer: UI + WF  ·  Effort: M

**Finding (§7.4, refined by §9.2):** DPC, parallax, and ptychography all
require the beam energy (py4DSTEM passes it straight into each constructor).
In the app the kV field only exists under Reconstruct → Ptychography and has
no accessibility identifier, so it is hard to find from the two other tasks
that need it. Two corrections from the measured runs: the field **is** usable
(the QC harness now locates it by its "Voltage" row label and typed 200/300 kV
into it on all four datasets), and DPC's *default* display mode — magnitude in
detector pixels — needs no voltage at all, so DPC is not actually blocked by
this. The problem is discoverability, not reachability.

**Change:** surface accelerating voltage in a shared setup/calibration
surface (e.g. the Prepare workspace or the dataset inspector), auto-populated
from file metadata when present (the app already imports
`accelerating_voltage`), and add an accessibility identifier so it's testable.
The per-task copy can still show it where relevant.

**Files:** `UI/ContentView.swift` (the voltage field lives ~L341–353),
`UI/CalibrationReadinessView.swift` or `UI/DatasetInspector.swift` (new home),
`App/AppState.swift` (`acceleratingVoltage`, `setManualAcceleratingVoltage`
already exist).

**Core untouched:** yes — moves/duplicates an existing input; no compute
change. (Note: adding the a11y identifier is an app-code change, so it is
*out of scope for the eval-only test work* and belongs to this UI effort.)

---

## #4 — Group tasks by prerequisite (Bragg path vs phase-contrast path)  ·  Priority: MED  ·  Layer: UI  ·  Effort: S

**Finding (§7.5):** two families of analysis have very different
prerequisites: the **Bragg-vector path** (Disks → ACOM/Strain) needs disk
detection + crystal calibration; the **phase-contrast path** (DPC / parallax /
ptychography) needs only energy + geometry, no disks. The app currently
interleaves them across Image / Map / Reconstruct, so the shared "you need
Bragg vectors first" dependency isn't visible.

**Change:** within the existing task lists, visually group or label tasks by
their prerequisite family, and show the shared prerequisite once per group
(e.g. a "requires Bragg vectors" header over Disks/Strain/ACOM). This is a
labelling/grouping change, not a re-ordering of workspaces.

**Files:** `UI/ContentView.swift` (task list rendering, the `task.\(mode.id)`
buttons).

**Core untouched:** yes — pure presentation.

---

## #5 — Make the strain reference/basis choice explicit  ·  Priority: HIGH  ·  Layer: UI  ·  Effort: S-M

*(Promoted from MED-LOW on the §9.2 evidence.)*

**Finding (§4, §7.6, §9.2.1):** "zero strain" is defined by the reference
lattice vectors g₁,g₂, which can come from the whole-scan average, a chosen
ROI, or manual specification. Measured outcome: with the defaults (whole-scan
mean + automatic basis) strain succeeds on `sim_Au` and fails on
`downsample_Si_SiGe_exp`, `Particle_1` and `polycrystal_2D_WS2`. On the first
two the input is fine — median 12 and 16 peaks per pattern, 0% empty — it is
the *whole-scan average* lattice that is ill-conditioned. py4DSTEM's own
`strain_01_Si_SiGe.ipynb` picks g₁,g₂ from an unstrained reference region for
exactly this reason. **The app already has both controls; the default is what
does not generalise.**

**Change:** in the Strain task controls, (a) label the two pickers with what
they mean for the result ("Reference defines zero strain"), (b) when the
automatic basis fails, point the failure text at the *specific* control that
would fix it rather than listing every possibility, and (c) consider making
"Current real-space ROI" the suggested reference whenever the whole-scan fit is
poorly conditioned (the app already computes κ and basis support — it knows).

**Files:** `UI/ContentView.swift` (Strain section, L238–331 — the `Reference`
and `Basis` pickers and the diagnostics rows), `App/AppState.swift`
(`strainReferenceMode`, `strainBasisMode`, the strain failure message).

**Core untouched:** yes — surfaces existing options and re-words an existing
diagnostic. `Core/Analysis/StrainMapping.swift` is unchanged.

**Note for automation:** neither picker has an accessibility identifier. The QC
harness reaches them structurally by row label, so this is not blocking, but
adding identifiers alongside this change would be cheap.

---

## #6 — Optional: in-flow ordering hints  ·  Priority: LOW  ·  Layer: UI  ·  Effort: S

**Finding (§7.1, softened):** the app's Prepare→Map order is valid (it
measures origin independently, unlike py4DSTEM's disks-first requirement), so
no re-ordering is needed. But a light "next step" hint on each workspace
(e.g. after calibration: "→ detect Bragg disks to enable orientation/strain")
would guide first-time users through the dependency chain without changing
structure.

**Explicitly NOT recommended:** re-ordering the top-level workspaces to mirror
py4DSTEM (disks-before-calibrate). That would be the one genuinely disruptive
change, and the app's independent origin measurement makes it unnecessary.

**Core untouched:** yes.

---

## #7 — Tell the Reconstruct task which prerequisite is missing  ·  Priority: HIGH  ·  Layer: UI (+ light WF)  ·  Effort: S-M

**Finding (§9.2):** `ProductWorkflow.prerequisites(for: .ptychography)` requires
five things — fitted origin, R–Q rotation, Q pixel scale, R pixel scale,
accelerating voltage. On **all four** training datasets the Reconstruct primary
action rendered as a disabled "Prepare Preview" with no on-screen explanation,
and the missing item was different every time:

| Dataset | Missing |
|---------|---------|
| `sim_Au` | R pixel scale *only* |
| `polycrystal_2D_WS2` | Q + R pixel scale |
| `downsample_Si_SiGe_exp` | origin (fit RMS exceeds probe radius) + R pixel scale |
| `Particle_1…300kV` | origin (same) + Q pixel scale |

The app *already computes the exact list* — `prerequisites(for:)` returns
strings like "Set the R pixel scale". They are simply not rendered next to the
disabled button. `sim_Au` is the sharpest case: one field away from a
reconstruction, with nothing on screen saying which.

**Change:** render the `prerequisites(for:)` strings under the Reconstruct
primary action as a ✓/✗ checklist, each row linking to the control that
satisfies it (all five live in Prepare or in the Reconstruct panel itself).
Same pattern as `UI/CalibrationReadinessView.swift`, and the same shape as #1
for ACOM — worth doing once, generically, for every task's prerequisites.

**Files:** `UI/ProductWorkspaceViews.swift` (the `workspace.primaryAction`
site), `App/ProductWorkflow.swift` (expose the already-computed list).

**Core untouched:** yes — renders state that is already computed.

---

## #8 — Make the strain failure's "adjust the thresholds" advice actionable  ·  Priority: MED  ·  Layer: UI  ·  Effort: S

**Finding (§9.2.1):** on `polycrystal_2D_WS2`, disk detection "succeeded" with
16,384 peaks over 16,384 scan positions — a **median of 1.0 peaks per pattern**,
i.e. essentially only the direct beam. The default detection thresholds do not
transfer from simulated Au to a 2D material. Nothing at the *disk-detection*
step flags this; the user only finds out later, from a strain failure whose
remedy ("Adjust the thresholds in the Bragg panel or the reference/basis
selection") names two unrelated causes and points at a panel in a different
task.

**Change:** (a) show the peaks-per-pattern median as a quality read-out on the
disk-detection result itself, with a warning when it is ≲2 (the app already
computes this number — it appears in the strain error text); (b) split the
strain failure message so a starved-input failure says *"only ~1 peak per
pattern was detected — lower the detection thresholds"* and an
ill-conditioned-basis failure says *"choose a reference ROI"* (see #5).

**Files:** `UI/DiskDetectionControls.swift` (result read-out),
`App/AppState.swift` (the strain failure message).

**Core untouched:** yes — surfaces a diagnostic the compute already produces.

---

## #9 — A failed compute should not block the whole window  ·  Priority: MED  ·  Layer: UI  ·  Effort: S

**Finding (§9.2.2):** `AppState.present(error:)` shows SwiftUI's
`.alert("Something went wrong")`, which AppKit presents as a **window-modal
sheet**. In `run_2026-07-21_0153` a strain failure left it up and every
subsequent interaction was silently swallowed — the rest of that datacube's run
was lost. The status bar already carries the same message, so the modal buys
nothing but a stop-the-world.

**Change:** demote recoverable compute failures (a strain/ACOM/reconstruct step
that did not converge) to the existing non-blocking status bar + log pane, and
reserve the modal for failures that genuinely invalidate the session (file
read errors). Keep "Copy Details" available from the non-modal surface.

**Files:** `UI/ContentView.swift` (L922–940, the `.alert`),
`App/AppState.swift` (`present(error:)` — distinguish recoverable from fatal).

**Core untouched:** yes — error *presentation* only.

---

## #10 — Surface R pixel scale provenance and conflicts  ·  Priority: LOW-MED  ·  Layer: UI  ·  Effort: S

**Finding (§9.2.2):** R pixel scale is the most common Reconstruct blocker
(3/4 datasets), and it is the one calibration with **no measurement path** in
the app — manual entry only. Meanwhile `Particle_1` imports 49.5 nm/px from
file metadata while its own filename says `ss30nm`. The app's precedence
(file over filename) is right, and the readiness row does say "Imported from
file", but a user reading the filename gets no warning that the two disagree.

**Change:** in the R pixel-scale readiness row, keep the provenance label and
add a one-line note when a scan-step token in the filename disagrees with the
imported value. Where no value exists at all, say plainly that R scale must be
entered by hand from the acquisition parameters — it cannot be measured from
the data.

**Files:** `UI/CalibrationReadinessView.swift` (`rScale` case).

**Core untouched:** yes.

---

## #11 — (Not a UI item) Crystal library has no WS₂  ·  Priority: n/a — scope question  ·  Layer: `Core/Crystal` + scope

**Finding (§9.2.2):** `CrystalModel.library` (`Core/Crystal/CrystalModel.swift:135`)
ships FCC/BCC/HCP metals plus Si (diamond). `polycrystal_2D_WS2` is hexagonal
2D and has no entry, so both ACOM and Q-from-crystal are unavailable for it —
even though §6 lists WS₂ as an ACOM+strain dataset and py4DSTEM's
`orient_strain_01_WS2.ipynb` is a canonical tutorial.

**Logged here only so it is not lost.** It is explicitly **not** a UI/workflow
item, and the bar for closing it is **already set** — `ROADMAP.md` Priority 1.3
names WS₂ specifically: a new phase is admitted only through the generic model
contract, with an explicit lattice, atomic basis, symmetry reduction, structure
factors, an expected-orientation fixture and fit-overlay acceptance; until then
the UI must *reject* it rather than infer it. So this is a roadmap-level
decision (do we invest in that contract for WS₂?), not a backlog item to
schedule, and the app's current behaviour — offering no WS₂ model — is the
**correct** behaviour under that rule, not a defect.

The UI-side sliver that *does* belong here is covered by #1: when no library
model fits the sample, ACOM should say so plainly instead of offering a picker
that cannot help.

---

## #12 — Revisit the ACOM Preview default, and lead with IPF·Z  ·  Priority: MED  ·  Layer: UI (+ light WF)  ·  Effort: S

**Finding (§9.4):** ACOM defaults to **Preview** scope (≤32 × 32 sampled
positions) and to the **Reliability** display. Measured on `sim_Au`: the full
84 × 100 scan against 200 templates completed in **0.7 s** — the app's own
estimate said "about 2 s". The Preview default is protecting the user from a
sub-second wait while costing them the full-resolution map. Meanwhile py4DSTEM's
`plot_orientation_maps` leads with the IPF orientation coloring, not
reliability, so a user following the tutorial has to find a picker to see the
map they came for.

**Change:** (a) when the panel's own work estimate is under a small threshold
(it is already computed and displayed — "Work" / "Expected"), default the scope
to Full scan, or surface a one-click "run the full scan, ~2 s" affordance next
to the estimate; (b) default `acomDisplay` to `.ipfZ` when the map has a
resolved symmetry, with Reliability one click away as the quality check.

**Files:** `UI/ACOMControlsView.swift` (scope + display pickers, the Work /
Expected rows), `App/AppState.swift` (`acomScope`, `acomDisplay` defaults).

**Core untouched:** yes — changes defaults and presentation; the matching code
is unchanged.

**Note for automation:** the display picker has no accessibility identifier and
its "Display" label collides with a sidebar section header. The QC harness
reaches it by its current *value* instead, so this is not blocking — but an
identifier alongside this change is cheap.

---

## #13 — A full-scan ACOM result is the least-labelled one  ·  Priority: LOW-MED  ·  Layer: UI  ·  Effort: S

**Finding (§9.4):** result titles are "ACOM preview · Reliability" for preview
and "ACOM region · …" for a region, but plain **"ACOM · Reliability"** for a
full scan — the qualifier is empty only in the full-scan case
(`Support/ResultExport.swift:901`), and the export `kind` drops it too. So the
most complete, full-resolution product is the one whose label says least about
how it was produced, and preview vs full-scan products are told apart by the
*absence* of a word.

This bit the QC harness concretely: a wait keyed on "ACOM" matched the stale
preview result and reported success before the full-scan run began (fixed
test-side by also requiring "preview" to be absent). A user comparing two
exported PNGs later has the same ambiguity with no fix available.

**Change:** label the scope explicitly in all three cases — "ACOM full scan ·
Reliability" — and carry the same qualifier into the exported `kind`, so
`acom_reliability` becomes unambiguous about scope. This touches saved-product
naming, so check it against session reopen before changing the `kind` string.

**Files:** `Support/ResultExport.swift` (~L899–902, the `qualifier`/`kind`
construction for `.acom`).

**Core untouched:** yes — naming of an existing product. **Caveat:** the `kind`
string is persisted, so changing it is a compatibility question, not purely
cosmetic; the *display name* half is safe on its own and is the higher-value
part.

---

## How to validate any of these

Re-run the QC playthrough (`tools/ui-qc-playthrough/run.sh`) after a change:
a pipeline that the scripted run can complete with *fewer* explicit
navigation/prerequisite steps is, by construction, one a new user can
complete more easily. The harness is the acceptance test for this backlog.

**Baseline to diff against:** `References/training_runs/run_2026-08-03_1404/`
(§9.3) — one no-argument run over all four datasets, 30 m 22 s, 0 failures.
Its numbers reproduced the per-dataset runs exactly, so it is a stable
reference: after a change, re-run with no argument and compare peak counts, Q
pixel sizes, ACOM position counts and strain diagnostics against that folder.
The items most likely to move it are **#5** and **#8** — if either lands, the
three currently-failing strain runs are what should turn green, and a strain
map on `downsample_Si_SiGe_exp` (the canonical py4DSTEM strain dataset) is the
single clearest proof that the change worked.
