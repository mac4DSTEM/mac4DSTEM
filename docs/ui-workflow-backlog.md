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

---

## Recommended first three

1. **#1 ACOM prerequisite gating** — highest user-impact; the exact thing that
   silently produced nothing in early runs.
2. **#2 Surface "Calibrate Q from Selected Material"** — turns a hidden,
   gated action into the obvious path; directly unlocks physical ACOM.
3. **#4 Group tasks by prerequisite** — cheap presentation change that makes
   the whole Bragg-vs-phase-contrast structure legible.

These three are mostly presentation + light gating, low risk, and together
they resolve the "I clicked the button and nothing happened" class of
problem. Details below.

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

**Finding (§7.4):** DPC, parallax, and ptychography all require the beam
energy (py4DSTEM passes it straight into each constructor). In the app the kV
field only exists under Reconstruct → Ptychography and has no accessibility
identifier, so it's hard to find and unreachable to three pipelines that need
it.

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

## #5 — Make the strain reference choice explicit  ·  Priority: MED-LOW  ·  Layer: UI  ·  Effort: S

**Finding (§4, §7.6):** "zero strain" is defined by the reference lattice
vectors g1,g2, which can come from the whole-scan average, a chosen ROI, or
manual specification. This choice materially changes the result and should be
a visible, deliberate decision in the strain task.

**Change:** in the Strain task controls, expose the reference source as an
explicit selector with a one-line explanation of what each option means for
the result.

**Files:** the strain task's controls (in `UI/`), `App/AppState.swift`
(strain reference state).

**Core untouched:** yes — surfaces an existing option.

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

## How to validate any of these

Re-run the QC playthrough (`tools/ui-qc-playthrough/run.sh`) after a change:
a pipeline that the scripted run can complete with *fewer* explicit
navigation/prerequisite steps is, by construction, one a new user can
complete more easily. The harness is the acceptance test for this backlog.
