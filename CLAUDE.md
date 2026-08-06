# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff prompt (copy-paste to start a session)

**v1.0.0 is tagged (2026-08-06).** The active work is the load pipeline.

```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/load-pipeline-plan.md — it is the
active plan (load progress, resident cube, crop/bin on open). Read §1–§4 for the
constraints, then the Status checklist in §5, and take the next unchecked stage.
docs/open-items.md is the live list for everything else.

This changes app code, so follow docs/development-process.md, and take the
review gate the stage names. Commit only if I ask.
```

Whatever the task: app-code changes follow `docs/development-process.md` —
Explore subagent (Haiku) to locate code, implement on the default model, and
take the review gate the work earns. Anything touching `Core/` or the science
needs an adversarial review *and* a `tools/` fixture. Never let the model that
wrote a science-affecting change be the only one to approve it — this refuted a
fix **twice** (2026-08-05, 2026-08-06), and both times the fix had already
passed every test written for it, including one verified to fail without it.
**Review the diagnosis, not just the code.** On 2026-08-06 the refuting evidence
— an origin fit residual printed in the very log the finding came from — had
been sitting in plain sight the whole time.

And **open the app.** On the day of the v1.0.0 tag, with all 30 harnesses green,
ten minutes of driving it by hand produced two defects the suite could not see.
There is no visual QC baseline (see `docs/open-items.md`), so nothing but a
person looking at the screen catches that class of bug.

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Where things stand

**v1.0.0 — tagged 2026-08-06.** What it is: [`CHANGELOG.md`](CHANGELOG.md).
`tools/run-tests.sh all` — exit 0, 30 harnesses.

Two things outlive the tag and neither blocks anything:

1. **Distribution** — Developer ID signing, notarization, clean-account launch.
   Release-owner actions against the existing tag; they change no source.
2. **The load pipeline** — [`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md),
   the active plan and the one that *does* touch `Core/`: load progress, a
   resident in-memory cube with a streaming fallback, and crop/bin-on-open.

The QC playthrough (`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/run.sh`) is
**the acceptance test**. It drives the real app through the canonical py4DSTEM
pipelines and logs every number it reads from the app's own controls. Its
eval-only rule stands: never change app code to make a QC step pass — that is a
finding, not a bug fix. It has never been run with screenshots, so v1.0.0 has
**no visual baseline**; that is recorded, deliberate, and the first item in
`docs/open-items.md`.

## Where things are written down

- **[`CHANGELOG.md`](CHANGELOG.md)** — what v1.0.0 is, and what it was *not*
  verified by. Start here for scope.
- **[`docs/open-items.md`](docs/open-items.md)** — everything still live, and
  the working methods that earned their keep. **The only maintained status
  doc.**
- **[`docs/v2-planning-draft.md`](docs/v2-planning-draft.md)** — **DRAFT, not
  decided.** Proposals for how a second phase should run: version policy,
  splitting test automation into a numeric track and a human visual track, a
  two-dataset default, and a per-stage rule for shrinking `AppState`. Written
  2026-08-06 so a planning session can react rather than start blank. **If that
  session has happened, its outcomes live in `docs/v2-scope.md` and
  `docs/development-process.md` and this file should be deleted.**
- **[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)** — **the active
  feature plan**: honest load progress, a resident in-memory cube with a
  streaming fallback, and crop/bin-on-open driven from a preview. Six staged
  prompts (L1–L6), the invariants, why the app is out-of-core, and where
  py4DSTEM must *not* be copied. **The active plan.**
- **`docs/py4dstem-pipelines.md`** — the pipelines step by step, the
  app-vs-py4DSTEM findings (§7), scope/roadmap (§8), empirical run findings
  (§9).
- **`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/run.sh [dataset-substring]`**
  — the on-screen acceptance playthrough. `--no-screenshots` trades the visual
  evidence for the numbers when the runner lacks a Screen Recording grant; the
  log says so loudly. Baseline for diffs:
  `References/training_runs/run_2026-08-03_1404/`, but read `open-items.md`
  first — that baseline predates a deliberate disk-detection change, so peak
  counts legitimately differ.
- **[`docs/archive/v1.0/`](docs/archive/v1.0/)** — the v1.0 phase's working
  memory: 46 numbered findings, the design passes, the QC-evaluation prompts.
  **History, not guidance.** Nothing current points into it; consult it for
  *why* a decision was made, never for what to do next.
- Session memory (direction + gotchas):
  `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM/memory/`.

## Standing references

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities and the scope rule.
- **`docs/v1-scope.md`** — the frozen v1 release contract. Consult when
  deciding whether a proposed change is in scope (ROADMAP's scope rule points
  here); not a "read first" doc.
- **`docs/v2-onramp.md`** — the handover written for a second development
  phase. Its *status* sections are superseded by `docs/open-items.md`; keep it
  for the grouping of open threads by what each actually needs (scope decision /
  harness confidence / small and known).
- **`docs/post-v1-ideas.md`** — parking lot for ideas that are out of v1 scope
  *and* would touch `Core/` (cropping, partial/binned loading). Deliberately
  separate from `docs/open-items.md`, which is contractually
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
  `docs/open-items.md`, not a code change.
- **Metal parameter structs in `MetalEngine.swift` must stay byte-for-byte
  identical** to the matching `.metal` structs (all 4-byte fields).
- **Don't widen scientific-state mutation access** just to reduce line counts
  (ROADMAP P3.2). Extract only at a green test boundary.
- **Don't add `CODE_SIGNING_ALLOWED=NO` to an app build you intend to launch**
  — use `tools/run-tests.sh unit` for unsigned XCTest work.
- **Port deviations from py4DSTEM get an inline `DEVIATION` note** with the
  reason.
- **Keep docs current as part of "done"** — no file self-updates. When a task
  lands, update **`docs/open-items.md`** (add, amend, or delete the item) and
  any reference doc it affects. Do **not** edit `docs/archive/v1.0/` — it is a
  frozen record of the v1.0 phase. Full conventions (model/subagent tiers,
  review gates, where new work goes, delivery):
  **`docs/development-process.md`**.
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
