# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff prompt (copy-paste to start a session)

**The v1.0 development phase is closed.** Which prompt you want depends on what
you're doing:

**Finishing v1.0** (review, distribution):
```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/v2-onramp.md § "Where v1.0 ended"
and § "Open threads". Backlog #16/#22 is FIXED (2026-08-06) and pinned by
mac4DSTEMTests/SplitViewHeightTests — what remains of it is one on-screen
tools/ui-qc-playthrough/run.sh to confirm step 3b passes on the real app.
Then the QC playthrough acceptance diff, and the distribution final mile
(release-owner credentials).

Everything awaiting review is committed — review range a9e4268..HEAD (the UI
session, 9c940d1 for the #14 CIF fix, and everything after; d47afb5 hides an
app-code change behind a "changes to .md" message, so review by range, not by
commit message). The v1.0 tag goes on after that review, not before. Do not
commit unless I ask.
```

**Opening a second development phase:**
```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/v2-onramp.md end to end — it is
the handover from the v1.0 phase and groups every open thread by what it
actually needs. Nothing in it is committed to; v2.0 scope is my decision, so
bring me options rather than starting work.
```

Whatever the task: app-code changes follow `docs/development-process.md` —
Explore subagent (Haiku) to locate code, implement on the default model, and
take the review gate the work earns. Anything touching `Core/` or the science
needs an adversarial review *and* a `tools/` fixture. Never let the model that
wrote a science-affecting change be the only one to approve it — on 2026-08-05
that review refuted a fix which had already passed all 30 harnesses.

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

## Where v1.0 stands (2026-08-05, close of the v1.0 development phase)

**The repo is at v1.0 release candidate and the development phase is closed.**
`tools/run-tests.sh all` is **green — exit 0, 30 harnesses**. The handover
document for what comes next is **[`docs/v2-onramp.md`](docs/v2-onramp.md)** —
read that before planning anything new.

Three things are outstanding, and they are different in kind:

1. **Backlog #16/#22 — ✅ FIXED 2026-08-06.** The cause was a single
   `.fixedSize(horizontal: false, vertical: true)` in
   `UI/TaskPrerequisiteChecklist.swift`: an unbounded vertical text demand in
   the detail column propagated a minimum height *past the window's own*, so
   both columns were laid out taller than the window and their top rows fell
   off it. It was never a scroll offset — which is why six attempts that
   measured the offset all found it correct. Pinned by
   `mac4DSTEMTests/SplitViewHeightTests` (no screen needed; verified to fail
   3/3 without the fix). **Outstanding: one on-screen playthrough to confirm
   the real app now gets past step 3b.**
2. **The QC playthrough acceptance re-run** — still has not produced a clean
   diff since 2026-08-04. The two things that blocked it are gone (permission,
   then #16); note the Accessibility grant is keyed to a *version-scoped* path
   and lapses on every Claude Code update. See `docs/v2-onramp.md` § "The one
   thing to do first".
3. **Distribution final mile** — Developer ID signing, notarization, and a
   clean-account launch. Release-owner actions, credentials required.

**Everything awaiting review is committed. Review range: `a9e4268..HEAD`.**
Three bodies of work inside it:
- **`a9e4268..901a6ef`** — the 2026-08-05 UI session (25 files, +3075/−246; the
  only `Core/` file is `Core/Data/BraggVectorEMDWriter.swift`, I/O plumbing).
- **`9c940d1`** — the backlog #14 CIF fix (`Core/Crystal/CIFImport.swift`,
  `Core/Crystal/CrystalModel.swift`, `tools/cif-symmetry-test/main.swift`).
  Already took its adversarial review, which refuted the first version; it
  needs only the ordinary read.
- **`d47afb5` onward** — **use `HEAD`, not a pinned hash.** `d47afb5` is titled
  "changes to .md" but also carries the backlog **#33** fix in
  `UI/ContentView.swift`. Reviewing the literal range `a9e4268..9c940d1` that
  this file used to name would have skipped it. If you commit app code, extend
  the range rather than trusting the message.

A dedicated **review/debug session** runs against that range, and **the v1.0
tag goes on after it** — not before.

The last science blocker (backlog **#14**, CIF symmetry expansion → silently
wrong structure factors for imported CIFs) is **closed**.

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
  — now the repo's general open-items record, not only the QC findings: 43
  numbered entries, most closed, each tagged with its layer. Items #1–#13 are
  the original QC-derived, contractually core-untouched set; later ones include
  hands-on reports (#33–#37), adversarial-review findings (#31, #32) and code
  review (#38–#40, #43), some of which *do* touch `Core/` and say so.
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
- **`docs/v2-onramp.md`** — **the handover for a second development phase.**
  What v1.0 is, what it deliberately excluded, every open thread grouped by
  what it actually needs (blocking / scope decision / deferred by recorded
  scope change / harness confidence / small and known), and the working methods
  that earned their keep. Start here when the next phase opens.
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
