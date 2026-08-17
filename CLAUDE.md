# CLAUDE.md — start here

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff prompt (copy-paste to start a session)

**v1.0.0 is tagged, signed and public. Phase 2 was planned 2026-08-17** — the
contract is `docs/v2-scope.md`. The active work is the load pipeline.

```
Pick up mac4DSTEM. Read CLAUDE.md, then docs/v2-scope.md (priority order and the
refusal rule), then docs/load-pipeline-plan.md — the active plan. Read §1–§4 for
the constraints, then the Status checklist in §5.

Three stages are PARTLY done (marked [~]) — read what landed before adding to
them. The next work is L3's reader threading: §6's L3 prompt opens with a
correction that reverses the original premise, so read that before touching a
reader.

Do NOT set ResidencyAdmission.measuredWorkingSetFraction. It is nil by decision,
not oversight — §5's L2 entry says why.

This changes app code, so follow docs/development-process.md and take the review
gate the stage names. If the stage touches AppState, extract one seam before it
lands (§7). If it changes what the app draws, ask me for a Track B pass —
several rows are already queued unverified. Commit only if I ask.

Before trusting any test you write: break the code it covers and watch it fail.
That caught three green-but-worthless suites on 2026-08-17 alone.
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
ten minutes of driving it by hand produced two defects the suite could not see;
the first clean-account run on 2026-08-14 produced three more. There is no
automated visual baseline, so nothing but a person looking at the screen catches
that class of bug — which is why it is now a written procedure,
`docs/visual-acceptance-checklist.md` (Track B). You cannot run it yourself;
write the checklist and ask.

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Where things stand

**v1.0.0 — tagged 2026-08-06; signed, notarized and public since 2026-08-14.**
What it is: [`CHANGELOG.md`](CHANGELOG.md). The repo is at
`github.com/mac4DSTEM/mac4DSTEM` under GPL-3.0, with a stapled DMG linked from
mac4dstem.com. **Distribution is done.**

**Phase 2 was planned 2026-08-17.** The contract is
[`docs/v2-scope.md`](docs/v2-scope.md) — a priority order and a refusal rule,
not a scope freeze. The active work is
[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md): a resident in-memory
cube with a streaming fallback, and crop/bin-on-open, so an analysis validated
on a reduced *view* re-runs unchanged on the full dataset.

**Do not repeat the claim `tools/run-tests.sh all` — exit 0, 30 harnesses**
without re-running it. It was measured at the tag and no one has reproduced the
aggregate since. `SidebarLayoutTests.testEveryWorkspaceSidebarFitsItsColumn` is
**intermittent**, not reliably red: it failed on macOS 27 with no app-code
change, and passed on 2026-08-17 in a full `run-tests.sh unit` that exited 0.
A layout threshold that drifts with the machine is worse than a stable failure,
because a green run proves nothing. Tracked in `docs/open-items.md`.

**Verification runs in two tracks** (`docs/development-process.md` §6): Track A
is `tools/run-tests.sh`, Track B is the human visual pass at
[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md).
The XCUITest QC playthrough was **retired 2026-08-17** — it never produced a
screenshot, never touched a disk-detection control, and could read a stale peak
count. Its eval-only rule carries over to Track B unchanged: never change app
code to make an acceptance step pass — that is a finding, not a bug fix.

## Where things are written down

- **[`CHANGELOG.md`](CHANGELOG.md)** — what v1.0.0 is, and what it was *not*
  verified by. Start here for scope.
- **[`docs/open-items.md`](docs/open-items.md)** — everything still live, and
  the working methods that earned their keep. **The only maintained status
  doc.**
- **[`docs/v2-scope.md`](docs/v2-scope.md)** — **the phase-2 contract**, decided
  2026-08-17. The product claim v2 is aiming at, the priority order (load
  pipeline → verification debt → UI backlog → deferred), what is deferred and
  what would open it, the **refusal rule**, the version policy, and the eight
  decisions with their reasons. Consult it when asking "should this be picked up
  now?". *(It replaced `docs/v2-planning-draft.md`, which is deleted.)*
- **[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md)**
  — **Track B**, the human visual pass, with the standing checklist and the
  known traps behind each row. The assistant writes the specific list; the
  release owner drives the app and sends screenshots.
- **[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)** — **the active
  feature plan**: honest load progress, a resident in-memory cube with a
  streaming fallback, and crop/bin-on-open driven from a preview. Six staged
  prompts (L1–L6), the invariants, why the app is out-of-core, and where
  py4DSTEM must *not* be copied. **The active plan.**
- **`docs/py4dstem-pipelines.md`** — the pipelines step by step, the
  app-vs-py4DSTEM findings (§7), scope/roadmap (§8), empirical run findings
  (§9).
- **`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/run.sh`** — **retired
  2026-08-17, unmaintained, still in the tree.** Do not spend a session
  repairing it and do not cite its numbers; see `docs/v2-scope.md` §6.2 for why.
  Whether to delete it is an open item.
- **[`docs/archive/v1.0/`](docs/archive/v1.0/)** — the v1.0 phase's working
  memory: 46 numbered findings, the design passes, the QC-evaluation prompts.
  **History, not guidance.** Nothing current points into it; consult it for
  *why* a decision was made, never for what to do next.
- Session memory (direction + gotchas):
  `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM/memory/` — note the
  path predates the `mac4DSTEM_Organization/` move, so a session started from
  the current checkout gets a *different*, empty memory directory.

## Standing references

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities, the version policy, and the
  scope rule.
- **`docs/v1-scope.md`** — the **frozen** v1 release contract, kept as the
  record of what v1.0.0 promised. Superseded as the live contract by
  `docs/v2-scope.md`; consult it for what was in v1 and why, not for what to do
  next.
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
| Vendored external material + machine-local data (`References/` is gitignored — **except** the py4DSTEM Python source lock, which is tracked on purpose so `DEVIATION` notes can cite it by file and line; see `.gitignore`) | `References/` |

## Hard rules

- **Views describe UI only.** Loading/parsing/compute live in `Core`.
  `AppState` (`@Observable`) is the single source of truth.
- **Acceptance is evaluation only** — never modify app logic under `mac4DSTEM/`
  to make a Track B step pass. If the app blocks the pipeline, that's a
  *finding* for `docs/open-items.md`, not a code change. (Inherited from the
  retired QC playthrough, which the rule originally named.)
- **A stage that touches `AppState` extracts one seam before it lands**, at a
  green test boundary, the extracted type itself `@Observable`. Binding since
  2026-08-17 — `docs/development-process.md` §7. Splitting the file into
  `extension AppState { }` does not count.
- **No claim stands that a reader cannot reproduce.** If a number in
  `README.md`, `CHANGELOG.md` or `docs/` goes stale, change the claim or fix the
  gate. The repo is public.
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
# build (needs full Xcode toolchain, not just Command Line Tools)
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build

tools/run-tests.sh unit          # fast XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific    # py4DSTEM-parity harnesses
tools/run-tests.sh all           # Track A, the aggregate gate
```

Track B (visual acceptance) is not a command — it is a person driving the app
against `docs/visual-acceptance-checklist.md`.

## Long-term goals

Three standing priorities (full text in `ROADMAP.md`): **(1) scientific
interpretation** — every result keeps its model/scale/units/validity through
display, export, and reopen; **(2) product clarity** — task-scoped controls,
persistent result labels, visible diagnostics; **(3) incremental architecture**
— shrink the `AppState` facade, one seam per stage, at green test boundaries.
Whether a new feature is picked up now is answered by `docs/v2-scope.md`: its
priority order, and its refusal rule.
