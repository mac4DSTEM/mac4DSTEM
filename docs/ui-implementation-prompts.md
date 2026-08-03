# UI implementation — reusable prompts for future sessions

Hand any prompt below to a **fresh agent on an empty context**. Each is
self-contained: it names the files to read first, the constraints, the review
gate, how to verify, and the definition of done.

**Where this lives:** `docs/ui-implementation-prompts.md` (this file). This is
the **single source of truth for implementation-phase status** — update the
checklist below when a task lands.

**How this differs from `docs/qc-playthrough-prompts.md`.** That file drove the
*evaluation* phase (Thread B), which was eval-only: it never touched
`mac4DSTEM/`. All four of its prompts are complete. **This file drives the
phase that acts on what the evaluation found** — so app code *does* change
here, which means tests and review gates now apply where they did not before.
The QC playthrough becomes the acceptance test rather than the deliverable.

## Session kickoff prompt (copy-paste to start a session)

```
Pick up the mac4DSTEM project. Read CLAUDE.md first, then
docs/ui-implementation-prompts.md — read its Status checklist and take the
next unchecked task, copying its prompt and executing it end to end.

This phase CHANGES APP CODE (unlike the finished QC-playthrough phase), so
follow docs/development-process.md properly: Explore subagent (Haiku) to
locate code, implement on the default model, and take the review gate the
prompt names before you call it done. Never let the model that wrote a
science-affecting change be the only one that approves it.

Run the "Task closeout" checklist at the top of
docs/ui-implementation-prompts.md exactly, then stop with a short summary.
Commit only if I ask.
```

## Status — what's done, what's next

- ⬜ **Prompt A — close the parity wire** (`tools/` only, no app change).
  Recommended first: it is the cheapest, and everything after it is easier to
  trust once it exists.
- ⬜ **Prompt B — task prerequisite checklists** (backlog #7, #1). First app
  change of this phase.
- ⬜ **Prompt C — defaults that don't generalize** (backlog #5, #8). Spike
  first — this one may not be "core untouched".
- ⬜ **Prompt D — accessibility & control labelling** (v1 release gate,
  backlog #3).
- ⬜ **Prompt E — result labelling & presentation batch** (backlog #2, #4, #6,
  #9, #10, #12, #13).

Backlog items #11 (WS₂ crystal model) is **not** in this phase — it is
governed by `ROADMAP.md` Priority 1.3, which already sets the bar for admitting
a new phase (explicit lattice, atomic basis, symmetry reduction, structure
factors, expected-orientation fixture, fit-overlay acceptance). Treat it as a
separate, roadmap-level decision, not UI work.

## Task closeout — run these EXACT steps at the end of every task

This phase touches app code, so the closeout is stricter than the QC phase's.
Do all of it before stopping:

1. **Tick the box** in the Status checklist above (⬜ → ✅) and name the run
   folder / test output the task produced.
2. **Close the backlog items** in `docs/ui-workflow-backlog.md` — mark each
   addressed item done with a one-line note on what actually shipped (which may
   differ from what the item proposed; say so).
3. **Run the tests the change earns:**
   - `tools/run-tests.sh unit` — always.
   - `tools/run-tests.sh scientific` — if anything under `Core/` changed.
   - Name any harness you had to add.
4. **Re-run the QC playthrough as the acceptance test:**
   `tools/ui-qc-playthrough/run.sh` (no argument), then **diff against the
   baseline `References/training_runs/run_2026-08-03_1404/`**
   (`docs/py4dstem-pipelines.md` §9.3). Every number that moves must be
   explained: peak counts, Q pixel sizes, ACOM position counts, strain
   diagnostics. A number that changes without a reason is a regression, not a
   success.
5. **Take the review gate the prompt names** (see `docs/development-process.md`
   §2). Do not skip it because the build is green — a green build is not proof
   of parity.
6. **Update the docs the change affects** — at minimum this file and the
   backlog; also `README.md`/`CLAUDE.md` if structure moved.
7. **Do NOT commit** unless the user asks. Leave the working tree for review.
8. **Stop with a short summary**: what changed, what the tests/QC diff showed,
   what the next unchecked task is.

If a task can't finish, leave its box unchecked, write why in the backlog item,
and stop — never mark done what isn't.

## Hard rules for this phase

The QC phase had one hard rule ("don't touch `mac4DSTEM/`"). That rule is now
lifted, and these replace it:

- **The scientific core stays frozen unless a prompt says otherwise.** The
  algorithms in `Core/` are validated by 25 harnesses in `tools/run-tests.sh
  scientific`. A UI/workflow task that finds itself editing `Core/Analysis` has
  either found a real bug (stop and say so) or drifted out of scope.
- **Any `Core/` or science-affecting change gets an adversarial review** — a
  high-end model prompted to *refute* that the port still matches py4DSTEM,
  plus a parity fixture in `tools/`. Non-negotiable (`development-process.md`
  §2).
- **Don't widen scientific-state mutation access** to reduce line counts
  (ROADMAP P3.2). Extract only at a green test boundary.
- **Metal parameter structs in `MetalEngine.swift` stay byte-for-byte
  identical** to their `.metal` counterparts.
- **Behaviour-preserving means measured, not asserted.** The QC diff in
  closeout step 4 is how you show it.
- **Every change must close a gap in `docs/v1-scope.md`** or it is post-v1
  (ROADMAP scope rule).

## Shared context (every prompt already references this — here for you)

- The app is **mac4DSTEM**, a macOS 4D-STEM analysis app; workspaces
  **Prepare → Image / Map / Reconstruct → Results**.
- **The findings driving this phase** are in `docs/py4dstem-pipelines.md` §9.2
  (strain/DPC/reconstruct across all four datasets), §9.3 (the whole-suite
  baseline run) and §9.4 (full-scan + IPF·Z ACOM).
- **The backlog** is `docs/ui-workflow-backlog.md` — 13 ranked items, each
  mapped to real files with a "core untouched" note.
- **The acceptance test** is `tools/ui-qc-playthrough/run.sh`, baseline
  `References/training_runs/run_2026-08-03_1404/`.
- **Known harness flake:** `run.sh` ad-hoc re-signs the runner each invocation,
  which can invalidate its Accessibility grant — a run that dies with "Timed
  out while enabling automation mode" before launching the app should simply be
  rerun once (§9.2.2).
- **A caveat to hold onto:** the QC harness measures *reachability*, not
  *discoverability*. It knows every identifier and prerequisite in advance, so
  it can prove a flow is completable and cannot prove a label is
  understandable. Items about sequencing/gating (#7, #1, #5) rest on strong
  evidence; items about wording and grouping (#4, #6, #12) are educated guesses
  — treat them as hypotheses and say so if the code disagrees.

---

## PROMPT A — Close the parity wire (§10)

```
Work in the mac4DSTEM repo. Read docs/py4dstem-pipelines.md §10 (the closed
evaluation loop and its "missing wire"), then §9.2–§9.4 for what the UI track
currently produces, then tools/training-dataset-campaign/ (run.sh, main.swift,
verify_py4dstem.py, manifest.json) for what the parity track currently checks.

The problem: these are two evidence streams that nobody joins. The UI
playthrough proves the app produced a result and labelled it Physical /
Quantitative. The campaign proves algorithms match py4DSTEM on fixtures. But
the specific outputs a user actually looks at — the sim_Au strain map (52%
indexed, RMS 1.06 px, kappa 4.78) and the full-scan ACOM orientation map — have
NO parity number attached to them anywhere.

Goal: make a UI-QC finding citable against py4DSTEM for the same dataset, so a
finding can read "this step is confusing AND its output is within X% of
py4DSTEM" instead of just the first half.

Suggested shape (choose what actually fits the existing harnesses — do not
rebuild what tools/training-dataset-campaign already does):
  - Extend the campaign to cover the products the QC run exports for the same
    training datasets (at minimum: strain on sim_Au, full-scan ACOM on sim_Au),
    reading them back through py4DSTEM the way verify_py4dstem.py already does.
  - Emit a small machine-readable parity record per dataset+product
    (dataset, product kind, metric, value, tolerance, pass/fail).
  - Have the QC playthrough log cite that record when one exists for the
    datacube it just ran — a line in the per-datacube log.md is enough.

Constraints:
  - tools/ + docs/ + mac4DSTEMUITests/ only. NO app-code change under
    mac4DSTEM/ — this task adds evidence, it does not alter behaviour.
  - Do not invent tolerances. Derive them from what the existing harnesses
    already use, or state plainly that a tolerance is a first proposal and why.
  - If a product genuinely cannot be compared (no py4DSTEM equivalent, or the
    app's variant differs by design), say so explicitly and record it as a
    known non-comparable rather than forcing a number.

Review gate: /code-review (Opus). This is evidence infrastructure, not app
logic, so no adversarial parity review is required — but if you find a real
numerical disagreement, STOP and report it rather than adjusting a tolerance to
make it pass. A disagreement here is the most valuable thing this task can
produce.

How to run: tools/run-tests.sh scientific (and the campaign's own run.sh).

Done when: at least one QC-exported product per crystalline dataset carries a
py4DSTEM parity number, the mechanism is documented in
docs/py4dstem-pipelines.md §10 (replacing the "missing wire" paragraph), and
any disagreement found is reported rather than tuned away.
```

---

## PROMPT B — Task prerequisite checklists (backlog #7 + #1)

```
Work in the mac4DSTEM repo. Read docs/ui-workflow-backlog.md items #7 and #1,
then docs/py4dstem-pipelines.md §9.2 (the per-dataset prerequisite table), then
App/ProductWorkflow.swift (the `prerequisites(for:)` function),
UI/CalibrationReadinessView.swift (the readiness-checklist pattern to copy) and
UI/ProductWorkspaceViews.swift (the workspace.primaryAction site).

The problem, measured: on ALL FOUR training datasets the Reconstruct primary
action rendered as a disabled "Prepare Preview" with nothing on screen saying
why — and the missing prerequisite was DIFFERENT every time (sim_Au: R pixel
scale only; WS2: Q + R; Si_SiGe: origin + R; Particle_1: origin + Q). ACOM has
the same shape of problem: it needs Bragg vectors and a phase model, and
without them the earliest QC runs clicked it and got silence.

The app ALREADY COMPUTES the exact answer — prerequisites(for:) returns strings
like "Set the R pixel scale". They are simply never rendered.

Goal: render them. Build ONE generic mechanism that shows, under any task's
primary action, the unmet prerequisites as a checklist, each row linking to the
control that satisfies it. Then it serves Reconstruct, ACOM, strain and anything
added later — do not special-case two tasks.

Constraints:
  - UI + light workflow state only. Core/ untouched.
  - Behaviour-preserving for the enabled path: a task whose prerequisites are
    met must behave exactly as before.
  - Do not change WHAT the prerequisites are in this task. If you believe one is
    wrong (e.g. whether parallax truly needs BOTH R and Q scale), that is a
    finding to raise, not a change to make here.
  - Reuse CalibrationReadinessView's visual language rather than inventing a
    second checklist idiom.

Review gate: /code-review (Opus). This is app logic (workflow layer), so do not
self-approve.

How to verify: tools/run-tests.sh unit, then the QC playthrough with no
argument, diffed against References/training_runs/run_2026-08-03_1404/. The
scientific numbers MUST NOT move. What should change is the QC log: the
Reconstruct step should now be able to name its blocker from the UI instead of
the test dumping the whole calibration panel to infer it.

Bonus signal that this worked: mac4DSTEMUITests/QCPlaythroughUITests.swift
currently navigates to Prepare and dumps the calibration panel to figure out
why Reconstruct is disabled. If the checklist makes that detour unnecessary,
simplify the test to read the checklist instead — a shorter test is the
acceptance evidence.

Done when: every task with unmet prerequisites names them on screen with a way
to fix each; the QC diff shows no scientific change; backlog #7 and #1 are
marked closed with what actually shipped.
```

---

## PROMPT C — Defaults that don't generalize (backlog #5 + #8)

```
Work in the mac4DSTEM repo. Read docs/py4dstem-pipelines.md §9.2.1 (three
different causes behind one error message) and §9.2.2, then backlog #5 and #8,
then UI/ContentView.swift Strain section (L238-331),
UI/DiskDetectionControls.swift, and Core/Analysis/StrainMapping.swift (READ
ONLY at first — see the spike below).

The problem, measured across all four datasets with the app's own defaults
(whole-scan mean reference + automatic basis):
  - sim_Au: strain SUCCEEDS (52% indexed, 100% basis support, kappa 4.78).
  - Si_SiGe and Particle_1: FAIL. Input is fine — median 12 and 16 peaks per
    pattern, 0% empty positions — but the whole-scan AVERAGE lattice is
    ill-conditioned. py4DSTEM's strain_01_Si_SiGe.ipynb picks g1,g2 from an
    unstrained reference REGION for exactly this reason.
  - polycrystal_2D_WS2: FAILS differently. Median 1.0 peaks per pattern over
    16,384 positions — the disk-detection defaults found essentially only the
    direct beam. This is a detection-parameter problem, not a strain problem,
    and nothing at the detection step flags it.
All three produce the SAME error text, which names two unrelated remedies and
points at a panel in a different task.

START WITH A SPIKE, NOT CODE. Backlog #5/#8 frame this as guidance/labelling
with "core untouched", and that framing may be too optimistic: better
sign-posting helps a user who already knows what to change, but it does not fix
defaults that are wrong on three of four datasets. Use a Plan subagent (Opus)
to decide and write a short docs/ note answering:
  1. Is this fixable purely as guidance + better-targeted error messages?
  2. Or does it need adaptive/derived defaults (e.g. detection thresholds scaled
     from the measured probe and pattern statistics), which reaches into
     Core/Analysis and therefore needs a parity fixture + adversarial review?
  3. What does py4DSTEM itself do — does it have generalizing defaults, or does
     every tutorial hand-tune per dataset? (Check the notebooks. If py4DSTEM
     hand-tunes too, then "good guidance" IS the correct answer and option 2 is
     over-engineering.)
Decide explicitly, record the decision and the reason, THEN implement.

Whatever the decision, these are in scope:
  - Show a peaks-per-pattern quality read-out on the disk-detection result with
    a warning when it is implausibly low. The number already exists (it appears
    in the strain error text) — surface it at the step that produced it.
  - Split the strain failure message so a starved-input failure and an
    ill-conditioned-basis failure say different, specific things.
  - Make the Reference/Basis choice legible as the scientific decision it is
    ("Reference defines zero strain"), per §4's reference options.

Constraints:
  - If the spike concludes Core/ must change, that is ALLOWED here — but then
    it needs a parity fixture in tools/ and an adversarial review (a high-end
    model prompted to REFUTE that the port still matches py4DSTEM). Do not
    quietly change a default that affects scientific output without it.
  - Do not tune a default just to make the QC run green. The QC run is evidence,
    not a target.

Review gate: /code-review (Opus) for the UI half; if Core/ changed, ALSO an
adversarial parity review (Fable 5 — this is the highest-stakes case in the
backlog, because it changes numbers users will publish).

How to verify: tools/run-tests.sh unit and scientific, then the QC playthrough
with no argument vs References/training_runs/run_2026-08-03_1404/. Here, unlike
Prompt B, numbers ARE expected to move — every moved number must be explained
and justified as more correct, not merely greener.

Done when: the decision is recorded with its reasoning; the three failure modes
are distinguishable from the UI; and either strain succeeds on more datasets
with a defensible reason, or it is documented why the remaining failures are
the correct scientific outcome.
```

---

## PROMPT D — Accessibility & control labelling (v1 release gate + backlog #3)

```
Work in the mac4DSTEM repo. Read docs/v1-scope.md ("Mac experience" release
gate — "the primary workflow is usable with VoiceOver and increased text
size"), then docs/py4dstem-pipelines.md §9.2.2 and §9.4 (the "mechanical note"
paragraphs), then backlog #3.

The signal: the QC harness could not reach several controls by accessibility
identifier and had to locate them STRUCTURALLY — by finding a nearby visible
label and taking the control on the same row. The controls are:
  - the accelerating-voltage field (UI/ContentView.swift:344) — its label is a
    separate Text("Voltage") in an HStack, so the field's own title is empty;
  - the Strain Reference / Basis / Component pickers (UI/ContentView.swift:240,
    251, 289);
  - the ACOM display-mode picker (UI/ACOMControlsView.swift:227) — no
    identifier, and its "Display" label collides with a sidebar section header;
  - the strain diagnostics and ACOM Work/Expected LabeledContent rows.

This was logged as an automation inconvenience. It is very likely also a
VOICEOVER problem: a control whose only label is a detached sibling Text may not
be announced with its label. That is an explicit v1 release gate that nothing
in the repo currently tests.

Goal, in this order:
  1. VERIFY FIRST, with VoiceOver actually running, whether these controls are
     announced correctly. Do not assume. Report what you observe — if VoiceOver
     handles them fine, say so plainly and the rest of this task shrinks to
     adding identifiers.
  2. Fix what is genuinely broken: proper label association (accessibilityLabel
     or a real Picker/TextField label rather than a detached Text), and add
     accessibility identifiers to the controls above.
  3. Check increased text size (Larger Accessibility Sizes) on the primary
     workflow — the sidebar packs many compact rows and is the likely casualty.

Constraints:
  - UI only. Core/ untouched. This is labelling and layout, not behaviour.
  - Adding an identifier is an APP change, which is why it belongs here and not
    in the (finished) eval-only QC phase.
  - Do not remove the QC harness's structural lookups when you add identifiers —
    leave AXDriver.control(_:inRowWithLabel:) in place. It is the fallback that
    made this finding possible, and it will find the next unlabelled control.

Review gate: /code-review (Opus), plus your own VoiceOver observations recorded
in the summary — the review cannot verify those for you.

How to verify: tools/run-tests.sh unit, then the QC playthrough (no argument)
vs References/training_runs/run_2026-08-03_1404/ — no scientific number should
move. Optionally simplify the harness to use the new identifiers where they
now exist.

Done when: the VoiceOver behaviour of those controls is documented (fixed or
confirmed fine), identifiers exist, increased-text-size behaviour on the
primary workflow is reported, and backlog #3 is closed with what shipped.
```

---

## PROMPT E — Result labelling & presentation batch (backlog #2, #4, #6, #9, #10, #12, #13)

```
Work in the mac4DSTEM repo. Read docs/ui-workflow-backlog.md items #2, #4, #6,
#9, #10, #12 and #13, plus ROADMAP.md Priority 2 (product clarity) — especially
P2.3, "use persistent result labels (Quantitative, Relative, Exploratory,
Categorical) instead of relying on units or transient guidance text".

These are the lower-risk presentation items, batched because each is small and
they touch overlapping files. Do them as separate commits-worth of work even if
you do not commit, and feel free to drop any that the code contradicts — they
are the weakest-evidence items in the backlog (see the reachability-vs-
discoverability caveat in the Shared context above).

In rough value order:
  - #9 A failed compute should not block the whole window. Measured: a strain
    failure raises a window-modal sheet that swallowed every later interaction
    and cost a whole datacube's run. Demote recoverable compute failures to the
    existing non-blocking status bar + log pane; keep the modal for failures
    that invalidate the session.
  - #2 Make "Calibrate Q from Selected Material" the obvious path rather than a
    late-appearing action beside a manual field that reads as primary.
  - #12 Revisit the ACOM Preview/Reliability defaults. Measured: the full 84x100
    scan matched in 0.7 s — Preview scope is protecting the user from a
    sub-second wait while costing them the full-resolution map.
  - #13 Give a full-scan ACOM result a scope qualifier. Measured: preview
    publishes "ACOM preview - Reliability" but full scan publishes plain
    "ACOM - Reliability", so the MOST complete product is the LEAST labelled.
    CAUTION: the export `kind` string is persisted, so changing it is a
    compatibility question — the display-name half is safe alone and is the
    higher-value part. Check session reopen before touching `kind`.
  - #10 Surface R pixel scale provenance and conflicts (Particle_1 imports
    49.5 nm/px from file while its filename says ss30nm).
  - #4 Group tasks by prerequisite family (Bragg path vs phase-contrast path).
  - #6 In-flow "next step" hints. Explicitly NOT recommended: re-ordering the
    top-level workspaces.

Constraints:
  - UI only, Core/ untouched, except #9 which touches AppState.present(error:).
  - #13's `kind` change must not break reopening an existing saved session.
  - Any item whose premise the code contradicts: drop it and say why. Do not
    implement a change you do not believe in because a doc listed it.

Review gate: /code-review (Opus). #13 additionally needs a session
save-and-reopen check if you change the persisted `kind`.

How to verify: tools/run-tests.sh unit, then the QC playthrough (no argument)
vs References/training_runs/run_2026-08-03_1404/. Scientific numbers must not
move. Result TITLES are expected to change (#13) — update the harness's title
waits accordingly, and note the change in docs/py4dstem-pipelines.md §9.4,
which documents the current naming.

Done when: each item is either shipped or explicitly dropped with a reason, the
QC diff shows no scientific change, and the backlog reflects reality.
```
