# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff prompt (copy-paste to start a session)

```
Pick up the mac4DSTEM project. Read CLAUDE.md first (app overview, the two
work-threads, file-placement rules, hard rules, process). Then open
docs/ui-implementation-prompts.md, read the Status checklist, and take the
next unchecked task — copy its prompt and execute it end to end.

This phase CHANGES APP CODE (the eval-only QC phase is finished), so follow
docs/development-process.md properly: use an Explore subagent (Haiku) to
locate code, implement on the default model, and take the review gate the
prompt names — /code-review for app logic, and an adversarial parity review
plus a tools/ fixture for anything touching Core/ or the science. Never let
the model that wrote a science-affecting change be the only one to approve it.

When the task lands, run the "Task closeout" checklist at the top of
docs/ui-implementation-prompts.md exactly (tick the box, close the backlog
items, run the tests the change earns, re-run the QC playthrough and diff it
against References/training_runs/run_2026-08-03_1404/, take the review gate,
do not commit), then stop with a short summary. Commit only if I ask.
```

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Two threads (this is the mental model)

The repo holds two related bodies of work. Knowing which one you're in
removes most of the confusion:

- **Thread A — the app itself.** v1 is implemented and in *stabilization*
  (scientific-contract polish, UI consolidation, distribution readiness).
  Governed by `ROADMAP.md` (3 standing priorities) and `docs/v1-scope.md`
  (frozen release contract). This is the long-lived product.
- **Thread B — the QC-playthrough evaluation → UI improvement.** We drive the
  real app through the canonical py4DSTEM analysis pipelines (an XCUITest that
  watches on screen), compare against py4DSTEM, and turn every workflow
  friction into a UI/workflow improvement. **Thread B feeds Thread A's
  Priority 2 (product clarity).** It has **two phases**: the *evaluation*
  phase (finished — eval-only, never modified app logic) and the
  *implementation* phase (current — it does change app code).

## Where v1.0 stands (2026-08-05)

`tools/run-tests.sh all` is **green — exit 0, 30 harnesses**. Five things stand
between the repo and v1.0, listed with their blockers in
**`docs/ui-implementation-prompts.md` § "Road to v1.0"**, which also carries the
recommended order for the next session. The short version: the **QC playthrough
acceptance re-run has not executed since 2026-08-04** and is the main
verification debt; it and the two open layout bugs (#16/#22) are blocked on the
same **Accessibility permission**. **`/code-review` is the designated final gate
before v1.0** and is user-invoked — an agent cannot launch it, and nothing
should be called v1.0-complete before it has run.

## Current initiative (Thread B) — start here for "what do I do next"

- **Next actions + live status — cold-start prompts for a fresh agent:**
  **`docs/ui-implementation-prompts.md`** (the *current* phase — acts on what
  the evaluation found; app code changes here, so tests and review gates
  apply). It carries the authoritative "what's done / what's next" checklist
  and five self-contained task prompts; hand one to a new session. Read its
  Status section first — don't restate status here.
- **The finished evaluation phase:** `docs/qc-playthrough-prompts.md` — all
  four prompts complete. Still the reference for *how the harness is driven*
  and for its eval-only rules.
- **What it is + all pipelines, step by step:** `docs/py4dstem-pipelines.md`
  (also holds the app-vs-py4DSTEM findings §7, the scope/roadmap §8, and the
  empirical run findings §9).
- **The UI backlog these findings produced:** `docs/ui-workflow-backlog.md`
  (13 ranked items, each tagged UI-only vs workflow-logic, core-untouched).
- **The harness + how to run it:** `mac4DSTEMUITests/` +
  `tools/ui-qc-playthrough/run.sh [dataset-substring]`. It is now the
  **acceptance test** for the implementation phase; baseline to diff against is
  `References/training_runs/run_2026-08-03_1404/` (§9.3).
- Session memory (direction + gotchas):
  `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM/memory/qc-playthrough-pipeline-eval.md`.

## Standing references (Thread A)

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities and the scope rule.
- **`docs/v1-scope.md`** — the frozen v1 release contract. Consult when
  deciding whether a proposed change is in scope (ROADMAP's scope rule points
  here); not a "read first" doc.
- **`docs/post-v1-ideas.md`** — parking lot for ideas that are out of v1 scope
  *and* would touch `Core/` (cropping, partial/binned loading). Deliberately
  separate from `docs/ui-workflow-backlog.md`, which is contractually
  UI/workflow-only and must stay safe to hand out as implementation prompts.
  Nothing here is committed to; entries record the non-obvious constraints so a
  later session doesn't rediscover them.

## Where things go (file-placement rules)

The Xcode project uses **synchronized folder groups**: any file placed under
`mac4DSTEM/` auto-joins the app target, and `.metal` files auto-route to the
Metal compile phase. So placement *is* wiring — put files in the right folder
and they build.

| Putting in… | goes under… |
|-------------|-------------|
| App entry, window/workflow state (`AppState`), recovery | `mac4DSTEM/App/` |
| Readers (H5/DM4/vendor), calibration model, EMD writer, product model | `mac4DSTEM/Core/Data/` |
| GPU/Metal engine, FFTs, multicorr, cancellation | `mac4DSTEM/Core/Compute/` |
| Analysis algorithms (virtual detector, calibration solvers, disks, strain, DPC, parallax, ptycho) | `mac4DSTEM/Core/Analysis/` |
| Crystal models, scattering factors, ACOM matching | `mac4DSTEM/Core/Crystal/` |
| Operation-lifecycle controllers | `mac4DSTEM/Core/Workflow/` |
| Metal kernels (`.metal`) | `mac4DSTEM/Shaders/` |
| SwiftUI views, viewers, controls, inspectors | `mac4DSTEM/UI/` |
| Export, system monitor, bridging header | `mac4DSTEM/Support/` |
| Fast unit / workflow-contract tests (logic, invisible, in-process) | `mac4DSTEMTests/` |
| UI automation / visible QC playthrough (whole app, on-screen) | `mac4DSTEMUITests/` |
| Standalone parity / dev / packaging harnesses | `tools/<name>/` (add to `tools/run-tests.sh` if it should gate) |
| Human design/scope/process docs | `docs/` (dated or superseded → `docs/archive/`) |
| Vendored external material + machine-local data (gitignored) | `References/` |

## Hard rules

- **Views describe UI only.** Loading/parsing/compute live in `Core`.
  `AppState` (`@Observable`) is the single source of truth.
- **The QC playthrough (`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/`) is
  evaluation only** — never modify app logic under `mac4DSTEM/` to make a QC
  step pass. If the app blocks the pipeline, that's a *finding* for
  `docs/ui-workflow-backlog.md`, not a code change.
- **Metal parameter structs in `MetalEngine.swift` must stay byte-for-byte
  identical** to the matching `.metal` structs (all 4-byte fields).
- **Don't widen scientific-state mutation access** just to reduce line counts
  (ROADMAP P3.2). Extract only at a green test boundary.
- **Don't add `CODE_SIGNING_ALLOWED=NO` to an app build you intend to launch**
  — use `tools/run-tests.sh unit` for unsigned XCTest work.
- **Port deviations from py4DSTEM get an inline `DEVIATION` note** with the
  reason.
- **Keep docs current as part of "done"** — no file self-updates. When a task
  lands, tick the status checklist in `docs/qc-playthrough-prompts.md` and
  update the doc it affects. Full conventions (model/subagent tiers, review
  gates, where new work goes, delivery): **`docs/development-process.md`**.
- Commit/push only when asked; this is a solo-dev repo with linear `main`.

## Build / test / run

```sh
# build (needs full Xcode toolchain)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build

tools/run-tests.sh unit          # fast XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific    # py4DSTEM-parity harnesses
tools/run-tests.sh all           # aggregate acceptance gate
tools/ui-qc-playthrough/run.sh [dataset-substring]   # visible QC playthrough (separate; not in run-tests.sh)
```

## Long-term goals

Three standing priorities (full text in `ROADMAP.md`): **(1) scientific
interpretation** — every result keeps its model/scale/units/validity through
display, export, and reopen; **(2) product clarity** — task-scoped controls,
persistent result labels, visible diagnostics; **(3) incremental architecture**
— shrink the `AppState` facade only at green test boundaries. Any new feature
must close a gap in `docs/v1-scope.md`, else it is post-v1.
