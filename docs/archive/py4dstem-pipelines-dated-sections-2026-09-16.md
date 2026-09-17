> History, not guidance. Moved verbatim from `docs/py4dstem-pipelines.md` on 2026-09-16 (docs consolidation); the live replacement is `docs/py4dstem-pipelines.md`.

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
   for a UI change is the owner driving the app (the Track B checklist that
   followed the playthrough was itself retired 2026-09-03; its record is in
   `docs/archive/v2/`). The
   *pipelines* below are unaffected — they are still what any acceptance run,
   scripted or human, should drive the app through.

This QC harness is therefore dual-purpose: an *evaluation* of scientific
correctness against py4DSTEM **and** a *usability regression test* for the
workflow layer.
