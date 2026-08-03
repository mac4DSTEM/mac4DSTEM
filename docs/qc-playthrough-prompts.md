# QC Playthrough — reusable prompts for future sessions

Hand any prompt below to a **fresh agent on an empty context**. Each is
self-contained: it names the files to read first, the constraints, how to
run, and the definition of done. Copy the whole block for the task you want.

**Where this lives:** `docs/qc-playthrough-prompts.md` (this file). This is the
**single source of truth for QC-initiative status** — update the checklist
below when a task lands.

## Status — what's done, what's next

- ✅ **Baseline: ACOM pipeline on `sim_Au`** — clean end-to-end
  (`References/training_runs/run_2026-07-21_0013/`). The reference the other
  pipelines extend.
- ✅ **Prompt 3 — UI/workflow backlog** — done, produced
  `docs/ui-workflow-backlog.md`.
- ✅ **Prompt 1 — strain + phase-contrast pipelines** — done 2026-08-03.
  Runs: `References/training_runs/run_2026-08-03_1345/` (sim_Au, 0 failures),
  `run_2026-08-03_1309/` (Particle_1), `run_2026-08-03_1319/` (WS₂ + Si/SiGe).
  Findings in `docs/py4dstem-pipelines.md` §9.2; backlog items #7–#11.
  **DPC** runs on all four datasets; **strain** produces and exports an ε_xx
  map on `sim_Au` (and fails on the other three at automatic basis fitting —
  three distinct causes, §9.2.1); **kV is settable through the UI** after all
  (located structurally, so §7.4 is a discoverability finding, not a dead end).
  **Reconstruct did not run on any dataset** — after voltage is filled in, each
  is still blocked by a *different* prerequisite (see the §9.2 table), which is
  backlog #7. That is a real gate in the app + training set, not a harness
  limitation, so it is recorded as a finding rather than worked around.
- ✅ **Prompt 2 — fan out to all datasets** — done 2026-08-03.
  Run: `References/training_runs/run_2026-08-03_1404/` — one no-argument run,
  all four datacubes, **30 m 22 s, 0 failures**, each with screenshots, PNG
  exports and `log.md`. Per-dataset summary in `docs/py4dstem-pipelines.md`
  §9.3. Robustness confirmed: three datacubes hit a real app-side failure
  (strain non-convergence + its modal error sheet) and the run logged,
  recovered and continued every time. All numbers reproduced the §9.2
  standalone runs exactly, so those findings are not artefacts of invocation.
  Each log now opens with a `## Routing` section naming the §6 pipeline for
  that dataset.
- ✅ **Prompt 4 — full-scan + IPF ACOM** — done 2026-08-03.
  Run: `References/training_runs/run_2026-08-03_1459/` (sim_Au, 0 errors).
  Full-scan orientation map (**8,400 positions × 200 templates in 0.7 s**) and
  the **IPF · Z** coloring both produced, screenshotted and exported alongside
  the preview/Reliability map. Findings in `docs/py4dstem-pipelines.md` §9.4;
  new backlog items #12 (Preview/Reliability defaults are too conservative —
  full scan is sub-second here) and #13 (a full-scan result carries *no* scope
  qualifier, so it is the least-labelled product). Both controls were driven
  without app changes: the segmented `acom.scope` by segment label, the
  identifier-free display picker by its current value.

**All four prompts are now complete — this file is finished.** The evaluation
phase is done; the follow-on work changes app code and therefore leaves the
eval-only track.

> **→ The active phase is now `docs/ui-implementation-prompts.md`.** It carries
> the live status checklist and five cold-start prompts that act on what this
> evaluation found. Start there.

This file remains the reference for **how the harness is driven** and for the
eval-only rules that still apply whenever the QC playthrough is *extended*
rather than *used*. The playthrough itself is now the **acceptance test** for
the implementation phase: re-run `tools/ui-qc-playthrough/run.sh` with no
argument after any change and diff against `run_2026-08-03_1404/` (§9.3).

## Task closeout — run these EXACT steps at the end of every task (this is the anti-chaos rule)

Standardized handoff so docs never drift. Do all of it before stopping:

1. **Tick the box** in the Status checklist above (⬜ → ✅) and add the run
   folder path if the task produced one.
2. **Record findings** in `docs/py4dstem-pipelines.md` §9 (what worked, what
   the app did, any deviation noticed).
3. **Log UI friction** (anything a user would stumble on) as a new item in
   `docs/ui-workflow-backlog.md`, tagged UI-only vs workflow-logic.
4. **Do NOT modify app logic** under `mac4DSTEM/` — evaluation only. If the app
   blocked the pipeline, that's a backlog item, not a code change.
5. **Do NOT commit** unless the user asks. Leave the working tree for review.
6. **Stop with a short summary**: what ran, where the outputs are, what the next
   unchecked task is.

If a task can't finish, leave its box unchecked, write why in §9, and stop —
never mark done what isn't.

---

## Shared context (every prompt already references this — here for you)

- The app is **mac4DSTEM**, a macOS 4D-STEM analysis app.
- A visible XCUITest QC target **`mac4DSTEMUITests`** drives the real app
  through analysis pipelines, screenshots each step, and writes a per-datacube
  markdown log + PNG exports to `References/training_runs/run_<timestamp>/`.
- Canonical pipelines are documented in **`docs/py4dstem-pipelines.md`**
  (extracted from `References/py4DSTEM_tutorials-main/notebooks/`).
- Run it with **`tools/ui-qc-playthrough/run.sh [name-substring]`** (e.g.
  `sim_Au`). It builds incrementally into `build/ui-qc-DerivedData`, ad-hoc
  signs, then runs. NOT part of `tools/run-tests.sh`.
- **Hard constraint: evaluation only — do NOT modify app logic under
  `mac4DSTEM/`. Only touch the test target `mac4DSTEMUITests/`, the runner
  `tools/ui-qc-playthrough/`, and `docs/`.**
- Project memory: `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM/memory/qc-playthrough-pipeline-eval.md`.

---

## PROMPT 1 — Extend the harness to strain + phase-contrast pipelines

```
Work in the mac4DSTEM repo. First read docs/py4dstem-pipelines.md (esp. §4
strain and §5 DPC/parallax/ptychography), then read the existing test at
mac4DSTEMUITests/QCPlaythroughUITests.swift and mac4DSTEMUITests/Support/
AXDriver.swift to see how the ACOM pipeline is already driven.

Goal: add three more canonical pipelines to the QC playthrough, each driving
the app's REAL controls in the order py4DSTEM teaches:
  - Strain mapping (§4): load → calibrate origin/rotation → disks → StrainMap
    (choose basis vectors, fit, get_strain). App tasks: Map → Strain.
  - DPC (§5a): load → set accelerating voltage → DPC preprocess → reconstruct.
    App tasks: Image → DPC. Needs kV (see note below).
  - Parallax and/or iterative ptychography (§5b/5c): App workspace Reconstruct.
    Needs kV.

Constraints:
  - EVALUATION ONLY. Do not modify anything under mac4DSTEM/. Only edit the
    test target, the runner, and docs.
  - Pick the pipeline per dataset the way the current test does (a
    filename→analysis map). Use the dataset↔pipeline table in §6 of the doc.
  - Accelerating voltage: the app's kV field lives under Reconstruct →
    Ptychography and currently has NO accessibility identifier. Either locate
    it structurally (by "Voltage" label near that task) or, if you cannot,
    log that DPC/parallax/ptycho could not set kV via UI and treat it as a
    finding (do NOT add an identifier to app code — that violates eval-only).
  - Keep robustness: log + continue on per-datacube failure.

How to run: tools/ui-qc-playthrough/run.sh <dataset-substring>  (iterate on
one dataset until its new pipeline is clean before moving on). Read the
generated log.md + screenshots + ERROR_state.png under
References/training_runs/run_*/ to debug. Known automation gotchas: read
macOS static text via AXValue not .label (use AXDriver.bestText); nested
.accessibilityElement(children:.contain) rows are not queryable (read the
whole panel); export steps navigate to the Results workspace, so re-navigate
before clicking task buttons.

Done when: strain produces and exports a strain-component map; DPC produces
and exports a phase image (or the kV limitation is clearly logged); and at
least one reconstruct-workspace pipeline runs. Update docs/py4dstem-pipelines.md
§9 with findings.
```

---

## PROMPT 2 — Fan out the QC playthrough to all datasets

```
Work in the mac4DSTEM repo. Read docs/py4dstem-pipelines.md §6 (dataset↔
pipeline map) and mac4DSTEMUITests/QCPlaythroughUITests.swift.

Goal: run the QC playthrough across ALL .h5 files in
References/training_dataset, with each dataset routed to the analysis
pipeline appropriate to its structure (per §6): e.g. sim_Au → ACOM,
polycrystal_2D_WS2 → ACOM+strain, downsample_Si_SiGe_exp → strain,
Particle_..._300kV → virtual imaging (+ strain/ACOM if crystalline).

Constraints:
  - EVALUATION ONLY — do not modify anything under mac4DSTEM/. Test target +
    runner + docs only.
  - Robustness is essential: a failure on one datacube must log and continue
    to the next (the harness already does this — verify it holds at scale).
  - These files are large (0.5–1.3 GB) and runs are slow; use generous
    timeouts (already 240–600 s per heavy step).

How to run: tools/ui-qc-playthrough/run.sh   (no argument = all datasets).
Or a subset by substring. Outputs land per-datacube under
References/training_runs/run_<timestamp>/.

Done when: every datacube has a folder with screenshots, exports, and a
log.md; failures are captured (not aborting the run); and a short summary of
per-dataset results is added to docs/py4dstem-pipelines.md §9.
```

---

## PROMPT 3 — Turn the findings into a ranked UI/workflow backlog

```
Work in the mac4DSTEM repo. Read docs/py4dstem-pipelines.md in full,
especially §7 (UI observations) and §8 (scope/roadmap), plus §9 (empirical
findings). Also skim App/ProductWorkflow.swift and the UI/ views to ground
each item in real code.

Goal: produce docs/ui-workflow-backlog.md — a ranked, actionable backlog that
turns the §7 findings into concrete UI/workflow changes. For each item give:
  - the finding it addresses,
  - the concrete change (which workspace/view/label/gate),
  - the layer it touches (UI-only vs AppState/ProductWorkflow workflow logic),
  - a "core untouched" note confirming no Core/ algorithm change,
  - rough effort (S/M/L) and value (user-impact) → a priority.

Constraints:
  - This is a DOCUMENTATION task — write only under docs/. Do not change app
    or test code.
  - Be honest about which items are pure presentation vs which need workflow-
    state changes in AppState/ProductWorkflow (see §8.2 of the pipelines doc).

Done when: docs/ui-workflow-backlog.md exists with items ranked by priority,
each mapped to real files, and a one-paragraph "recommended first three".
```

---

## PROMPT 4 — Round out the ACOM pipeline (full-scan + IPF display)

```
Work in the mac4DSTEM repo. Read docs/py4dstem-pipelines.md §3 (ACOM) and
§9.1 (the clean sim_Au run), then mac4DSTEMUITests/QCPlaythroughUITests.swift
(runOrientationMap) and mac4DSTEMUITests/Support/AXDriver.swift.

Goal: the current ACOM run uses Preview scope (a 525-position subset) and
exports the Reliability map. Extend it to also:
  - run a FULL-SCAN orientation map (acom.scope segmented control → full-scan
    option), and
  - capture the IPF-Z orientation coloring display (not just Reliability).
Export both and screenshot them.

Constraints:
  - EVALUATION ONLY — test target + runner + docs only; no app changes.
  - acom.scope is a segmented control (AXRadioGroup) whose selection does not
    surface as text; select the option by its visible label. The ACOM display
    mode picker may not have an accessibility identifier — if you cannot
    reach it via UI, log that as a finding rather than modifying app code.
  - Full-scan ACOM on real data is slow; use a generous timeout (>=600 s).

How to run: tools/ui-qc-playthrough/run.sh sim_Au   (iterate until clean).

Done when: a full-scan orientation map and an IPF-Z map are produced and
exported for sim_Au, screenshots captured, and findings noted in
docs/py4dstem-pipelines.md §9.
```
