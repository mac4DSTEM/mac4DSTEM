# mac4DSTEM UI / Workflow Backlog

The repo's item-level record of open and closed work. It **started** as the
ranked output of evaluating the app against the canonical py4DSTEM pipelines
(`docs/py4dstem-pipelines.md` §7–§9) and has since become the general place
findings land, whatever found them.

**Layer key:** `UI` = SwiftUI views only (`mac4DSTEM/UI/`). `WF` = workflow
state/sequencing (`mac4DSTEM/App/AppState.swift`,
`mac4DSTEM/App/ProductWorkflow.swift`).

**Read the "Core untouched" line on each item; do not assume.** Items **#1–#13**
are the original QC-derived set and are contractually UI/workflow-only, which is
what makes them safe to hand out as implementation prompts. Later items are not
all in that category: **#11, #14, #15, #31, #32** are `Core/Crystal`, **#37** is
`Core/Compute`, and **#36** needs the reader to report progress. Anything
touching `Core/` needs an adversarial review *and* a `tools/` fixture — see
`CLAUDE.md`. Ideas that are out of v1 scope *and* touch `Core/` live in
`docs/post-v1-ideas.md` instead, deliberately.

## What is actually still open

Everything else on this page is closed. As of **2026-08-06**:

| Item | What it needs |
|---|---|
| **#16 / #22** | Cause found and fixed 2026-08-06 (one modifier — see the entry). **Outstanding: one on-screen `tools/ui-qc-playthrough/run.sh sim_Au` to confirm step 3b now passes.** |
| **#36, #37, #38, #39, #43** | Ordinary work, scoped and ready. #43 is a gate defect, not an app one. |
| **#40** | A decision from the release owner about which surface owns Q calibration. |
| **#11, #15, #31, #32** | `Core/Crystal`; #11 is a roadmap-level scope question, the rest are small and known. |
| **#18, #19, #20** | Harness confidence and acquisition parameters, not app defects. |
| **#29, #30** | Recorded investigations; no change proposed yet. |

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

## Recommended first three — ✅ ALL THREE CLOSED 2026-08-04/05

**Kept only as the record of what the evaluation phase judged most important.**
For what to do next, use the *"What is actually still open"* table above, not
this list.

1. **#7 Reconstruct prerequisite checklist** — a disabled button with no
   explanation, on 4/4 datasets. The single largest dead end measured so far.
2. **#5 Make the strain reference/basis choice explicit** — promoted from
   MED-LOW on new evidence: the automatic whole-scan basis is the *only* thing
   standing between three datasets and a strain map, and the app already has
   the controls that would fix it.
3. **#1 ACOM prerequisite gating** — same pattern as #7, and
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

## #1 — Gate & sign-post ACOM's prerequisites  ·  Priority: HIGH  ·  Layer: WF + UI  ·  Effort: M  ·  ✅ Done

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

## #3 — Give accelerating voltage a first-class home  ·  Priority: MED  ·  Layer: UI + WF  ·  Effort: M  ·  ✅ Done

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

## #5 — Make the strain reference/basis choice explicit  ·  Priority: HIGH  ·  Layer: UI  ·  Effort: S-M  ·  ✅ Done

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

## #7 — Tell the Reconstruct task which prerequisite is missing  ·  Priority: HIGH  ·  Layer: UI (+ light WF)  ·  Effort: S-M  ·  ✅ Done

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

## #8 — Make the strain failure's "adjust the thresholds" advice actionable  ·  Priority: MED  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

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

## #9 — A failed compute should not block the whole window  ·  Priority: MED  ·  Layer: UI  ·  Effort: S  ·  ✅ Done

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

## #14 — `expand` splits symmetry-equivalent sites at ordinary CIF precision  ·  ✅ Done 2026-08-05

**Shipped:** dedup tolerance is now derived from each coordinate's *written
precision* instead of a fixed 1e-4, and a cell that is still over-populated is
rejected by a new `atomic_sites_too_close` model-validation issue rather than
producing quiet nonsense. Pinned by `tools/cif-symmetry-test/`, now 29 cases
(was 14) — including the symmetry-expansion path, which the original fixture
never reached because every "must admit" case supplied its cell contents
explicitly. `run-tests.sh all` green, exit 0, 30 harnesses.

**It deviated from the fix direction this item proposed, and the deviation is
the whole story.** The item suggested reusing `symmetryPositionTolerance`
(5e-3) as the dedup tolerance. That is a fixed constant, and a fixed constant
is exactly what was wrong: 5e-3 still fails at 2 decimals and starts merging
distinct atoms in large cells. What shipped infers each coordinate's rounding
half-step from its literal text (`0.2500` is exactly ¼ and carries no error;
`0.333` carries 1e-3), propagates it through the symmetry-operator rows, and
merges only when both a per-axis precision bound and a 0.10 Å real-space cap
agree.

**The adversarial review earned its keep again — it refuted the first version
of this fix, and every finding below was reproduced independently before being
acted on.** Four defects, three of them regressions the fix itself introduced:

- **Truncation, not rounding.** CIF writers truncate ⅔ to `0.6666` as often as
  they round it, and truncation error is a full ulp of the last decimal —
  twice what a rounding assumption allows. The first version therefore
  *rejected* correct HCP magnesium at 3, 4 and 6 decimals while admitting it at
  5 and 7, on which side of the bound the residual happened to land. The bound
  is now `10⁻ᵈ`, not `0.5·10⁻ᵈ`.
- **A precision-derived point-group tolerance is not safe, and was reverted.**
  The first version also derived `symmetryPositionTolerance` from the file's
  precision. That let a coarsely-written file widen its own gate — and worse,
  it was a file-global maximum, so *the coordinate breaking the symmetry
  supplied the excuse for tolerating the break*. An FCC cell whose face-centre
  site was displaced by 0.163 Å was admitted as full m-3m cubic, fabricating an
  IPF colour key: the exact outcome that gate exists to prevent. The two
  tolerances face opposite risks — a too-tight *merge* tolerance is loud, a
  too-loose *point-group* tolerance is silent — so the gate is fixed at 5e-3
  again. Precision is now used **only to explain a rejection**: a new
  `symmetryUnresolvableAtWrittenPrecision` error says the coordinates are too
  coarse to confirm the symmetry, which is true, instead of claiming the
  structure is trigonal, which is not.
- **Over-merge deletes atoms silently.** A 0.30 Å real-space merge cap fused
  two genuinely distinct sites 0.20 Å apart at 2 decimals and admitted the cell
  one atom short — the same class of quiet error as #14 with the sign flipped.
  The cap is now 0.10 Å, and the gap between it and the 0.5 Å close-contact
  limit is deliberate: a pair too far apart to be rounding and too close to be
  chemistry is now **rejected**, not merged.
- **Split-site disorder is legitimate.** Two half-occupied images straddling a
  special position 0.2–0.5 Å apart is routine refinement practice, and a
  close-contact check with no occupancy awareness rejected those correct files
  while telling the crystallographer their symmetry expansion had duplicated
  sites — in files with no symmetry loop, where no expansion ever ran. Pairs
  whose occupancies sum to ≤ 1 are now exempt, and the message states only what
  was measured. Residual hole, documented in place: duplicates of an
  already-part-occupied site are invisible to the check.

Also fixed on the way: P1 coordinates outside `[0,1)` (legal CIF) were left
unwrapped, hiding close contacts from a detector that only searches the
neighbouring cells. The fixture now asserts the in-cell invariant for every
admitted model.

**Two findings from the same review are NOT fixed and are filed as #31 and
#32.** Neither is caused by this change.

**#15's dependency on this item is discharged** — the `symmetryPositionTolerance`
doc comment no longer cites `expand`'s 1e-4. The tolerance-band question #15
actually raises (1e-3 in `classifyFamily` vs 1e-6 in `validationIssues`) is
untouched and still open.

---

<details><summary>Original report (2026-08-04)</summary>

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

</details>

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
the offending axis pair.

**Core untouched:** no, but low risk — error routing only, no numerics.

**Updated 2026-08-05.** The doc-comment half of this item is discharged —
`symmetryPositionTolerance` was rewritten under #14 and no longer cites the
1e-3 metric gate as its justification. The tolerance *band* itself is
unchanged and this item stays open. Not a v1.0 blocker: the failure mode is a
correct rejection carrying a less specific message, not a wrong result.

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

## #22 — Layout breaks when panes are toggled or the tools pane is dragged wide  ·  ✅ Same bug as #16 — fixed 2026-08-06

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

## #16 — Controls intermittently unresponsive; navigating away and back clears it  ·  ✅ Cause found & fixed 2026-08-06 (on-screen confirmation outstanding)

**✅ REPRODUCED DETERMINISTICALLY 2026-08-05 (evening), by real synthesized
input, after Accessibility was granted.** This is the first reproduction after
five failed programmatic attempts, and it ends the "intermittent" framing:
under the QC harness it happens **every time**, at the same step.

**How to reproduce:** `tools/ui-qc-playthrough/run.sh`. It fails at step 3b on
every dataset that reaches it, with
`Element workspace.primaryAction exists but is not hittable`
(`QCPlaythroughUITests.swift:72`). Run
`References/training_runs/run_2026-08-05_2012/` holds two `ERROR_state.png`
captures — the evidence, kept deliberately.

### ✅ MECHANISM FOUND 2026-08-06 — it is NOT a scroll offset, and never was

**Instrumented run `run_2026-08-06_0120`.** A temporary probe
(`Support/LayoutDiagnostics.swift`, inert without `--layout-diagnostics`) dumped
the sidebar `NSScrollView`'s geometry on every task/workspace change. The two
captures either side of the `task.DPC` click — timestamped 01:22:10–01:22:47,
three seconds before `ERROR_state.png` at 01:22:50, so unambiguously the failing
state:

```
[task→DPC immediate] window 1470.0 x 923.0  contentLayoutRect y=0.0 h=871.0  titlebarInset=52.0
    scroll[0] x=0 w=325 h=923  | insetTop=52.0 clipOriginY=-52.0 expected=-52.0 DRIFT=+0.0 | docH=871.0   clipH=923.0
[task→DPC settled]   window 1470.0 x 923.0  contentLayoutRect y=0.0 h=871.0  titlebarInset=52.0
    scroll[0] x=0 w=325 h=1154 | insetTop=52.0 clipOriginY=-52.0 expected=-52.0 DRIFT=+0.0 | docH=1102.5 clipH=1154.5
```

**Three facts, and each one kills a standing hypothesis:**

1. **`DRIFT = +0.0` at every single capture.** The clip origin is *exactly*
   `-contentInsets.top` before, during and after the collapse. **The scroll
   offset is never wrong.** Every scroll-offset hypothesis — the seven refuted
   triggers, the top-overscroll theory, and the `.scrollBounceBehavior` fix
   shipped defensively against it — was aimed at something that is not
   happening. `docH (1102.5) < clipH (1154.5)`, so the sidebar has nothing to
   scroll and is not scrolled.
2. **`titlebarInset = 52.0` and `contentLayoutRect y=0 h=871` are identical
   before and after.** The titlebar safe area does not collapse. The window does
   not move or resize (1470 × 923 throughout).
3. **The sidebar scroll view grows from `h=923` to `h=1154.5` — inside a 923 pt
   window.** It is laid out **231.5 pt taller than the window that contains it**,
   so its content necessarily extends above the visible area. That is the
   collapse: the top rows are drawn off the top of the window, and the titlebar
   hit-tests over what remains.

**So the bug is that the split view is given more height than the window**, and
both columns inherit it — which is exactly what #22's third report described
("three things losing their top at once — the sidebar's upper rows, the detail
column's entire workspace header, and the inspector's upper rows") and what the
screenshot measurement below shows from the outside.

**Why every previous attempt missed it:** they measured the scroll offset, which
is correct, rather than the scroll view's *frame*, which is not. The
2026-08-05 hosted test asserting `clipOrigin == -contentInsets.top` passes in the
collapsed state — it would have gone green with the bug on screen.

### 🎯 CAUSE FOUND 2026-08-06 — one modifier, bisected in a hosted test

**It reproduces in-process** — `mac4DSTEMTests/SplitViewHeightTests.swift`, no
screen needed. The six earlier in-process attempts failed because they hunted the
*scroll offset*, which is correct; a frame height is a pure layout property and
reproduces immediately. Driven with `openDemoFixture(calibrated: false)`, because
the click only changes the layout when `guidance(for: .dpc, …)` is non-empty.

**Measured, window 1470 × 923:**

| Variant | sidebar scroll h | root `fittingSize.h` | verdict |
|---|---|---|---|
| Virtual imaging (baseline) | 923 | 226 | healthy |
| **after switch to DPC** | **1291.5** | **1343.5** | **collapsed** |
| `imagePanes`: `HSplitView` → `HStack` | 1291.5 | 1343.5 | **no effect — refuted** |
| `TaskPrerequisiteChecklist` → `EmptyView` | 923 | 227 | healthy |
| guidance `Text`: drop `.fixedSize(…vertical: true)` | 923 | 277.5 | healthy |
| guidance `Text`: add `.lineLimit(3)`, keep `fixedSize` | 923 | 315.5 | healthy |

**The cause is a single modifier**: `.fixedSize(horizontal: false, vertical: true)`
on the guidance `Text` in `TaskPrerequisiteChecklist.limitedInterpretation`.
`fixedSize(vertical:)` means *"never compress me — give me whatever height my
content needs at the proposed width."* Measured at a narrow proposed width the
text wraps to many lines, and `fixedSize` turns that into a **hard minimum
height** which propagates up through the detail column → the outer `NSSplitView`
→ the hosting view, past the window's own height. Everything else — the sidebar,
the panes — merely inherits the split view's height. Bounding the wrap
(`lineLimit(3)`) bounds the demand, which is what confirms the mechanism rather
than merely correlating with it.

This also explains every otherwise-puzzling observation: the scroll offset is
never wrong because **nothing scrolls**; the titlebar inset never collapses
because the window never changes; and the sidebar's top rows go off-screen only
because the *column* is taller than the window.

**Why this one interaction, and why #22 is the same bug.** The app has 22
`.fixedSize(horizontal: false, vertical: true)` sites, but 18 are inside the
sidebar `List` (a row may grow; the List scrolls) and one is in `WelcomeWorkspace`
inside a `ScrollView`. **The only unbounded vertical text demands sitting in the
detail column outside any scroll view are the three in
`TaskPrerequisiteChecklist`** — the guidance text, the "Ready: …" satisfied
summary, and the `.taskPanel` hint. That is exactly why the trigger is *mounting
the checklist*, and why the release owner also hit it on **Reconstruct** (five
prerequisites plus the voltage hint) — **#16 and #22 are one bug**.

### ✅ FIXED 2026-08-06 — `lineLimit(4)` on all three checklist explanations

**Shipped:** `TaskPrerequisiteChecklist.explanationLineLimit = 4`, applied to all
three wrapping `Text`s — the guidance line, the satisfied summary, and the
`.taskPanel` hint. `fixedSize` is *kept*, so nothing is truncated at any real
column width; the cap only removes the unbounded demand. A cap does not force
lines, so short strings are unaffected. Chosen over dropping `fixedSize`
altogether because this checklist is the single owner of readiness (#21) and
silently truncating its explanation to one line has a real cost.

Applied to **all three** sites rather than only the bisected one: the other two
render on the blocked path, which is where the release owner originally hit this
on Reconstruct.

**Pinned by `mac4DSTEMTests/SplitViewHeightTests.swift`**, which asserts the
general invariant — *nothing inside the window may be laid out taller than the
window* — rather than anything about `fixedSize`, so the guard survives a
different remedy later.

**Verified to fail without the change, 3 runs each way**, after a first version
proved flaky: with a fixed `pump(0.6)` the task-switch case caught the unfixed
build and the sweep did not; at `pump(0.9)` the sweep caught it and the
task-switch case did not. Both now wait for layout *quiescence* instead of a
guessed duration, and fail 3/3 unfixed, pass 3/3 fixed.

`testABlockedTaskAlsoFitsTheWindow` is documented in place as **coverage, not a
tripwire** — measured to pass 3/3 with the fix reverted, so a green run there is
not evidence about #16.

**`SidebarLayoutTests.testSidebarContentNeverDrawsOverTheTitlebar` gained a
frame-height assertion.** It asserted `clipOrigin == -contentInsets.top`, which
is **true throughout the collapse** — it went green with the bug on screen for
months. A correct clip origin inside an oversized frame still puts the top rows
off-screen.

**Not yet confirmed on the real app.** The hosted test proves the layout
invariant; it does not prove the QC playthrough now gets past step 3b. That run
is the remaining check.

**Superseded question — kept for the record:** *what demands 1154.5 pt?* The
click's only structural effect is that `ProductWorkspaceHeader` mounts
`TaskPrerequisiteChecklist` (because `guidance(for: .dpc, …)` is non-empty where
`.virtualDetector`'s is empty), so the detail column's content grows. Something
then propagates a height larger than the window back up to the split view instead
of the column scrolling or compressing. **This is now a pure layout question with
no interaction in it, so it should be answerable in a hosted test
(`SidebarLayoutTests` already builds a real window) without needing the screen.**

**Do not "fix" this by clamping the sidebar's height.** That would hide the
symptom while the detail column still demands more than the window.

---

### Screenshot measurement 2026-08-06 — the "whole window too high" mechanism is WRONG

**Reproduced again** (`run_2026-08-06_0058`, sim_Au, same failure at step 3b),
and this time the two frames were **measured instead of eyeballed**: row-
brightness cross-correlation of `03_virtual_df.png` against `ERROR_state.png`
over separate x bands, both captures 2940 × 1846 native = 1470 × 923 pt.

| Band | Displacement | Residual |
|---|---|---|
| Sidebar column, whole | **+89.5 pt (up)** | 2.0 |
| Sidebar, upper half | **+89.5 pt (up)** | 1.2 |
| Sidebar, lower half | **+89.5 pt (up)** | 2.4 |
| Detail column, image panes | **−67.0 pt (down)** | 0.4 |
| … diffraction pane alone | **−67.0 pt (down)** | 0.9 |
| … real-space pane alone | **−67.0 pt (down)** | 0.1 |
| Titlebar band | **0.0 pt** | — |
| Traffic lights | **0.0 pt** | — |

**The two columns move in opposite directions, by different amounts, under a
stationary titlebar.** That is not a collapsed safe-area inset — a collapsed
inset moves everything the same way by the same amount. The recorded mechanism
("the whole window's content is laid out ~52 pt too high, as if the titlebar
safe-area inset collapsed", "both columns moved together") is refuted. So is the
inference built on it, that "a sidebar scroll offset cannot move the detail
column's header, therefore it is not the sidebar scroll view."

**The detail column's −67 pt is not a defect.** The DPC header is taller than
the Virtual-imaging one because `ProductWorkflow.guidance(for: .dpc, …)` is
non-empty while `.virtualDetector`'s is empty, so `ProductWorkspaceHeader` mounts
`TaskPrerequisiteChecklist` on this click and everything below it is pushed down.
That is the header doing its job. It is also why the earlier reading looked
plausible: the header's *title row* really does end up above the visible area,
but because the header grew, not because the column rose.

**So the entire anomaly is the sidebar, rigidly translated 89.5 pt past its own
top** — the upper and lower halves agree to the pixel, so it is a scroll offset,
not a layout stretch. Which revives exactly the hypothesis that was retired:

> *"offset clamping when the sidebar document shrinks on a workspace switch —
> the most promising one, AppKit re-clamps to −52 correctly every time"*

That refutation was obtained **programmatically, on a workspace switch**. The
real trigger is a **task switch under real input**, and this entry's own recorded
lesson is that those are not the same input path. **The seven-refuted list should
not be treated as covering it.**

**Not yet established, and the next thing to test:** *why* the offset ends up at
+89.5 pt. Note it does not match the 52 pt (`contentInsets.top`) that the
2026-08-05 hosted test measured, so the two observations are not obviously the
same state and that discrepancy is itself unexplained. The sidebar's content does
change on this click — the `Region → diffraction` section is unmounted and a
shorter `DPC` section takes its place — so a document-height change is present
and is the obvious thing to instrument first. **Do not fix anything from this
paragraph; it is the hypothesis, not the finding.**

Measurement script kept out of the repo deliberately (it is disposable); the
numbers above and the two captures in `run_2026-08-06_0058/` are the evidence.

---

**Earlier reading of the same screenshots — SUPERSEDED by the measurement above.**
The *whole split* is laid out roughly one titlebar-height (52 pt) too high:
- the sidebar's top rows are drawn **under the traffic lights** ("Inspect and
  calibrate the dataset" is clipped by the window edge);
- the window title "mac4DSTEM" is drawn **over** the detail column's content;
- the workspace header row — which carries `workspace.primaryAction`
  (`UI/ProductWorkspaceViews.swift:231`) — is pushed above the visible area
  entirely. It stays in the accessibility tree, so it "exists"; it cannot be
  clicked, because it is not on screen and the titlebar hit-tests above it.

**"Disabled button" was ruled out by geometry, not by the error text.** The
button is `.disabled(!primaryActionEnabled)`, and a disabled `XCUIElement` is
also un-hittable — so the message alone does not distinguish the two. But a
disabled button would still be *drawn* in the header, and in both captures the
header row is not on screen at all.

**The sequence that triggers it** (from the XCUITest log, both datasets):
click `workspace.image` → click `task.DPC` → `workspace.primaryAction` exists
but is not hittable. A task switch inside the Image workspace, which is the one
transition the earlier investigation drove programmatically and refuted — real
input reproduces what mutating `AppState` did not.

**THE TRIGGER IS NOW ISOLATED TO A SINGLE CLICK, and it overturns the earlier
mechanism.** `03_virtual_df.png` and `ERROR_state.png` in the same run folder
are the same window, seconds apart, and the only event between them is the
click on `task.DPC`:

| | `03_virtual_df.png` (before) | `ERROR_state.png` (after) |
|---|---|---|
| traffic lights | in the titlebar, content below | **drawn on top of sidebar rows** |
| sidebar top row | "Prepare / Inspect and calibrate…" fully visible | clipped by the window's top edge |
| workspace header | visible, **"Update Image"** button at top right | pushed above the visible area |
| window size | 1470 × 838 | 1470 × 838 — *unchanged* |

**So it is not the sidebar scroll view.** The earlier diagnosis (sidebar
`NSScrollView` at clip origin 0) cannot be the whole story, because a sidebar
scroll offset cannot move the *detail column's* header — and in these captures
the detail column shifts by the same amount. What actually happens is that the
**whole window's content is laid out ~52 pt (one titlebar height) too high**,
as if the titlebar safe-area inset collapsed to zero. The sidebar measurement
from 2026-08-05 morning is a *symptom* of that, not the cause.

**Trigger:** switching task from *Virtual imaging* to *DPC & iDPC* inside the
Image workspace, on a real dataset. Note the DPC header is taller than the
Virtual-imaging one — it carries a readiness line and an "Improve in Prepare"
button — so a header height change on task switch is the prime suspect.

**A sixth in-process reproduction failed (2026-08-05 evening) — recorded so it
is not repeated.** A hosted test built the real `ContentView` at both 838 and
923 pt and drove `selectWorkspace(.image)` then `analysisMode = .dpc`:
`safeAreaInsets.top` stayed 52 and the sidebar stayed at clip origin −52 at
every step. Two reasons it proves less than it looks: it used
`openDemoFixture()`, whose sidebar may be short enough never to scroll; and
SwiftUI controls are accessibility *elements*, not `NSView`s, so
`workspace.primaryAction` could not be located in-process at all — walking
`accessibilityChildren()` from the content view did not surface it either. **A
probe that cannot see its target must not be left behind as a passing test**,
so it was deleted rather than committed.

**CONFIRMED BY SCREEN RECORDING, 2026-08-05 (evening).** A 7.9 s capture of the
release owner switching to DPC by hand, stepped at 10 fps, pins it to a
**single frame**: at t ≈ 7.0 s the layout is healthy, at t ≈ 7.1 s it has
collapsed, and the click that separates them is on the **DPC & iDPC task row**.
No resize, no scroll, no other input.

In the collapsed frame, `Diffraction (CBED)` is drawn **above** the "mac4DSTEM"
window title and the traffic lights sit on top of the sidebar rows. Both
columns moved together. This is a whole-window titlebar-inset collapse, and it
is now reproducible three independent ways: by hand, by the QC harness, and in
this recording.

### ❌ The "infinite frame" lead is DEAD — measured 2026-08-06, do not re-try

The 27 `(inf, inf, 0.0, 0.0)` lines in `run_2026-08-06_0058` were mapped onto
test-relative time and correlated with the XCUITest activity log. They are
**background noise, not a signature of the collapse**:

- First occurrence at **t ≈ 8 s**, during app launch — ~130 s before the trigger.
- A dense burst at **t ≈ 127–136 s** coincides exactly with the PNG export:
  `⌘⇧G`, the Go-to-folder sheet, and two Return presses. Sheets and panels are
  separate windows, and positioning one asks `DisplayManager` which display
  contains a not-yet-established frame.
- One fires at **t = 138.9 s**, right after the *benign* `workspace.image`
  click that causes no collapse at all — and one at **t = 141.9 s** after the
  `task.DPC` click that does. **The same line appears on the click that breaks
  the layout and on the click that does not**, which is what retires it.

`(inf, inf, 0, 0)` is exactly `CGRectNull` — the value AppKit *returns* from a
rect operation that found nothing. It is an effect of ordinary window/sheet
positioning here, not evidence of a NaN propagating through a layout pass.

**Original text kept below for the record.**

The XCUITest log repeats
`[DisplayManager] Could not find any displays containing rect (inf, inf, 0.0, 0.0)`,
and the entry previously called this the strongest untested lead on the grounds
that an infinite origin with zero size is a degenerate layout result.

**But `(inf, inf, 0, 0)` is exactly `CGRect.null`** — the documented value of
`CGRectNull`, which is what AppKit *returns* from a rect operation that found
nothing: an empty intersection, or the frame of a view lying wholly outside its
clip. So the most economical reading is that this line is a **consequence** of
the header being pushed off-screen, not a cause — and one obvious producer is
XCUITest itself, asking for the hit point of the `workspace.primaryAction`
element it has just found to be unhittable.

**Cheap test that settles it, and should be done first:** check *when* the line
appears in the run log. If it appears only at or after the step-3b hittability
check, it is an artifact of probing an off-screen element and the lead is dead.
If it appears **before** the collapse, it is real and worth chasing into the
image panes' aspect/scale math. Noted 2026-08-06; not yet measured, because the
run that would have measured it never launched (see the permission note below).

**Before any run: confirm Accessibility is still granted.** On 2026-08-06 a
reproduction attempt failed with `Timed out while enabling automation mode`
after 60 s — the app never launched and no run folder was written. That is a
*missing grant*, not a #16 symptom, and the grant is keyed to a version-scoped
path (`claude-code/<version>/claude.app`), so it lapses on every Claude Code
update. See `docs/v2-onramp.md` § "The one thing to do first".

**The fix can now be tested empirically, which was never true before.**
`tools/ui-qc-playthrough/run.sh sim_Au` fails at step 3b every run, in about
two minutes. That is a real edit-test loop: make one hypothesis-driven change,
run it, keep or discard. Do not batch several speculative changes into one run.
Note it drives real windows on screen, so it needs the machine to itself.

**A third failure mode appeared on the dataset after those two:**
`Failed to synthesize event: Timed out while synthesizing event`
(`AXDriver.swift:404`) — the app stopped accepting synthesized input entirely,
which is the "inert" half of the original report in its strongest form.

**Consequence for the QC playthrough:** it gates the entire pipeline at step 3b.
The 2026-08-05 run finished in 413 s against the baseline's 30 m 22 s and never
reached Bragg disks, ACOM or strain on any dataset, so **it produced no
acceptance numbers** — the closeout-step-4 diff is still outstanding, now for a
fixable reason rather than a permissions one.

---

**◐ Earlier state — MECHANISM FOUND + FIXED DEFENSIVELY 2026-08-05; TRIGGER
UNCONFIRMED at the time.**

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

## #31 — `validationIssues` is O(n²) and runs in a SwiftUI view body

**Found by:** the adversarial review of #14's fix, 2026-08-05. **Caused by that
change**, and accepted knowingly rather than fixed.

`CrystalModel.validationIssues` now contains a pairwise close-contact scan, and
`ACOMControlsView` reads it through `AppState.acomModelSelectionIssue` on every
re-render, with no memoization. Measured: 0.3 ms at 500 atoms, 3 ms at 2 000,
19 ms at 5 000, **76 ms at 10 000**.

**Why it shipped anyway:** the cells that reach ACOM are cubic or hexagonal
phase models, which are tens of atoms, not thousands — every built-in model is
under 10. A 10 000-atom import is a P1 supercell export, which is not a v1 use
case. The check is O(n²) but gated behind a per-axis fractional prefilter that
rejects almost every pair in three comparisons, so the constant is small.

**Fix direction when it matters:** precompute the close-contact distance once
in `CrystalModel`'s construction rather than recomputing it per read, or hoist
the check to import time only. The first is preferable — it keeps the model
contract in one place.

**Core untouched:** no (`Core/Crystal`), but it is caching, not numerics.

---

## #32 — `isSymmetry`'s bijection check has no fixture coverage, and its stated counterexample does not exercise it

**Found by:** the adversarial review of #14's fix, 2026-08-05, by mutation
testing. **Pre-existing** — it predates that change and is unaffected by it.

Deleting the `!claimed.contains(index)` guard from `CIFImport.isSymmetry` —
the surjectivity check that makes the symmetry map a genuine permutation —
leaves `tools/cif-symmetry-test/` **fully green**, both before and after the
#14 work. So the guard is untested.

Worse, the comment above it names a specific counterexample ("without this an
FCC cell carrying a split atom … passes as cubic"), and the case that was built
from that claim is rejected by a *different* path entirely: it still fails with
the guard removed. The claim as written appears to be wrong.

**Fix direction:** either construct a case that actually dies without the guard
— it needs two distinct sites both landing within tolerance of the same target,
which is what the guard exists to forbid — or delete the claim and keep the
guard on its own merits. Do not leave a comment asserting a counterexample
nobody has reproduced.

**Core untouched:** no (`Core/Crystal`), but a fixture-only change if the
guard turns out to be correct.

---

## #33 — The green task tick means "ready", but reads as "done"  ·  ✅ Done 2026-08-05

**Shipped, and the entry below was left stale for a day — worth recording why.**
The fix landed in `d47afb5`, a commit titled *"changes to .md"* that also
touched `UI/ContentView.swift`. So the code moved and this entry did not, and a
reviewer working the documented range `a9e4268..9c940d1` would have missed the
change entirely. Found by the 2026-08-06 review; the review range in `CLAUDE.md`
and `docs/v2-onramp.md` was corrected at the same time.

`ContentView.taskButton` now draws an **empty `circle`** for a ready task and
keeps the orange `exclamationmark.circle.fill` for a blocked one — matching the
inspector's own glyph for "this product does not exist yet", so ✓ is left to
mean *completed* everywhere. Readiness detail stays where **#21** put it: the
prerequisite checklist under the primary action. No tooltip, per the item.

**Reported by the release owner 2026-08-05**, hands-on: *"the green ticks right
of Virtual imaging and DPC are already green before I even did the steps."*

**Confirmed in code, not a misreading.** `ContentView.swift:1303` renders
`taskUnmetCount(mode) == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"`.
So green ✓ = *every prerequisite for this task is satisfied*; orange ! = one is
missing. Nothing about it reports whether the task has produced a result.

**Why it misleads:** the app already uses ✓ for *completed* elsewhere — the
inspector's "Computed this session" list marks Origin calibration ✓ against
empty circles for R–Q rotation, Bragg disks, Strain map, Orientation map. Two
different meanings, one glyph, both on screen at once.

**Fix direction:** reserve ✓ for "this produced a result" and give readiness a
different affordance (an empty/filled state dot, or nothing at all when ready —
readiness is already carried by the prerequisite checklist under the primary
action, which is the one owner #21 established). Do **not** solve it with a
tooltip.

**Core untouched:** yes — presentation only.

---

## #34 — A cancelled Bragg detection still displays a Bragg vector map  ·  ✅ Done 2026-08-06

**The open question is settled: it is a STALE PREVIOUS result, never a partial
one.** Established by reading the cancellation path rather than by inference —
`DiskDetection.detectAll` returns `nil` whenever the token is cancelled
(`Core/Analysis/DiskDetection.swift`, the `return !bad && cancellation?.isCancelled != true`
guard), so a half-finished `BraggVectors` cannot reach `AppState`. The cancel
branch in `runDiskDetection` then returns early without touching `braggVectors`
or `resultImage`, which leaves whatever the last completed run published on
screen. So the worse of the two possibilities — a partial peak set presented as
complete — does not happen.

**What was actually wrong was silence, in two places, and both are fixed:**

- **The cancel message named nothing.** Every other cancellable step in
  `AppState` already says what it kept ("Parallax alignment bin N cancelled;
  last completed level retained", "Parallax KDE cancelled; aligned result
  retained"); disk detection alone said only "Disk detection cancelled". It now
  says whether peaks are still shown or none were ever published.
- **The result pane never said the map was out of date.**
  `diskDetectionSettingsAreStale` already existed and already gated strain and
  ACOM, and the *sidebar* already said "Full-scan peaks use earlier settings" —
  but the viewer showed the map with its ordinary title. An orange
  **"Earlier settings"** badge (`result.staleBadge`) now sits beside the
  interpretation badge in `StemImageView`. Being correct in a panel the user is
  not looking at does not satisfy ROADMAP P1.1.

**Deliberately NOT done: discarding the previous map on cancel.** When the
settings have not changed, that map is the current, valid, full-scan result and
throwing it away would destroy good work to make a message simpler. The badge
is keyed on the staleness the app already computes, so it appears exactly when
the map and the panel disagree.

<details><summary>Original report (2026-08-05)</summary>

**Reported by the release owner 2026-08-05:** *"When I stop the Bragg disc
detection, it shows a Bragg vector map regardless — this doesn't make sense."*
Screenshot log reads `Detecting Bragg disks… / Cancelling Disk detection… /
Disk detection cancelled`, with a fully rendered Bragg vector map beside it.

**This contradicts a documented contract.** `README.md` § Known limitations
states "Cancel invalidates the result immediately; the in-flight GPU command
finishes in the background." A map left on screen after cancellation is either
a stale product from an earlier run that is not labelled as such, or a partial
result being presented as complete. Both are ROADMAP P1 problems — a displayed
result must carry its validity — and the second is worse than cosmetic, because
a partial peak set looks exactly like a real one.

**Establish which it is first:** does the pane show the *previous* completed
map, or a partial map from the cancelled run? The fix differs. If previous, it
needs a label. If partial, it must be discarded.

**Core untouched:** unlikely — result publication on the cancel path.

</details>

*(It turned out to be presentation only: `Core/` is untouched.)*

---

## #35 — Diffraction pane: a click must not move the detector  ·  ✅ Done 2026-08-06

**Shipped as option 1, exactly as decided — pan when zoomed, scrub when not.**

- `RealSpacePointerPolicy` (`UI/`) owns the decision and the marker geometry.
  Zooming **out** is deliberately still the scrub mode: the image is then
  smaller than its pane, so there is nothing to pan to and removing
  click-to-scrub would cost a gesture and give nothing back.
- At zoom 1 `StemImageView.selectionLayer` is mounted and behaves exactly as
  before. Zoomed in it is **not mounted at all** — that, rather than any gesture
  priority trick, is what lets a plain drag reach `zoomPan` and finally makes a
  zoomed real-space image pannable.
- The scan marker gains a filled white grab handle when zoomed, mirroring
  `ApertureControl`'s centre handle, so both panes share one vocabulary.
- **The mode is visible.** A `PAN · ×N` badge (`result.zoomModeBadge`) appears
  in the pane header whenever the mode is not scrub, because a mode nobody can
  see is just confusing — the one real objection to option 1 when it was chosen.
- **Double-click reset was verified, not assumed**: at zoom 1 `selectionLayer`
  does still swallow the second click, but `reset()` is a no-op at zoom 1; once
  zoomed — the case that matters — the layer is gone and the double-click
  reaches `ZoomPanModifier`.

**Harness impact: none, and this was checked rather than assumed.** The item
warned that `mac4DSTEMUITests` might drive scrubbing by clicking the real-space
image. It does not — the QC playthrough only clicks identified controls
(`workspace.*`, `task.*`, `calibration.*`), never the image.

Pinned by `mac4DSTEMTests/RealSpacePointerPolicyTests.swift` (9 cases: the
zoom-1 default, zoomed-out, zoomed-in, float noise either side of 1, and the
marker geometry). **Mutation-tested:** deleting the half-pixel centre offset
initially left the marker round-trip green — the marker merely slid to its
pixel's leading edge, which still floors to the same index — so the assertion
was strengthened to "the marker sits *strictly inside* its own pixel band", and
that version does kill the mutant. Same failure mode as **#32**.

<details><summary>Original item and the analysis behind option 1</summary>

**Reported by the release owner 2026-08-05**, then specified exactly:

> Don't move the marker on click, only when grabbed and moved. Zoom in and move
> around in the zoomed picture, unzoom by double-clicking. **This doesn't change
> the mask.**

**The contract, as four rules:**
1. A plain click anywhere in the diffraction pane **never** moves the detector.
2. The detector moves **only** while its handle is grabbed and dragged.
3. Drag on empty area pans the zoomed image; double-click resets zoom/pan.
4. Zoom and pan are display-only and **never** alter detector geometry.

**Rule 4 is already guaranteed, and this was verified rather than assumed.**
`ZoomPanState` is display state held in `DiffractionView`; the only writers of
aperture geometry are `ApertureControl`'s own handle drags, which call
`emit(_:)` → `app.updateAperture(_:)`. No zoom or pan path reaches it. So the
mask is safe today.

**RESOLVED BY SCREEN RECORDING, 2026-08-05 — the defect is in the OTHER pane.**
A 46 s recording was analysed frame by frame (ffmpeg contact sheets at 1 and
4 fps; the working images are disposable, the conclusion is not):

- **The diffraction pane already satisfies all four rules.** Frames 4.5–10.5 s
  show the detector being grabbed by its white centre dot and dragged, staying
  put when the cursor moves away un-grabbed, and being dragged back. Correct
  throughout. **Nothing to fix here** — the original report misattributed the
  pane.
- **The real-space pane violates rules 1–3.** Frames 26–34 s show the scan
  marker sitting *directly under the cursor* and tracking it continuously
  across the zoomed image, while the image content never moves.

**Mechanism, confirmed in code.** `StemImageView.selectionLayer` uses
`DragGesture(minimumDistance: 0)` and sits *above* `zoomPan`'s pan gesture. So
in the real-space pane every click scrubs the scan position, and the scrub
gesture always wins over the pan gesture — meaning **a zoomed real-space image
cannot be panned at all**. Zooming in is therefore useless: you can magnify but
never navigate.

**What the release owner is asking for is that both panes follow the same four
rules**, with the *diffraction* pane as the model, not real space.

**This is not a light fix, and it is not obviously safe.** Click-to-scrub is
the primary way a user explores a 4D-STEM dataset — clicking a scan position to
see its CBED. Replacing it with grab-the-marker-only changes the app's most
used gesture, and `mac4DSTEMUITests` may drive scrubbing by clicking. Options,
in increasing order of disruption:
1. **Pan wins when zoomed, scrub when not.** `zoom == 1` keeps today's
   click-to-scrub; zoomed in, drag pans and the marker moves only by its own
   handle. Preserves the common case, fixes the useless-zoom case. Mode-
   dependent, which needs to be visible in the UI or it is just confusing.
2. **Marker gets a grab handle, always.** Literal reading of the request, fully
   consistent with the diffraction pane, and the biggest behavioural change.
3. **Modifier key to pan** (e.g. space or ⌥ + drag). Conventional, discoverable
   only if documented.

**DECIDED 2026-08-05 by the release owner: option 1 — pan when zoomed, scrub
when not.** Implement that; do not re-open the choice.

**What option 1 means concretely:**
- At zoom == 1 (the default), behaviour is **unchanged**: click or drag
  anywhere in the real-space pane scrubs the scan position. This is the
  gesture users make a hundred times a session and it must not regress.
- Once zoomed in, **drag pans** the image, and the scan marker no longer
  follows the cursor. The marker still needs a way to be moved while zoomed —
  give it a grab handle, mirroring `ApertureControl`'s white centre handle in
  the diffraction pane, so both panes share one vocabulary.
- **Double-click resets zoom/pan** in the real-space pane. `ZoomPanModifier`
  already provides this; verify it actually fires, because `selectionLayer`
  currently sits above it and may be swallowing the second click.

**Watch out for:** `mac4DSTEMUITests` may drive scrubbing by clicking the
real-space image. Check `mac4DSTEMUITests/Support/AXDriver.swift` and the QC
playthrough before assuming the change is invisible to the harness. Since the
zoom == 1 path is unchanged, it should be — but verify rather than assume.

**Also worth pinning with a test:** `SidebarLayoutTests` is a hosted target and
can build a real window, so "at zoom == 1 a click still scrubs" is cheap to
assert and is the regression that would hurt most.

**Core untouched:** yes.

</details>

---

## #36 — No progress indication while a datacube loads

**Reported by the release owner 2026-08-05:** *"When you open a dataset, for
some time nothing happens… I want a loading bar that shows me the progress on
that. Better than watching the Cube memory go up until it is stable, and the
user won't wonder why he can't interact with the dataset."*

The app already has the two things this needs — a determinate progress control
in the workspace header (used by virtual detector, "34 %") and a live
`Cube (f32)` figure in the performance panel. Load is the one long operation
that reports neither, so the first thing a new user experiences is the one
unexplained wait.

**Core untouched:** likely not — the reader has to report progress.

---

## #37 — Cancelling the virtual detector takes a long time

**Reported by the release owner 2026-08-05.** Visible in the log as repeated
`Computing virtual detector… / Virtual detector cancelled` cycles, and in a
screenshot as a header stuck at "Virtual detector 0 %" with Cancel showing.

Partly expected and documented (`README.md`: Metal commands cannot be
interrupted after submission; CPU loops stop at row/template boundaries), but
"documented" is not the same as "acceptable" — the user is left watching a
progress bar that no longer means anything. At minimum the UI should say it is
finishing an in-flight GPU command rather than showing stalled progress.

**Measure before changing anything:** how much of the delay is the in-flight
command and how much is cancellation checking too coarsely.

**Core untouched:** no — cancellation granularity lives in `Core/Compute`.

---

## #38 — The image panes' scroll monitor consumes every scroll in the window

**Found by:** code review, 2026-08-06. **Pre-existing** — it shipped with #26.

`ZoomPanModifier.installScrollMonitor` (`UI/SwiftUI+MTKView.swift`) installs an
`NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` and returns `nil`,
which swallows the event. The comment says why — *"consumed — don't let it
scroll the sidebar behind"* — and for scrolls **over the pane** that is right.

But a local monitor is window-wide, not view-wide. It is armed by
`onContinuousHover(.active)` and disarmed by `.ended`, so for as long as SwiftUI
has not delivered an `.ended` — a pointer leaving through a divider, a window
losing key, a pane disappearing on a task switch — every scroll anywhere in the
window is eaten, including in the tools sidebar and the output log. The
`onDisappear` cleanup covers teardown but not a missed `.ended`.

**Why it is not fixed here:** the failure is a *missed event*, so judging it
needs real input, which puts it in the same class as #16/#22 — six programmatic
reproductions of that one failed. Guessing a fix is exactly what this repo has
twice been burned by.

**Fix direction when it is picked up:** gate the handler on the event's own
location rather than on hover state — convert `event.locationInWindow` into the
pane's frame and pass the event through (`return event`) when it falls outside.
That makes correctness independent of ever receiving `.ended`, which is the
property the current design lacks.

**Core untouched:** yes.

---

## #39 — The Reconstruct tools sidebar is one flat wall of controls

**Found by:** code review, 2026-08-06, following up the release owner's *"the UI
feels very off … it got crowded"*.

**#21 fixed the Reconstruct *main pane* and never touched the sidebar.** The
`workspaceArea == .reconstruct` branch of `ContentView` is ~450 lines inside a
single `Section`: roughly 20 `TextField`s, 8 toggles and 6 buttons, plus the
"Run details" disclosure. Once `parallaxHigherOrderFit` exists, essentially all
of it is on screen at once — KDE σ, Lanczos order, position-correction
iterations, low/high-pass cutoffs, depth start/end/planes, information limit and
power — in a 250–340pt column.

**The structure to reuse already exists.** `reconstructionProgress` already
models the workflow as four stages, and `primaryActionTitle` already knows which
stage is next. The controls are simply not grouped by it.

**Fix direction:** group each stage's parameters under the stage it belongs to
and expand only the current one, keyed off the same stage the header's primary
action names. Presentation only — no control changes meaning, none is removed.

**Deliberately not patched reactively** (2026-08-06): the release owner scoped
this session to fixing breakage rather than restructuring, and this is the same
kind of decision #21 took a design pass to answer.

**Core untouched:** yes.

---

## #40 — ACOM restates Prepare's Q calibration, and draws the IPF key twice

**Found by:** code review, 2026-08-06. Same family as **#21** — one thing owned
by two surfaces.

Two duplications, both in `UI/ACOMControlsView.swift`:

1. **Q calibration has two owners.** `qScaleControls` renders its own
   *"Calibrate Q from Selected Material"* button plus Q-scale value and
   provenance rows. `CalibrationReadinessChecklist`'s `qScale` case renders the
   same action (*"Calibrate from selected material"*, made prominent by **#2**)
   and the same provenance. Both call `calibrateQFromCrystal()`. It is milder
   than #21 because ACOM's copy sits inside an *Engine & Q scale* disclosure —
   but the disagreement it invites is real: #2 deliberately shaped how that
   choice is *presented* in Prepare, and none of that shaping applies here.
2. **The IPF colour key is drawn twice at once.** `resultControls` draws
   `CubicIPFLegendView` / `HexagonalIPFLegendView` in the sidebar while
   `StemImageView` draws the same legend over the image. A legend belongs with
   the pixels it decodes.

**Fix direction:** apply #21's rule — decide which surface *owns* readiness-like
information, and have the other point at it. Prepare owns calibration, so ACOM's
Q rows become a read-out plus the "Review Q Calibration in Prepare" link it
already has; the image owns the legend.

**Why it is a decision, not a patch:** moving where a control lives changes
where a user has learned to look for it, and the ACOM panel's stated purpose is
that *"keeping material, scale semantics, work scope and result diagnostics
together prevents a physically labelled output from being assembled out of
unrelated controls elsewhere"* — a real argument for the duplication that has to
be answered rather than ignored. Needs the release owner's call on the
destination.

**Core untouched:** yes.

---

## #41 — The CBED pattern-source picker was drawn on top of its own header  ·  ✅ Done 2026-08-06

**Found by:** code review, 2026-08-06. **Pre-existing.** Part of the release
owner's *"it got crowded"* report, and the one part of it that was an outright
drawing bug rather than density.

`DiffractionView.header` placed the Current / Mean / Max segmented picker in a
centred **`.overlay`** on the header `HStack`, with a comment explaining it was
"centered over the pattern rather than crammed against the size". An overlay
does not participate in its host's layout, so the ~170pt `fixedSize()` picker
was drawn straight through *"Diffraction (CBED)"* — invisible on a wide window,
guaranteed at the 360pt minimum detail-column width the layout actually allows.
The picker only appears once mean/max exist, which is why it survived: it is
absent until calibration has run.

**Shipped:** it is a row member now, so the `HStack` budgets space for it and
the title truncates instead of being overdrawn. It also gained the
accessibility identifier (`pattern.displayMode`) and label it never had — it was
an unlabelled `Picker("")`. The trailing read-outs are `fixedSize()` so the
title is the thing that yields. **Checked, not assumed:** no test in
`mac4DSTEMUITests` or `mac4DSTEMTests` reaches this picker, so the identifier is
additive.

The same pass gave `StemImageView.header` single-line policies, for the same
reason: a wrapping title or cursor read-out changes the header's *height*, which
moves both image panes.

---

## #42 — Aperture radius drags published fractional pixels; centre drags did not  ·  ✅ Done 2026-08-06

**Found by:** code review, 2026-08-06. **Pre-existing**, and it survived #25's
pass over this same file.

`ApertureControl.emit(_:)` rounds every field before publishing, and its comment
states the contract: *"a virtual detector sums whole pixels, so fractional edges
are meaningless."* The centre handle and the rectangle handle used it. The
annulus inner/outer handles and the circle radius handle called `onEdited`
directly, so one control had two contracts — and the inspector's *Inner r /
Outer r* rows showed whole or fractional pixels depending on which handle you
had touched last.

**Shipped:** all four handles route through `emit`. Presentation/handle
plumbing only; `applyDetectorPreset` and the dataset-open defaults still set
fractional radii deliberately, which is unchanged — the contract is that a
*drag* snaps, not that a radius is always integral.

---

## #43 — The acceptance gate breaks if anyone saves a session for a training dataset

**Found by:** the acceptance gate crashing during the 2026-08-06 review session.
**Pre-existing**, and it is a *gate* defect, not an app defect.

`tools/real-data-acceptance/run.sh:32` collects its inputs with

```sh
files=("$ROOT"/References/training_dataset/*.h5(N))
```

and hands every match to a harness that calls `fail()` — a hard `exit(1)`, seen
as `Fatal error: … H5Error.noDatasetFound` — on anything that is not a datacube.

**The app writes its session companion as `<source>.mac4dstem.h5`, deliberately
beside the source file.** So the moment a session is saved for any dataset in
`References/training_dataset/` — by a user, by the QC playthrough, or by a
stray app instance — the next `tools/run-tests.sh all` dies partway through
`real-data-acceptance` with an error that names 40 HDF5 paths and says nothing
about the actual cause. Observed exactly that: exit 133, with
`downsample_Si_SiGe_exp.mac4dstem.h5` present in the directory.

**Why it matters more than the inconvenience:** the aggregate claim in
`README.md` is *"`tools/run-tests.sh all` — exit 0 across 30 harnesses"*. A gate
that fails from a file the app is designed to create is a gate whose green is
partly luck, and the failure mode is loud but deeply unhelpful.

**Fix direction:** exclude the app's own sidecars from the glob — they are
identifiable by the `.mac4dstem.h5` suffix — and, separately, make the harness
report an unreadable file as a named failure rather than a top-level fatal, so
one bad file cannot take the whole gate down without saying which file it was.
Both are small; neither is in this session's scope.

**Core untouched:** yes — `tools/` only.

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
