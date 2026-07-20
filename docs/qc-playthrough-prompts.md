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
- ⬜ **Prompt 1 — strain + phase-contrast pipelines** (recommended next: strain
  is closest, it reuses the proven disk-detection step).
- ⬜ **Prompt 2 — fan out to all datasets.**
- ⬜ **Prompt 4 — full-scan + IPF ACOM.**

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
