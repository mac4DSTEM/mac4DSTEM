# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff prompt (copy-paste to start a session)

**The v1.0 development phase is closed, and feature work has reopened on the
load pipeline.** The two are independent — the tag does not gate the feature
and the feature does not gate the tag. Which prompt you want depends on what
you're doing:

**Finishing v1.0** (one defect, then distribution):
```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/open-items.md — it is the live
list and it is short. One thing blocks the tag: #46, a Q pixel size derived
from an origin whose fit residual exceeds the probe radius, still stamped
"Measured in app". Read its "do not retry" note before proposing anything;
the obvious fix was tried on 2026-08-06 and refuted.

Code review of a9e4268..HEAD is DONE (2026-08-06) with one low-severity
finding. The QC playthrough is green on all four datasets, numbers-only —
there is no visual baseline yet. Do not commit or tag unless I ask.
```

**Building the load pipeline** (progress, resident cube, crop/bin on open):
```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/load-pipeline-plan.md — it is the
active feature plan (load progress, resident cube, crop/bin on open). Read
§1–§4 for the constraints, then the Status checklist in §5, and take the next
unchecked stage. docs/open-items.md is the live list for everything else;
docs/v2-onramp.md has the working methods and its status sections are
superseded.

This changes app code, so follow docs/development-process.md, and take the
review gate the stage names. Commit only if I ask.
```

Whatever the task: app-code changes follow `docs/development-process.md` —
Explore subagent (Haiku) to locate code, implement on the default model, and
take the review gate the work earns. Anything touching `Core/` or the science
needs an adversarial review *and* a `tools/` fixture. Never let the model that
wrote a science-affecting change be the only one to approve it — this has now
refuted a fix **twice** (2026-08-05, 2026-08-06), and both times the fix had
already passed every test written for it, including one verified to fail
without it. **Review the diagnosis, not just the code.** On 2026-08-06 the
refuting evidence — an origin fit residual printed in the very log the finding
came from — had been sitting in plain sight the whole time.

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Two threads (this is the mental model)

Two bodies of work, deliberately independent:

1. **Closing out v1.0** — #46, then signing/notarization. Governed by
   `ROADMAP.md` (3 standing priorities) and `docs/v1-scope.md` (the frozen
   release contract). Status: `docs/open-items.md`.
2. **The load pipeline** — `docs/load-pipeline-plan.md`. New feature work that
   *does* touch `Core/`: load progress, a resident in-memory cube with a
   streaming fallback, and crop/bin-on-open. It is post-v1 by `ROADMAP.md`'s
   scope rule and is being built anyway, as a recorded decision — see that
   plan's §1.

Neither gates the other.

The QC playthrough that used to be a second thread has finished both its
phases and become **the acceptance test**. It drives the real app through the
canonical py4DSTEM pipelines on screen and logs every number it reads from the
app's own controls. Its eval-only rule still stands: never change app code to
make a QC step pass — that is a finding, not a bug fix.

## Where v1.0 stands (2026-08-06, close of the v1.0 development phase)

**Release candidate. `tools/run-tests.sh all` — exit 0, 30 harnesses.**
What v1.0 *is*: [`CHANGELOG.md`](CHANGELOG.md). What is still live:
**[`docs/open-items.md`](docs/open-items.md)** — short, and the only status
document that is maintained. Read it before planning anything.

Settled on 2026-08-06:

- **#16/#22 — fixed and confirmed on the real app.** A single
  `.fixedSize(horizontal: false, vertical: true)` in
  `UI/TaskPrerequisiteChecklist.swift` propagated a minimum height past the
  window's own. Never a scroll offset, which is why six offset measurements all
  found it correct. Pinned by `mac4DSTEMTests/SplitViewHeightTests`; the QC
  playthrough now passes step 3b and runs to Results.
- **QC playthrough — green on all four datasets, 0 failures.** Numbers only:
  those runs used `--no-screenshots`, so **there is no visual baseline yet**.
- **Code review of `a9e4268..HEAD` — done**, one low-severity finding
  (`CrystalModel.shortestCloseContact` assumes fractional coordinates in
  `[0,1)`; true for every current source, undocumented).
- **The acceptance diff found a real defect (#46)** and it blocks the tag.

Outstanding: **#46**, then the distribution final mile (Developer ID signing,
notarization, clean-account launch — release-owner actions, credentials
required).

## Where things are written down

- **[`CHANGELOG.md`](CHANGELOG.md)** — what v1.0 is. Start here for scope.
- **[`docs/open-items.md`](docs/open-items.md)** — everything still live, and
  the working methods that earned their keep. **The only maintained status
  doc.**
- **[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)** — **the active
  feature plan**: honest load progress, a resident in-memory cube with a
  streaming fallback, and crop/bin-on-open driven from a preview. Six staged
  prompts (L1–L6), the invariants, why the app is out-of-core, and where
  py4DSTEM must *not* be copied. Independent of the v1.0 tag in both
  directions.
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

## Standing references (Thread A)

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities and the scope rule.
- **`docs/v1-scope.md`** — the frozen v1 release contract. Consult when
  deciding whether a proposed change is in scope (ROADMAP's scope rule points
  here); not a "read first" doc.
- **`docs/v2-onramp.md`** — **the handover for a second development phase.**
  What v1.0 is, what it deliberately excluded, every open thread grouped by
  what it actually needs (blocking / scope decision / deferred by recorded
  scope change / harness confidence / small and known), and the working methods
  that earned their keep. Start here when the next phase opens.
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
