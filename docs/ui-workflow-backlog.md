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

## Design-pass items — ✅ DESIGN PASS DONE 2026-08-05

**The pass ran on 2026-08-05.** Design document:
`docs/ui-design-pass-2026-08-05.md` (options weighed, measurements, decisions).
The release owner chose **Option C** for the sidebar/main-pane split, the
**#17a/#17b split**, and the **figure-applies / data-doesn't** export rule. All
four items below are now closed or split — see each entry. The one thing still
open is #16's *trigger*, which needs a human at a trackpad (§6 of the design
doc); its mechanism, its fix and its regression test all landed.

Kept below for the record of what the pass was for:

Most items below are a mechanical fix: reproduce, patch, test, done in one
session. The two marked **[DESIGN PASS]** are different — the release owner
wants these thought through deliberately (what the control should feel like,
how it fits the rest of the workspace) rather than patched reactively. Do not
hand these out as an ordinary implementation prompt; scope a design pass first
(Plan subagent / Opus, weighing 2–3 approaches) before writing code. This
section is the standing place to park a UI idea that isn't ready to execute
yet — add to it rather than starting a new doc.

- **#16** — controls intermittently unresponsive. Reproduction is still
  mechanical (find the trigger, fix the stale state) — but once found, the
  release owner wants the fix considered against *why* the app accumulated
  this kind of state bug at all, not just patched at the one site found.
- **#17** — rotate the real-space image. Scope rationale already written
  below, but on reflection this deserves the same treatment: how rotation
  should compose with every real-space view, the export-provenance question,
  and whether the control family (rotate/flip/whatever else the browser needs)
  should be designed as a set rather than one feature at a time.
- **#21** — the Reconstruct workspace is cramped, and says everything twice.
  See below; found by playthrough 2026-08-05.

## #21 — The Reconstruct workspace is cramped and says everything twice  ·  ✅ Done 2026-08-05

**Costed before it was designed.** Reconstruct with 4 unmet prerequisites
against 0, measured in a real 1470×923 window:

| | 0 unmet | 4 unmet |
|---|---|---|
| Main-pane chrome above the image panes | 208pt | **399pt** |
| Image pane | 646×646 | **516×516** (−36% area) |
| Sidebar document (871pt of column) | 993pt | 1040pt |

So the duplicated list cost **191pt of main pane and 47pt of an already
overflowing sidebar, for the same information twice.**

**Shipped — Option C, "one owner, two densities":**
- **Readiness has exactly one owner, the main pane**, because that is where the
  action it gates lives. `TaskPrerequisiteChecklist` now also owns the
  "ready · limited interpretation" guidance that the sidebar block used to
  show, so nothing moved from being explained twice to not at all.
- **Unmet requirements get a full row with the control that fixes them;
  satisfied ones collapse to one line**, and the whole detail section is
  collapsible with a summary row that still names the task, the count, and the
  first fix.
- **The sidebar carries a per-task ✓/! glyph instead** (`taskButton`), folded
  into the button's own accessibility label — which is strictly *more*
  information than before, since the old block described only the *selected*
  task while sitting in a list of all of them.

**Measured after:** Reconstruct while blocked went **399pt → 231pt** of chrome,
image panes **516² → 646²** (the same size as when nothing is blocked), and the
sidebar **1040pt → 899pt**, cutting the column overflow from 169pt to 28pt.
That last number is also **#16**'s structural fix.

**Deviation from the design doc:** the doc proposed the detail be *expanded on
first arrival and collapsed once seen*. It ships **collapsed by default**,
because expanded-by-default was measured to recover **1pt of the 191** — the
new summary row costs about what the satisfied rows saved, so the whole win is
in the collapsed state. The "explains itself at the action" contract from
Prompt B still holds: the collapsed row names the task, says "3 of 5 missing",
and offers the first unmet item's own action button.

Pinned by `SidebarLayoutTests.testBeingBlockedDoesNotShrinkTheImagePanes` and
`testSidebarDocumentRoughlyFitsItsColumn` — both verified to fail without the
change.

---

### Observed 2026-08-05 — a Reconstruct playthrough, for the design pass

Two screenshots of the **Reconstruct** workspace on `downsample_Si_SiGe_exp`
(reached after a successful strain map: 100% indexed, RMS 0.99 px, κ 4.84).
Concrete material for whoever takes the design pass:

1. **#16 reproduced, with a location.** The first screenshot has the sidebar
   "Prepare" header drawn over the window traffic lights, and the
   prerequisite rows drawn over the "mac4DSTEM" title bar. The second, same
   screen after navigating, lays out correctly. So the symptom is not only
   "buttons go inert" — it is **layout/scroll state**, and Reconstruct is a
   place it happens. Whoever reproduces #16 should start here.

2. **The prerequisite list is on screen twice.** The main pane renders
   "Needed before Parallax & ptychography can run" — all five requirements
   with Ready/Missing and two `Open Prepare` buttons. The sidebar Task section
   simultaneously renders the *missing* subset plus `Go to Prepare`. Neither is
   wrong on its own; together they are most of the vertical space in the
   screenshot and the reason it reads as cramped. This is a consequence of #7's
   checklist being mounted under every primary action while the main pane also
   has one. **The design pass should decide which surface owns this**, rather
   than either being trimmed in isolation.

3. **#4's group label is marginal in single-task workspaces** — my own change,
   flagged here rather than left to rot. Reconstruct has exactly one task, so
   "No Bragg vectors required" sits above a single row. It earns its place in
   Map (three tasks, two families) and is close to noise with one. Candidate
   refinement: only label when a workspace actually contains more than one
   family, or more than one task. Deliberately *not* patched reactively — it
   belongs with the same design pass, since the answer depends on what that
   pass decides about the sidebar's role overall (point 2).

4. **#17's use case is now concrete.** The strain map is 200 × 50 — a wide,
   short strip sitting beside a square 128 × 128 CBED, so most of the result
   pane is empty. Rotating it 90° for *display* would let both panes use their
   space. This is presentation only, "just for the show" in the release owner's
   words — see #17 below for why that still has real constraints (true scan
   indices, scale-bar axis, export provenance).

---

## #1 — Gate & sign-post ACOM's prerequisites  ·  Priority: HIGH  ·  Layer: WF + UI  ·  Effort: M

**✅ CLOSED 2026-08-04** — shipped with #7 as one generic mechanism:
`ProductWorkflow.prerequisiteItems(for:readiness:)` (the legacy string API now
derives from it) + `UI/TaskPrerequisiteChecklist.swift`, mounted under every
task's primary action, each unmet row linking to Prepare / the providing task /
the in-panel control. ACOM's disks + material rows render exactly as this item
asked; nothing was special-cased.

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

## #2 — Make "Calibrate Q from Selected Material" the obvious path  ·  Priority: HIGH  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

**Shipped:** in `CalibrationReadinessChecklist.readinessAction(for:)` (`qScale`
case), when a phase model is resolved the crystal-calibration button now
renders `.borderedProminent` above an "or manual" fallback row; when no phase
model is available the manual field is preceded by a reason that names
whichever half of the two-part prerequisite is actually unmet: "Detect disks
and choose a phase model to calibrate Q from a known crystal." when disks
haven't been detected yet, or "Choose a phase model to calibrate Q from a
known crystal." when disks are already in hand and only the phase model is
missing (fixed post-review — the single generic sentence had been telling
users who'd already detected disks to redo that step). Presentation-only
reorder/branching of existing controls/state, matches the proposal.

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

**✅ CLOSED 2026-08-05** — the identifier/label half shipped and stays; the
VoiceOver runtime half was **deferred to v2.0** by an explicit scope change
(the screen-reader clause was removed from `docs/v1-scope.md`'s "Mac
experience" gate — no current or near-term user needs it). The identifiers are
*not* screen-reader features: they are what XCUITest matches on and what
`AXDriver` depends on, so they must not be removed as part of that deferral.
Procedure parked at `docs/voiceover-verification-checklist.md`. Still open and
unrelated to accessibility: moving the voltage field to a shared
setup/calibration home.

**◐ PARTIAL 2026-08-04** — the accessibility half shipped: the voltage field
now has `calibration.acceleratingVoltage` + a proper accessibility label, the
strain pickers got `strain.reference/basis/component`, the ACOM display picker
got `acom.display` with a disambiguated label, and the strain-diagnostics /
ACOM Work·Expected rows got identifiers. The prerequisite checklist (#7) also
points at the voltage row. Still open: moving the field to a shared
setup/calibration home. (The VoiceOver runtime pass this originally also listed
was deferred to v2.0 on 2026-08-05 — see the header above.)

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

## #4 — Group tasks by prerequisite (Bragg path vs phase-contrast path)  ·  Priority: MED  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

**Shipped:** `TaskPrerequisiteFamily` (`App/ProductWorkflow.swift`) +
`AnalysisMode.prerequisiteFamily`; the sidebar Task section now renders one
light caption per non-empty family before its tasks. Identifiers
`task.group.{producesBragg,requiresBragg,phaseContrast}`.

**Refined 2026-08-05 (design pass).** The caption is now drawn only where a
workspace has **more than one family** — `WorkspaceArea.showsTaskFamilyLabels`
+ `taskFamilyGroups`. Map keeps its captions; **Reconstruct** loses the one that
sat above a single task, and **Image** loses one too. *Deviation from the
release owner's candidate*, which was "more than one family **or** more than
one task": Image has two tasks in one family, and a single caption spanning the
whole list there says exactly as little as it did in Reconstruct, so the
task-count clause would have kept noise for no work done. Keyed on family count
because distinguishing families is the caption's entire job. Pinned by
`testFamilyCaptionsAreDrawnOnlyWhereThereIsMoreThanOneFamily`.

**Deviation from the proposal:** three families, not two. The item suggested a
"requires Bragg vectors" header over Disks/Strain/ACOM, but `.disks` *produces*
the vectors the other two consume — one header spanning Map would be wrong
about the one task that satisfies it. So Disks gets "Produces Bragg vectors",
Strain/ACOM get "Requires Bragg vectors", and the phase-contrast tasks get
"No Bragg vectors required". Pinned by
`testTaskPrerequisiteFamiliesSplitTheBraggDependencyCorrectly`, which also
asserts the grouping neither drops nor duplicates a task in any workspace.

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

> **CORRECTION (2026-08-04).** "The input is fine — median 12 peaks per
> pattern" was wrong, and the "12" was the symptom, not a healthy baseline.
> The detector-scaled `minPeakSpacing` default sat *above* the true Bragg
> spacing on Si_SiGe (16 px gate vs 14.9 px lattice) and Particle_1 (16 vs
> 12.7), suppressing 96.9% and 94.4% of genuine peaks — the shortest
> g-vectors, which are precisely what defines the basis. With the gate fixed
> (pipelines doc §10.3) Si_SiGe detects 248,384 peaks instead of 123,885.
> So the whole-scan *average* was not shown to be the problem; a starved peak
> population was. The reference/basis UI work below still has independent
> value — py4DSTEM really does pick an unstrained ROI for this specimen — but
> it must not be justified by this evidence, and it is **not** the reason
> Si_SiGe produced no strain map.

**✅ CLOSED 2026-08-05 — the reference/basis UI half, all three parts.**

- **(a) The pickers now say what they decide.** A caption under each: Reference
  → "Defines zero strain: …" (worded per mode — whole-scan mean vs the visible
  ROI), Basis → "The g₁ / g₂ pair every position is indexed against."
- **(b) The failure names one control, not two.** `StrainFailureCause`
  classifies the failure before wording it, and each case names exactly one
  remedy. A starved population says *"Only N peaks per pattern were detected …
  lower the detection thresholds in Bragg disks"*; an ill-conditioned lattice
  says *"the peak population is healthy, but no single lattice explains enough
  of it"* and points at the reference. The old text ended "Adjust the
  thresholds in the Bragg panel **or** the reference/basis selection", which
  sent the user to a task that was often not at fault.
- **(c) The suggestion is a button, not prose.** After an ill-conditioned
  failure with the whole-scan reference, the Strain panel offers **"Use the
  current ROI as the reference"** (`strain.remedy.useROI`); after a starved
  failure it offers **"Go to Bragg Disks"** (`strain.remedy.disks`). Cleared on
  success and on dataset activation, so a stale remedy is never shown.

**The classification threshold is stated, not tuned:** a 2D basis needs the
direct beam plus two non-collinear g-vectors, so three peaks is the floor at a
position; a median below **4**, or more than **25%** of positions empty, is a
detection failure whatever the reference is. Pinned by
`StrainFailureCauseTests`, including a sweep asserting the two causes are
mutually exclusive and total.

**Deviation from the item:** it proposed using κ and basis support to decide
when to suggest the ROI. Those are diagnostics of a run that *succeeded* — on
the failure path there is no map and therefore no κ, so the decision is made
from the peak population instead, which is available in both cases and is what
actually distinguishes the two failures.

**Original change proposed:** in the Strain task controls, (a) label the two
pickers with what they mean for the result ("Reference defines zero strain"),
(b) when the automatic basis fails, point the failure text at the *specific*
control that would fix it rather than listing every possibility, and (c)
consider making "Current real-space ROI" the suggested reference whenever the
whole-scan fit is poorly conditioned (the app already computes κ and basis
support — it knows).

**Files:** `UI/ContentView.swift` (Strain section, L238–331 — the `Reference`
and `Basis` pickers and the diagnostics rows), `App/AppState.swift`
(`strainReferenceMode`, `strainBasisMode`, the strain failure message).

**Core untouched:** yes — surfaces existing options and re-words an existing
diagnostic. `Core/Analysis/StrainMapping.swift` is unchanged.

**Note for automation:** neither picker has an accessibility identifier. The QC
harness reaches them structurally by row label, so this is not blocking, but
adding identifiers alongside this change would be cheap.

---

## #6 — Optional: in-flow ordering hints  ·  Priority: LOW  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

**Shipped:** `ProductWorkflow.nextStepHint(for:readiness:calibrationReady:)` —
a pure function alongside the existing `guidance(...)`, not a second
mechanism — rendered as one caption under the Workspace section
(`workspace.nextStepHint`). Prepare → Image/Map, Image → Map, Map → Results.

**Deliberately silent** on three screens, because a hint that repeats what is
already visible is noise: Prepare while calibration is incomplete (the
readiness checklist already names each missing field), Map before disks exist
(**#4**'s group labels already say which tasks need Bragg vectors), and
Results/Reconstruct. That silence is the part most likely to regress, so it is
what `testNextStepHintPointsForwardAndStaysSilentWhereTheUIAlreadyExplains`
asserts. No workspace re-ordering, per the item's explicit "NOT recommended".

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

**✅ CLOSED 2026-08-04** — see #1: one generic checklist serves Reconstruct,
ACOM, strain, and future tasks. Reconstruct now names all five prerequisites
on screen with per-row navigation. Covered by
`ProductWorkflowTests.testPrerequisiteChecklistItemsMatchPrerequisiteStrings`
(legacy strings and checklist provably cannot drift).

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

**✅ CLOSED 2026-08-05.** (a) shipped earlier — the Bragg panel shows
"Per pattern · median N · range lo–hi" with the acceptance funnel beside it.
(b) shipped with **#5**: `StrainFailureCause` splits the message so a starved
population and an ill-conditioned lattice say different things and each offers
one button. See #5 for the threshold and its justification.

**Original change proposed:** (a) show the peaks-per-pattern median as a
quality read-out on the disk-detection result itself, with a warning when it is
≲2 (the app already computes this number — it appears in the strain error
text); (b) split the strain failure message so a starved-input failure says
*"only ~1 peak per pattern was detected — lower the detection thresholds"* and
an ill-conditioned-basis failure says *"choose a reference ROI"* (see #5).

**Files:** `UI/DiskDetectionControls.swift` (result read-out),
`App/AppState.swift` (the strain failure message).

**Core untouched:** yes — surfaces a diagnostic the compute already produces.

---

## #9 — A failed compute should not block the whole window  ·  Priority: MED  ·  Layer: UI  ·  Effort: S

**✅ CLOSED 2026-08-04** — `AppState.presentComputeFailure(_:)` routes 46
compute-step failure sites (strain, ACOM, calibration, DPC, disks, parallax,
ptychography) to the status bar + log pane, non-modally; session/file-level
failures (file open, dataset activation, pattern reads) and export-write
failures deliberately keep the modal. Covered by `ErrorRoutingTests` (3 tests,
including the measured strain scenario).

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

## #10 — Surface R pixel scale provenance and conflicts  ·  Priority: LOW-MED  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

**Shipped:** both halves, in `CalibrationReadinessChecklist`. The `rScale`
action now leads with "R pixel scale cannot be measured from the data — enter
it from the acquisition parameters" above the manual field. The conflict note
is rendered in `readinessRow` rather than `readinessAction`, because an
imported-but-wrong R scale is *ready* — the one state the existing action
branch never draws. `scanStepAngstromPerPixel(inFilename:)` parses an
`ss<number><unit>` token (nm/pm/µm/Å, decimals, case-insensitive, last path
component only) and compares in Å/px at a 5% tolerance, so a unit difference
is not reported as a conflict and an abbreviated token is not flagged for
rounding. Identifier `calibration.rScale.filenameConflict`.

**Deviation from the proposal:** the parser is `internal`, not `private`, so
`mac4DSTEMTests/CalibrationReadinessFilenameTests.swift` (7 cases) can pin the
false-positive guards — the note contradicts a correct imported calibration if
it ever fires wrongly, so `bin2` / `45x90` / `300kV` / `cl-600mm` and
no-token filenames are all asserted to parse as nil.

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

## #12 — Revisit the ACOM Preview default, and lead with IPF·Z  ·  Priority: MED  ·  Layer: UI (+ light WF)  ·  Effort: S  ·  ✅ Done

**Shipped (b) as proposed:** a completed map with a resolved symmetry promotes
`acomDisplay` to `.ipfZ` (`promoteIPFZDisplayIfDefault`). Guarded twice — never
when `map.symmetry == .identity` (no fundamental zone, so an IPF key would be a
fabricated legend), and never over an explicit choice: the picker now routes
through `selectACOMDisplay(_:)`, which records `acomDisplayIsUserChosen`
(a `didSet` cannot tell a human choice from a programmatic default). Reset per
dataset. Pinned by
`testChoosingAnACOMDisplayIsRecordedSoItIsNotLaterOverridden`.

**Shipped (a) as the affordance, NOT the default change** — the item offered
either. Changing the default was rejected: `acomEstimatedDuration` is nil
without a measured throughput or the CPU baseline, so on a fresh GPU session
the app cannot know a full scan is cheap, and the default would only flip
*after* a preview had already been run. Instead `acomFullScanSuggestion`
surfaces a one-click "Run the full scan instead — about N s" button
(`acom.suggestFullScan`) beside the Expected row, offered only from `.preview`,
only when grounded, and only under 5 s. It reuses the existing estimator via a
shared `acomEstimatedDuration(forPositions:)` so the suggestion can never
disagree with the "Expected" row.

**Also:** the display picker's accessibility identifier the item asked for was
already added under **#3**; the label disambiguation is retained.

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

## #13 — A full-scan ACOM result is the least-labelled one  ·  Priority: LOW-MED  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

**Shipped both halves** — display name *and* the persisted `kind`. All three
scopes are now named uniformly: "ACOM full scan · Reliability",
`acom_full_reliability` (previously `acom_reliability`, the only unqualified
spelling).

**The compatibility caveat was real, and it found a live bug.**
`UI/StemImageView.swift` gated the IPF colour-key legend on
`displayedResultKind == "acom_ipf_z"` — exact equality. Adding a scope token
would have removed the legend from full-scan IPF maps, i.e. the exact product
**#12** just promoted to the default. It is now a `contains("ipf_z")` check,
which additionally **fixes a pre-existing bug**: preview and region IPF maps
(`acom_preview_ipf_z`) never matched that equality, so they had never shown a
colour key at all. Substring matching also keeps kinds saved *before* this
change working on reopen.

**Checked, not assumed:** `ACOMRunSemantics.productStatus(for:)` already
matched by substring; `tools/sidecar-result-test/` hardcodes its own
`acom_ipf_z` fixture rather than calling `ResultExport`, so it is unaffected
(confirmed — full `scientific` suite green, 28/28). The QC harness's two waits
still match ("ACOM full scan · Reliability" contains "ACOM", not "preview"), so
its test-side workaround keeps working; it could now assert "full scan"
positively instead, which is left alone because that harness cannot currently
be run to verify (needs Accessibility permission).

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

## #14 — `expand` splits symmetry-equivalent sites at ordinary CIF precision

**Found by:** adversarial review of the CIF point-group check (2026-08-04),
not by the QC playthrough. **Pre-existing** — predates the symmetry work and is
independent of it.

`CIFImport.expand` dedupes symmetry images at a fixed `1e-4` fractional
tolerance (`Core/Crystal/CIFImport.swift`, `expand`). Applied to an asymmetric
unit written to the entirely ordinary **3 decimals**, the generated images miss
each other by more than that, so they are kept as distinct atoms. Magnesium
given as `Mg 0.333 0.667 0.25` plus the real P6₃/mmc operators expands to
**6 Mg sites instead of 2** — three times the atoms in the cell.

**Why it matters:** site multiplicity feeds the kinematic structure factors
directly, so the ACOM template intensities are wrong, silently.
`CrystalModel.validationIssues` has no minimum-interatomic-distance check, so
nothing catches it. Worse, it is spelling-dependent: the *same* structure at
the *same* precision is handled differently depending on whether the CIF lists
a symop loop or the full P1 site list.

**Fix direction:** make the dedup tolerance consistent with
`symmetryPositionTolerance` (5e-3) rather than a separate 1e-4 constant, and
add a minimum-interatomic-distance validation issue so an over-populated cell
is rejected loudly instead of producing quiet nonsense. Needs a fixture in
`tools/cif-symmetry-test/` covering the symop-loop path at 2/3/4 decimals —
the current cases all supply explicit site lists, which is why this was missed.

**Core untouched:** no — this is `Core/Crystal`, and it changes structure
factors. Adversarial review + fixture required.

---

## #15 — `classifyFamily`'s metric tolerance is unreachable

**Found by:** the same review. **Pre-existing**, cosmetic-to-moderate.

`CIFImport.classifyFamily` admits a cubic/hexagonal metric at `1e-3` relative
on lengths and `0.05°` on angles, but `CrystalModel.validationIssues` re-checks
the same metric at `1e-6` relative. Anything in the gap is admitted by the
point-group step and then rejected by model validation with a *different*
message: a cell with a=4.0782, b=4.0812, c=4.0782 reports "Cubic m-3m symmetry
requires a = b = c…" rather than a point-group error naming the real problem.

**Fix direction:** pick one tolerance and use it in both places, or have
`classifyFamily` reject the in-between band itself with a message that names
the offending axis pair. Note this also invalidates the reasoning in the
`symmetryPositionTolerance` doc comment, which cites the 1e-3 metric gate as
upstream justification — 1e-6 is what actually survives, so that comment should
be corrected when this is fixed.

**Core untouched:** no, but low risk — error routing only, no numerics.

---

## #19 — Does `Particle_1` have any Bragg reflections on the detector at all?

**Raised by the adversarial review of the disk-spacing fix, 2026-08-04.
Needs the release owner's acquisition parameters to settle.**

The filename says `alpha=0p48 … cl-600mm … 300kV … bin8`, the detector is
128×128, and the fitted probe radius is 10.6 px. If `alpha` is a convergence
semi-angle of 0.48 mrad, the angular scale is 0.045 mrad/px, so the detector
half-width of 64 px spans 2.9 mrad and the **smallest d-spacing reachable on
the detector is ~6.8 Å**. No metal or oxide reflection lies there. The
"nearest-neighbour spacing" measured as 12.7 px would correspond to d ≈ 34 Å,
which is not a lattice plane. With 2r = 21.2 px against a 12.7 px spacing the
disks would overlap by ~84%.

The simpler reading is that those maxima are **structure inside the single
central disk**, not distinct Bragg disks. Corroborating: Particle_1's strain
now computes but fails parity by 54× (pipelines §10.3), and its origin fit RMS
is 18.3 px against a 10.6 px probe — the app already flags that probe fit as
unfit for quantitative use.

**Why it matters:** Particle_1 was used to *reject* the 1.5·r and 2.0·r
spacing rules, on the grounds that they "regress" its peak count. If its peaks
are intra-disk structure, that rejection was backwards. The 1.0·r choice
should be re-derived from Si_SiGe and sim_Au alone, or from a dataset with
confirmed reflections. **Check the mean CBED for off-centre disks first.**

**Also flagged:** the change makes a *flagged-invalid* quantity (a probe fit
the app itself says to recalibrate) govern an upstream detection filter. Under
the old rule a bad probe fit could not affect spacing at all.

---

## #20 — Re-measure the Bragg spacing distribution without a gate floor

**Raised by the same review.** `tools/bragg-spacing-probe/` reports each
variant's nearest-neighbour percentiles over *that variant's own accepted
peaks*, so the distribution is hard-floored at the variant's own
`minPeakSpacing`. The published "true nearest-neighbour" figures (14.9 px
Si_SiGe, 12.7 px Particle_1 — pipelines §10.3) come from a 10 px run and are
therefore floored at 10 px. The medians sit well above the floor so the
qualitative finding holds, but the **low tail is truncated**, and for
Particle_1 the shipped 11 px gate is only 1.7 px above the floor — the
measurement cannot see whether it suppresses real peaks.

Two fixes, both cheap:
1. Run the distribution pass with `minPeakSpacing = 0` so the histogram is
   unfloored, then re-check whether 1.0·r still beats 0.75·r.
2. The 40-pattern sample is `prefix(40)` over a row-major strided grid, which
   is not spatially balanced — on Particle_1 (90 rows) 36 of 40 samples land in
   the top half and rows 65–89 are never read, which for a *particle* dataset
   is the difference between on- and off-particle. Build the grid to land on 40,
   or shuffle before truncating.

---

## #18 — The campaign cannot reproduce the app's strain result on Si_SiGe  ·  Priority: LOW (test-harness gap, not a v1 blocker)

**NOT a release blocker — read this before picking it up.** The app already
produces a correct Si_SiGe strain map (100% indexed, 98% basis support,
confirmed by frame-by-frame video analysis, 2026-08-04) — that is real
operational evidence per ROADMAP P1.4's evidence tiers, independent of
automated parity. And the campaign's one dataset with an actual py4DSTEM
comparison — sim_Au — passes, unaffected by anything below (all 47 metrics
bit-identical before/after the disk-spacing fix). What's unresolved is that
the *campaign harness* cannot yet reproduce the app's success, for a reason
six tested hypotheses have failed to find. `docs/v1-scope.md`'s correctness
gate requires deviations to be explicit, not that every one be resolved —
this is now thoroughly documented, so that bar is met. Pick this up when
someone wants deeper harness confidence, not to unblock v1.

**Found 2026-08-04 while fixing the disk-spacing default (pipelines §10.3).**

The release owner produced a clean strain map in the **app** on
`downsample_Si_SiGe_exp` (100% indexed, 100% basis support, RMS 0.885 px,
κ 4.80). The **campaign** cannot, even when handed identical input: re-run with
their exact detector settings it detects **250,195 peaks — the same number to
the peak** — and `StrainMapping.compute` still returns no basis.

Established, so do not re-derive:
- not disk detection — the peak population is identical;
- both call `StrainMapping.compute(bragg:originX:originY:)` on vectors from
  `BraggVectors.calibrated(with:referenceOrigin:)`;
- both use the `.plane` origin fit; the campaign does fit an ellipse before
  detection;
- `BraggVectors(scanWidth: d.rx, scanHeight: d.ry)` and the origin maps both
  come from the same descriptor, so `canUseMaps` should hold.

**Why it matters more than the strain map itself:** every
`"app produced no strain map for this dataset"` parity record is evidence about
the *campaign*, not the app. Until this is found, those records cannot be cited
as app findings — which is most of what the strain half of the parity track has
been reporting.

**Tooling now available:** `MAC4DSTEM_DISK_SIGMA_CC`,
`MAC4DSTEM_DISK_MIN_SPACING`, `MAC4DSTEM_DISK_EDGE` make the campaign reproduce
a hand-tuned session exactly. `MAC4DSTEM_DISK_KERNEL_MEASURED` swaps in
`ProbeKernel.measured` (see below — tested and ruled out, kept for reuse).

**2026-08-04, later: a screen recording of the successful app session was
frame-analyzed and two more candidates were tested and RULED OUT — do not
re-try either:**

1. **Kernel type.** The recording showed the successful run used **"Use
   Current CBED/ROI"** (`AppState.generateMeasuredProbeKernel()` →
   `ProbeKernel.measured`, built from the dataset's actual central-disk shape)
   rather than the synthetic idealized kernel the campaign always builds
   (`ProbeKernel.synthetic`). This looked like a strong, structural candidate —
   it is a real code-level difference, confirmed by the app's own log line
   ("Measured probe kernel ✓ r = 5.0 px from current CBED/ROI"). Tested via
   `MAC4DSTEM_DISK_KERNEL_MEASURED=1`: peak count changes as expected (267,025
   vs 248,368 synthetic — the kernel genuinely is different), but **strain
   still fails identically** ("No sufficiently supported, well-conditioned
   lattice basis was found"). Ruled out.
2. **Aperture feeding origin calibration.** The release owner's own
   hypothesis — that placing/moving the virtual detector before running
   calibration changes the fit. Checked in code: `calibrateOrigin()` calls
   `OriginCalibration.tiledRun(data:descriptor:fitFunction:cancellation:)` with
   no aperture parameter at all; the aperture is only *recentered* onto the
   result afterward. Cannot affect the fit. Ruled out without needing a test.

**Also confirmed matching exactly by frame analysis (so also not the
cause):** ellipse fit fails to converge identically in both paths, with the
same error text ("Detector ellipse fitting did not converge."), so neither
applies a correction; `Calibration.meanOrigin` is exactly
`(Σ fittedX/n, Σ fittedY/n)` in both; Reference = Whole-scan mean and
Basis = Automatic in both; spacing/σCC/edge and peak count (248,118 in the
recording vs 248,368 reproduced with spacing=10 alone, σCC/edge at default)
match to 0.1%.

**What has NOT been tried:** the actual instrumented diff this entry
originally called for — dump `Calibration` state, `referenceOrigin`, and the
first ~20 *calibrated* vectors at matching scan positions from both paths and
compare them directly, rather than testing one hypothesis at a time from
outside. Given how much has been ruled out already, the remaining difference
is likely small and specific (e.g. a float32/float64 path, an ordering
dependency in `expand`/consensus that a near-identical peak SET realizes
differently even at a near-identical peak COUNT, or something in
`StrainMapping`'s basis search itself) — better found by diffing actual data
than by further black-box guessing.

**Core untouched:** unknown until located — likely harness-side, but not
proven; `StrainMapping.compute` itself has not been ruled out.

---

## #30 — Origin calibration over a NAS runs at ~3 MB/s  ·  investigation, not yet a change

**Asked by the release owner 2026-08-05:** origin calibration on a 1.66 GB
cube (`060_STEM…bin_4`, 330 × 330 scan, 64 × 64 detector) was taking ~5–9
minutes. Is that normal, or is it the NAS?

**Almost certainly the NAS, and the app's own read-out says so.** From the
Performance panel: **208.6 positions/s**, ETA 7:29, 108,900 positions.

- Each position is 64 × 64 float32 = **16 KB**, so 208.6 pos/s is an effective
  **≈3.3 MB/s**.
- A local SSD sustains 1–3 GB/s; gigabit Ethernet ≈110 MB/s; even 802.11n
  ≈50 MB/s. **3.3 MB/s is ~30× below gigabit**, so this is not merely "a
  network" — it is latency-dominated access.
- Per position that is **4.8 ms**, which is the order of a filesystem round
  trip, not of a 4096-pixel centre-of-mass fit.

**The app is not doing small random reads.** `VirtualDetector.tiled` reads whole
scan-row tiles sized from the GPU working set (`FourDArray.scanTileRows`), and
`H5Reader` issues one *scan-tile hyperslab* per tile — large sequential reads.
Origin calibration must stream the cube once (it computes the mean/max DP and a
per-position origin), so ~1.7 GB has to cross the link regardless; at 3.3 MB/s
that alone is ~8.5 min. **The cost is the link, not the algorithm.**

**Decisive test for the release owner:** copy the file to the local SSD and
re-run origin calibration, watching the same Throughput read-out. If it jumps
by one to two orders of magnitude, this is settled and the guidance is simply
"work from local storage". Worth checking whether the file is also *contiguous*
(the inspector reports `Chunks: contiguous`), since an unchunked HDF5 dataset
over SMB/NFS is a well-known worst case.

**Only if a local copy is also slow** is there anything to fix in the app, in
which case the next measurement is tile size versus wall-clock — `scanTileRows`
divides the GPU working set by 8, which may be leaving read bandwidth unused.

---

## #29 — "Disk detection sometimes goes bad" — it is the origin fit, not the detection

**Asked by the release owner 2026-08-05**, comparing two Bragg-vector maps on
`downsample_Si_SiGe_exp`: one with sharp discrete spots, one a diffuse mass.

**The detection was not different.** Their own two screenshots report
**248,116 vs 248,384 peaks**, median **24.0 per pattern, range 16–42** in both.
That is the same detection to within 0.1%.

**What the map actually shows.** `AppState.showBraggMap` plots
`calibratedBraggVectors(…)` — every peak is shifted by the **fitted origin of
its own scan position** before being histogrammed. So the sharpness of the
Bragg-vector map is a direct read-out of *origin-fit quality*, not of detection
quality: with a good per-position origin the lattice collapses to points; with
a bad one every position contributes a differently-displaced copy and the spots
smear into a mass.

**The corroborating number is in the same session's log:**
`Origin ✓ r ≈ 5.0 px, fit RMS 11.655 px (Plane)` — an RMS more than **twice the
probe radius**, which the app itself already flags as *"exceeds probe radius;
recalibrate before quantitative use"*. The sharp map came from the run that
used **Use Current CBED / ROI** (measured kernel, RMS 1.46 px, κ 4.59, 100%
indexed); the diffuse one from a **Synthetic** kernel run.

**So the answer is: recalibrate the origin** (measured probe kernel, and a fit
model that can follow the descan — `Plane` may not, on a 200×50 scan).

**The UI lesson, worth acting on:** the Bragg-vector map *is* the origin
diagnostic, and nothing on that pane says so. Candidate: show the origin fit
RMS (and its exceeds-probe-radius warning) beside the Bragg-vector map, so a
smeared map names its own cause instead of being read as bad detection.
**Not implemented** — filed here rather than patched reactively.

---

## #24 — An invisible real-space ROI silently changed the CBED  ·  ✅ Done 2026-08-05

**Reported by the release owner:** after choosing a rectangle in Image, the
Bragg-disks and Strain tasks still showed a region-summed CBED while the scan
image drew only a point crosshair.

**Root cause, and it was not cosmetic.** `AppState.displayedPattern`
substitutes the ROI-summed pattern for the current one whenever
`realSpaceShape != .point` — in *every* task. But `realSpaceROIIsRelevant`,
which gates the overlay, listed only the tasks where a region was *intended*
(virtual detector, strain-from-region, ACOM-from-region). So in Disks and
Strain the sum was in force and invisible — and that summed pattern is what
"Use Current CBED / ROI" builds the probe kernel from and what the
"Current CBED · N peaks" read-out counts.

**Shipped:** `realSpaceROIIsRelevant` is now simply `realSpaceShape != .point`
— the same condition that substitutes the pattern, so the two cannot drift
(pinned by `RealSpaceROIVisibilityTests`) — plus an orange **ROI SUM** badge
(`pattern.roiSumBadge`) in the diffraction header whenever a summed pattern is
displayed. The release owner offered "show the rectangle *or* only sum the
point"; showing it was chosen because the ROI sum is a deliberate feature
elsewhere, and the defect was that it was silent, not that it existed.

---

## #25 — Aperture drawn at the pixel corner, not its centre  ·  ✅ Done 2026-08-05

Detector coordinates name pixel **centres** (`VirtualDetector.fillRadial`
computes `dx = Float(x) - centerX` over integer indices), and
`PeakOverlayGeometry` already drew peaks at `(v + 0.5) · scale`.
`ApertureControl` used a bare `centerX * scaleX`, so the aperture rendered half
a pixel up and to the left — clearly off-axis on a 32×32 detector.

**Shipped:** both directions now route through `PeakOverlayGeometry`, which
gained an exact inverse `pixel(at:…)`, so the draw map and the drag map have
one definition. `OverlayGeometryTests` pins the half-pixel and the round trip.

---

## #26 — Zoom worked only with a trackpad, and only in one pane  ·  ✅ Done 2026-08-05

`MagnificationGesture` is a trackpad pinch and nothing handled the scroll
wheel, so **a mouse could not zoom at all**; the real-space pane had zoom but
no pan, so zooming in stranded the user.

**Shipped** — one set of conventions for both panes (`ZoomPanModifier`):
pinch **or mouse wheel** zooms, drag **or two-finger scroll** pans, double-click
resets that pane. Splitting on `NSEvent.hasPreciseScrollingDeltas` is what lets
one handler serve both devices — a wheel cannot pan, a trackpad already pinches
to zoom, so each device gets the gesture it lacks. The scroll monitor is
installed only while the pointer is over a pane, so the two viewers never fight
over one wheel. `StemImageView` adopted the shared `ZoomPanState`.

---

## #27 — Reopening a dataset landed mid-flow  ·  ✅ Done 2026-08-05

The recovery record restored `workspaceArea = mode.workspaceArea`, so
reopening dropped the user straight into Map or Reconstruct. The remembered
*task* is still restored; the **workspace is not** — a reopened dataset always
lands on Prepare, which is the step that confirms the dataset and its
calibration, and calibration is per-session state the recovery record does not
carry.

---

## #28 — Completed analyses are not switchable, and the bundle exports only one  ·  ✅ Done 2026-08-05

**Shipped, both halves — plus a third defect found on the way.**

**(b) Export.** `scientificBundleMaps()` early-returned out of the strain
branch, so once a strain map existed the orientation fields could never be
exported. It accumulates both now. The provenance question raised when this was
filed turned out to be **already answered**: provenance is per-`ScalarResultMap`,
and `tools/scientific-bundle-test` already builds a fixture holding
`strain_*` *and* `orientation_*` together — the writer never needed changing.
**A regression this could have introduced, and the guard for it:** the writer
requires all fields to share one shape, and a *preview-scope* ACOM map is
subsampled — so naively combining it with a full-scan strain map would have
turned a previously-working export into a hard failure. The bundle now keeps
the scan-shaped family and `scientificBundleOmissions(in:)` names anything left
out in the status line, so a partial export never looks complete.

**(a) Switching.** `AppState.ComputedProduct` + `availableComputedProducts` +
`showComputedProduct(_:)`, wired to the inspector's existing *Computed this
session* rows — "Strain map" and "Orientation map" become clickable with a
`show` affordance once retained (`computed.strain`, `computed.orientation`).
Nothing is recomputed; both maps were always in memory.
**Deliberately an explicit action, not a side effect of `changeMode`:**
navigation must never silently relabel the visible result, which
`testNavigationDoesNotRelabelTheVisibleScientificResult` pins. Covered by
`ComputedProductSwitchTests`.

**Third defect, found while in this file — export was failing outright.**
The release owner hit *"HDF5 export failed while creating the temporary file"*.
Every write path built its scratch file as a **sibling** of the destination
(`.<name>.<uuid>.tmp`). Under the app sandbox `NSSavePanel` grants access to
*the file the user chose*, not to arbitrary new siblings in that folder, so
creating it was denied. All three sites now go through
`BraggVectorEMDWriter.temporaryPublishURL(for:)`, which uses the system
`.itemReplacementDirectory` — writable under the sandbox and guaranteed to be
on the same volume, so the `rename(2)` publish stays atomic. Falls back to the
old sibling path only if the system cannot supply one.
**This is a `Core/Data` change**, so it wants the review gate: it is I/O
plumbing with no numerical effect, and `scientific` is 28/28 green including
`scientific-bundle-test` and `sidecar-result-test`, but it should not be
self-approved.

**Original report (2026-08-05).** Running ACOM
and then Strain shows no strain map, and an export carries only whichever
product is in front.

**Both halves are real and already half-solved by existing state:**

1. **Switching.** `AppState` retains `strainMap` *and* `orientationMap`
   simultaneously — only the *displayed* product is single-valued. So this is a
   presentation gap, not a retention one: it needs a switcher over
   "computed this session" (the inspector already lists exactly that under
   *Files & products*), not a new cache. Saving to the session sidecar in
   Results already persists products, but it is manual and per-product.
2. **Export.** `ResultExport.scientificBundleMaps()` early-returns:
   `if let map = strainMap { return strain fields }` and only *then* considers
   `orientationMap`. With both computed, the orientation fields can never be
   exported. It should emit both, which raises one real question to settle
   first — whether a mixed bundle keeps one `provenance` block per field
   (it must; strain and ACOM have different `quantitative_status` and different
   run semantics).

**Scope note:** the export half touches `Support/ResultExport.swift` and the
EMD writer's field set, so it earns `tools/run-tests.sh scientific` and a
session save-and-reopen check.

---

## #22 — Layout breaks when panes are toggled or the tools pane is dragged wide

**Reported by the release owner 2026-08-05**, reviewing the design-pass build.
Two symptoms, both horizontal analogues of **#16**:
1. Toggling the tools / inspector panes clips the sidebar off the **left** edge
   and the inspector off the **right** at the same time — the whole split laid
   out wider than the window.
2. Dragging the tools pane very wide "gets distorted".

**Neither reproduced headlessly**, and the investigation produced a *false
positive* recorded in `docs/ui-design-pass-2026-08-05.md` §1.7 so it is not
repeated: driving the divider with `NSSplitView.setPosition(_:ofDividerAt:)`
looks like it reproduces symptom 2, but a SwiftUI `NavigationSplitView` never
follows an externally forced divider — it owns that layout — so the desync it
shows is the probe's own. It also pushes content off the *right*, while the
real report clips the *left*.

**Shipped on its own merits, NOT as a confirmed fix:** the detail column was
rigid (`minWidth: 480` panes + a *fixed* 300pt inspector = a 780pt floor), so
against the 1080pt minimum window it had essentially no slack — the exact
configuration reported as breaking. Now 360pt panes, a compressible 220–340pt
inspector, and a 170pt per-pane floor.

**Third report, 2026-08-05:** *"I minimized an info bar and the UI somewhat
collapsed."* The screenshot shows **three things losing their top at once** —
the sidebar's upper rows, the detail column's entire workspace header, and the
inspector's upper rows — while the titlebar and traffic lights stay put. That
is a different shape from #16 (one scroll view scrolled past its own top) and
points at the whole split being laid out taller than the window.

**Ruled out by measurement (do not re-try):** toggling log/inspector in all
combinations, three times over, in both a normal workspace and Reconstruct;
with the tools pane collapsed as well; and — the one variable the screenshot
actually showed — with the sidebar **scrolled down** first, at two scroll
depths. The sidebar's `contentInsets.top` stayed 52 and its clip origin tracked
the scroll exactly in every one. Nothing in the non-Results detail column
declares a `minHeight`, so there is no obvious source for content taller than
the window on that path.

> **The pattern across all three reports (#16, #22, and this) is now the
> finding.** Five independent programmatic reproductions have failed while the
> release owner hits these routinely by hand. Mutating `AppState` is not the
> same input path as clicking a real toolbar button or dragging a real divider,
> and SwiftUI's layout demonstrably responds differently. **The missing
> capability is real user input**, which needs the same **Accessibility
> permission** that has blocked the QC playthrough since 2026-08-04. Granting it
> converts these from unreproducible reports into an XCUITest that clicks the
> actual controls. That is now the highest-value unblock in the repo.

**Open:** the trigger. Needs the release owner to re-test (design doc §6.5), or
Accessibility granted so the harness can drive real clicks.

---

## #23 — The virtual-detector controls look unfinished  ·  ✅ Done 2026-08-05

**Reported by the release owner 2026-08-05:** *"the UI for choosing the
detector in real space feels ugly to me."* The section rendered a `Shape`
segmented picker whose inline label ate the row width, leaving four segments
fighting over the rest of a 292pt column — and below it **three full-width
stacked bordered buttons** (Bright Field / ADF / HAADF), which read as a
placeholder rather than a control.

**Shipped:** the shape picker takes the full row (`.labelsHidden()`, with an
accessibility label so nothing is lost to VoiceOver), and the presets became
one compact right-aligned row of conventional STEM abbreviations —
**BF · ADF · HAADF** — as small bordered buttons under a "Presets" caption,
with the full name in the tooltip and the accessibility label. Identifiers
`detector.preset.{bf,adf,haadf}`. The "Region → diffraction" section got the
same treatment for consistency, plus its radius readout moved to a right-
aligned monospaced value instead of being baked into the label text.

`ContentView.shortName(_:)` holds the abbreviations — deliberately *not* on
`DetectorPreset`, which lives in `Core/`.

---

## #16 — Controls intermittently unresponsive; navigating away and back clears it

**◐ MECHANISM FOUND + FIXED DEFENSIVELY 2026-08-05; TRIGGER STILL UNCONFIRMED.**

**The two symptoms are one bug.** Measured in a real window (hosted test, real
`ContentView`): the sidebar `NSScrollView` sits at clip origin **0** while its
`contentInsets.top` is **52** — scrolled exactly one titlebar-height past its
own top. Healthy is `docTopInWindow=871, visibleOriginY=-52`; broken is
`docTopInWindow=923, visibleOriginY=0`, i.e. the first rows land at the top of
the *window*. That is both halves of the report at once: the rows draw across
the traffic lights, **and** they stop responding, because the titlebar
hit-tests above them. So the app did not accumulate a family of stale-state
bugs — there is one, with two faces.

**Seven candidate triggers were driven and REFUTED** (do not re-try): offset
clamping when the sidebar document shrinks on a workspace switch — the most
promising one, AppKit re-clamps to −52 correctly every time; the toolbar item
count changing in Results; an animated `showToolsPane` round trip; log/inspector
toggles; window resize; key resign/restore; rapid non-linear navigation.

**Shipped:** `.scrollBounceBehavior(.basedOnSize)` on the sidebar `List`
(`UI/ContentView.swift`) — top overscroll is the remaining candidate and this
closes it — plus the structural half: removing the duplicated readiness block
(**#21**) took the blocked-Reconstruct sidebar from **1040pt to 899pt** against
871pt of column, so on most screens there is now nothing to scroll and nothing
to overscroll. Pinned by
`SidebarLayoutTests.testSidebarContentNeverDrawsOverTheTitlebar`, which asserts
`clipOrigin == -contentInsets.top` after every one of the refuted transitions.

**Still open, needs a human:** confirming the entry is top overscroll. Nothing
headless can generate a real rubber-band trackpad gesture — see
`docs/ui-design-pass-2026-08-05.md` §6.3 for the 60-second check.

**Original report — reported by the release owner, 2026-08-04**, observed across the last few
sessions — the UI "got buggier". Buttons are sometimes blocked/inert, and
clicking through the workspace sections and back usually restores them.
Screenshot at the time showed the **Reconstruct** task with its prerequisite
list ("Set the Q pixel scale / R pixel scale / accelerating voltage") while the
Prepare section header was drawn overlapping the toolbar.

**Not yet diagnosed — do not guess a fix.** That it clears on navigation points
at stale view state rather than a genuine prerequisite block: candidates are a
`@State` value surviving a task switch, a disabled-binding computed from a
readiness snapshot that is not re-read, or a SwiftUI diffing problem in the
section headers (the overlap in the screenshot suggests layout state is also
involved). Reproduce first and capture *which* control, in *which* task, after
*which* transition.

**Why it matters beyond annoyance:** the prerequisite checklist shipped in
Prompt B is what tells a user why a primary action is unavailable. If a control
can be disabled while the checklist says it is ready — or ready while inert —
that undermines the mechanism v1 relies on to explain itself.

**Core untouched:** expected yes — this is view state.

---

## #17 — Rotate the real-space image in the browser (display only)  ·  ✅ Split & shipped 2026-08-05

**The item's stated justification was falsified by arithmetic, and the item was
split because of it.** Rotation cannot recover pane area: an image of aspect
*a* fitted into a pane of aspect *p* fills `min(a,p)/max(a,p)` of it, which is
unchanged when *a* becomes *1/a* and the pane keeps its shape. The measured
panes are ~660×646 — square — so the 200×50 strain map fills **25% before the
rotation and 25% after it**. What recovers the space is re-proportioning the
*pane*.

### #17a — aspect-aware pane arrangement  ·  ❌ BUILT, THEN REVERTED on sight 2026-08-05

**Do not rebuild this.** It worked as designed — a 200×50 scan stacked the
panes vertically and the map went from ~25% to ~98% of its pane — and the
release owner rejected it immediately on seeing it: *"how come the diff and
real space images are now on top and below, this is not ok, they should be left
and right like we established right in the beginning."*

The lesson is not that the arithmetic was wrong; it is that **the side-by-side
arrangement is part of the app's identity**, and a layout that rearranges
itself per dataset is worse than an under-filled pane. Space efficiency was the
wrong objective to optimise here. Diffraction left, real space right, always.

The arithmetic below still stands and is why the *original* #17 rationale was
wrong — it just does not justify this remedy either.

### ~~#17a — what it was~~ (reverted; kept for the reasoning)

**Shipped:** `ProductWorkflow.stacksImagePanesVertically(scanWidth:scanHeight:)`
+ `ContentView.imagePanes`. A scan wider than 2:1 puts the diffraction and
real-space panes in a `VSplitView` instead of an `HSplitView`, so the wide map
gets a full-width, short pane. The threshold is **derived, not chosen**:
side-by-side panes are ~1:1 and stacked ones ~4.1:1, so a scan of aspect *a*
fills `1/a` one way and `a/4.1` the other, and they cross at `a² = 4.1`, a ≈ 2.
Si_SiGe (200×50, a = 4) goes from ~25% to ~98% of its pane; sim_Au (84×100),
Particle_1 (45×90) and WS₂ (128×128) are all unaffected. Tall scans never
stack — the rule is deliberately one-sided, because a full-height pane already
suits them. The axis follows the dataset, so it is decided once on open and
does not shift under the user. Pinned by
`testWideScansStackTheImagePanesAndNothingElseDoes` (all four training
datasets + the crossover at 199/100 vs 200/100).

### #17b — display rotate/flip  ·  ✅ Done (built for orientation, not for area)

**Shipped:** `RealSpaceDisplayOrientation` (quarter turns only) +
`AppState.realSpaceDisplayOrientation` / `realSpaceDisplayMirrored`, reset per
dataset, with a **"View orientation"** menu in the real-space pane header
(`result.viewOrientation`) worded "display only — scan indices, saved products
and the scientific bundle are unchanged" so it can never read as the measured
R–Q rotation.

Every constraint the item named, and how it was met:

- **Quarter turns + mirror only** — the enum has no arbitrary angle to pass.
- **Real space only** — the control and the transform are both gated on
  `displayedProduct?.domain == .scan`, so the same viewer showing a
  detector-domain product is never transformed, and `DiffractionView` has no
  control at all. Pinned by `testOrientationIsIgnoredForNonScanProducts`.
- **The inspector inverts rather than follows** — solved structurally instead
  of by hand: the rotation is applied to the *shared* image+overlay container
  and the cursor/selection mapping lives **inside** it, so SwiftUI's own hit
  testing applies the inverse. There is no hand-rolled inversion that could
  drift from the forward transform.
- **The scale bar recomputes against the correct axis** — a quarter turn
  switches it to `pixel.row` and to `dims.height` for the pixel count, on
  screen and in the burnt-in figure both, because for a non-square scan that is
  a different pixel size *and* a different extent.
- **Export** — the release owner chose the split: the **publication PNG applies
  the orientation and records it** (`display_rotation_deg`, `display_flip`
  appended to the burnt-in caption, but only when it is not the default, so an
  unrotated figure carries no noise); the **scientific EMD bundle stays in
  scan-index order** and records the same two keys plus
  `display_orientation_applied=false`. A quantitative field must stay
  addressable by (Rx, Ry). Silently baking an unrecorded rotation into a figure
  — the one unacceptable outcome — cannot happen on either path.

**Deviation worth noting:** the pixel transform is implemented on the RGBA
buffer in pixel indices (`AppState.orientedRGBA`), not as a `CGContext`
transform. The context's y-axis points the opposite way to the view's, so the
rotation sign there is easy to get backwards and nearly invisible in review —
and with no Screen Recording permission this session, no one could have caught
it by eye. In pixel indices it is pinned exactly by `ResultOrientationTests`
(11 cases: direction, dimension swap, mirror composition order, 4×90° identity,
channel travel, degenerate buffers).

**Original item — concrete case, 2026-08-05:** on `downsample_Si_SiGe_exp` the strain map is
**200 × 50** and renders beside a square **128 × 128** CBED, leaving most of the
result pane empty. Rotating the real-space view 90° would let both panes use
their space. Confirmed by the release owner as presentation only — "not a
scientific rotation in that sense, just for the show" — which is exactly the
framing that makes the constraints below matter rather than disappear.

**Requested by the release owner, 2026-08-04.** A 200 × 50 scan is displayed
as a wide, short strip that is awkward to read. There should be a way to rotate
how the real-space image is *presented* — with the scale bar following — while
the underlying data, indices and exported product are untouched.

**Scope this carefully; it is a scientific-labelling question, not just a
transform:**

- **90° steps + flips only, no arbitrary angle.** Multiples of 90° are exact
  and need no interpolation. An arbitrary angle resamples the scan grid, which
  makes a *displayed* image that no longer corresponds pixel-for-pixel to the
  scan positions — much easier to mistake for modified data.
- **Real space only.** Never offer this for the diffraction pattern: the app
  already has a measured **R–Q rotation** calibration, and a display rotation
  of the CBED would be indistinguishable from it. Name the control so the two
  can never be confused.
- **The inspector must keep reporting true scan indices.** `Current scan
  position x (Rx) / y (Ry)` and the cursor→position mapping must invert the
  display rotation, not follow it.
- **The scale bar must recompute against the correct axis.** For a non-square
  scan a 90° rotation swaps which R pixel size governs the displayed
  horizontal, so a bar that just re-renders at the same length is wrong.
- **Decide and document what export does** (ROADMAP P1.1: a result keeps its
  interpretation through display *and* export). Either the publication figure
  ignores the display rotation, or it applies it and records the orientation in
  provenance. Silently baking an unrecorded rotation into an exported figure is
  the one outcome that is not acceptable.

**Core untouched:** yes, if it stays a presentation transform.

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
