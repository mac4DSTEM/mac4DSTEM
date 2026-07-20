# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

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
- **Thread B — the QC-playthrough evaluation → UI improvement.** The *current
  active initiative*. We drive the real app through the canonical py4DSTEM
  analysis pipelines (an XCUITest that watches on screen), compare against
  py4DSTEM, and turn every workflow friction into a UI/workflow improvement.
  **Thread B feeds Thread A's Priority 2 (product clarity).** It is
  **evaluation only** — it never modifies app logic.

## Current initiative (Thread B) — start here for "what do I do next"

- **What it is + all pipelines, step by step:** `docs/py4dstem-pipelines.md`
  (also holds the app-vs-py4DSTEM findings §7 and the scope/roadmap §8).
- **Next actions + live status — cold-start prompts for a fresh agent:**
  `docs/qc-playthrough-prompts.md`. It carries the authoritative "what's done /
  what's next" checklist and four self-contained task prompts; hand one to a
  new session. (Read its Status section first — don't restate status here.)
- **The UI backlog these findings produced:** `docs/ui-workflow-backlog.md`
  (ranked, each item tagged UI-only vs workflow-logic, core-untouched).
- **The harness + how to run it:** `mac4DSTEMUITests/` +
  `tools/ui-qc-playthrough/run.sh [dataset-substring]`.
- Session memory (direction + gotchas):
  `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM/memory/qc-playthrough-pipeline-eval.md`.

## Standing references (Thread A)

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities and the scope rule.
- **`docs/v1-scope.md`** — the frozen v1 release contract. Consult when
  deciding whether a proposed change is in scope (ROADMAP's scope rule points
  here); not a "read first" doc.

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
