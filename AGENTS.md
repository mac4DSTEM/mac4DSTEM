# AGENTS.md — start here

> **Generated from `CLAUDE.md` by `tools/sync-agents-md.sh` — do not edit this
> file.** Edit `CLAUDE.md`; the three passages that differ for a non-Claude-Code
> agent are substituted by that script and listed in its header. Hand-maintained
> until 2026-08-28, when it was found six sessions stale.

Single entry point for any agent (or human) opening this repo cold. It does
not duplicate the docs; it tells you what to read and where things go.

## Session kickoff (start here)

**v1.0.0 is tagged, signed and public. The v2 release was planned 2026-08-18**
— the contract and session plan are `docs/v2-release.md`: §1 the claim, §7 the
gates, §8 the session briefs, §9 the live status checklist. **The one
canonical kickoff prompt is §8's copy-paste block — paste it.** The repo also
carries five standing skills in `.claude/skills/` — `pickup`, `track-b`,
`diagnose`, `adversarial-review`, `closeout` — each encoding one of this
repo's disciplines. They are **Claude Code skills and cannot be invoked from
here**, but their `SKILL.md` files are short and are the authority on how each
discipline runs: read the matching one as a document before you do that kind of
work. There is no `.Codex/skills/` directory; an earlier hand-written version of
this file said there was.

Standing cautions, each of which has burned this repo before:

- **Do NOT set `ResidencyAdmission.measuredWorkingSetFraction`** — nil by
  decision, not oversight; `.automatic` residency was DROPPED (S3), not tuned.
- App-code changes follow `docs/development-process.md` (Explore on Haiku to
  locate code, implement on the default model) and take the gate the session
  names — A, B or D, defined in §7 of the release plan. Gate D writes the
  diagnosis, the refuting observation and the predicted outcome, then runs
  the experiment, BEFORE touching code.
- Anything touching `Core/` or the science needs an adversarial review *and*
  a `tools/` fixture. **Never let the model that wrote a science-affecting
  change be the only one to approve it; review the diagnosis, not just the
  code.** Three times (2026-08-05, 2026-08-06, 2026-08-18) a fix passed every
  test written for it — including one verified to fail without it — and a
  second reader of the same evidence refuted it.
- A session touching `AppState` extracts one seam first. A change to what the
  app draws queues Track B rows and is unverified until the owner drives them.
- **Break every new test before trusting it** — three green-but-worthless
  suites were caught that way on 2026-08-17 alone.
- **Open the app.** Tag day: all 30 harnesses green, and ten minutes of
  driving by hand found two defects the suite could not see; the
  clean-account run found three more. Track B
  (`docs/visual-acceptance-checklist.md`) exists because nothing else catches
  that class. You cannot run it yourself — write the checklist and ask.

## What this is

**mac4DSTEM** — a native macOS (Swift / SwiftUI / Metal) app for interactive
4D-STEM analysis on Apple Silicon. The mission is feature parity with
[py4DSTEM](https://github.com/py4dstem/py4DSTEM), which is vendored here as the
reference implementation and validated against.

## Where things stand

**v1.0.0 — tagged 2026-08-06; signed, notarized and public since 2026-08-14**
at `github.com/mac4DSTEM/mac4DSTEM` (GPL-3.0, stapled DMG linked from
mac4dstem.com). What it is: [`CHANGELOG.md`](CHANGELOG.md). **Distribution is
done.**

**The v2 release is mid-flight: S0–S8, S9a, S9b, S10, S11, S12, S13, S17, S18,
S19 and S21 are done** (plus the M1 tidy) — **S13 was MERGED to `main` and
pushed (fast-forward to `bab5e07`); `s13-q-calibration` still exists and points
at the same commit. Corrected 2026-08-31**: this file and §9 both still said
"NOT merged to `main`; the merge is the owner's call", which was true when
written on 2026-08-29 and stopped being true when the owner merged. Neither
summary noticed. The evidence is `git reflog show main` —
`main@{0}: merge s13-q-calibration: Fast-forward` — not either doc.
— the load pipeline closed as a product, the promote run with unattended
recipe replay, the error-honesty and strain-frame trust fixes, and the
reduced-file export with the recipe frame mapping — with the full session
records in
[`docs/archive/v2-session-records/`](docs/archive/v2-session-records/).
**S18 is ticked `[x]`. Its Gate B debt was cleared 2026-08-28** — a separate
refuter attacked both `Core/` changes (`pattern(ry:rx:)` from the resident cube,
the staging-copy elimination) and **both survived**, twelve mutations each
producing a distinct red. It also exposed a fixture blind spot, now closed by
`tools/resident-cropped-view`. **What is still owed from S18 is only the
`mac4DSTEMUITests` deletion**, which the environment refused rather than
declined; that needs the owner.

*Read this before trusting either summary again:* on 2026-08-27 a session found
this paragraph disagreeing with §9's S18 stub and **resolved it the wrong way**,
rewriting this text to defer to the stub — which claimed a Gate B review that
S18's own record does not contain. The record's *Not verified* section says the
second read did not run, and its only review section is `Gate A — 14 agents`.
Corrected 2026-08-28. **When a stub and this file disagree, neither wins by
default — open the session record in `docs/archive/v2-session-records/`, which
is the evidence both are summarising.**
Sequencing (§9's checklist and resequencing line are the authority): the
S10 → S21 → S17 run is complete; **TB1 sitting 1 is COMPLETE (2026-08-27)** and
sittings 2–4 wait on the owner — sitting 3 needs a multi-GB/NAS cube, sitting 4
a clean account. **S11 was run ahead of them on 2026-08-28** rather than after,
because it needs neither; that reordering is stated in its stub, and **S12 ran
ahead of them on 2026-08-28 for the same reason**. **S9b ran 2026-08-28** and
needed no NAS after all — the axis is
`MNT_LOCAL && !MNT_REMOVABLE`, not local-vs-network. Its mechanism is confirmed
and scoped to DM4/DM3; the 2026-08-18 death itself is **still unexplained**, and
the reader fix is owed to a later session. **#37 moved to S9**, since S18's
measurement showed the cancellation cost is I/O, not check granularity. The
cut line and the severable block (now **S14–S16, TB2** — S11–S13 landed)
are §2 of the release plan. **S13 implemented
[`docs/q-calibration-design.md`](docs/q-calibration-design.md) on the owner's
§6(a) decision (2026-08-28, Gate B with four refuters)** — but the review cut
all three estimator thresholds (derivation refuted), so the estimator
**measures and reports** the shell ratio rather than refusing on it, and the
origin-fit gate stays on the full-scan RMS: **which statistic should gate that
fit is OPEN** (`docs/open-items.md`). The demo-fixture and probe-radius
findings (`probeSize` over-measures 2.15×, Gate D owed) came out of the same
session. F1.40–F1.43 are queued and undriven.

**The honest test claim — each number dated to its own run:**
`run-tests.sh scientific` — exit 0 over **39 harnesses**, zero FAIL and zero
SKIP lines (2026-08-29, S13 closeout on `s13-q-calibration`, after
`tools/q-calibration-gate-test` — 70 checks — joined the array).
`run-tests.sh unit` — **390 passed / 2 skipped / 0 failed, exit 0**
(2026-08-29, same tree — 390 distinct case names, checked for retries, not a
raw line count); the two skips are the unmounted-volume bookmark probe and
S17's explicit uncalibrated-Prepare geometry quarantine. Two former data-probe
skips (including `TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes`)
now PASS because their staged data is present. **Two recordable non-green outcomes
from that sitting, both environmental:** one `unit` run refused with **exit 69**
(the S0 preflight — scratch DerivedData from repeated app builds; cleared, then
green) and one reported a single spurious failure in
`SidebarDensityMeasurementTests` because the app was being driven for Track B
against the same defaults domain while the gate ran. **Do not drive the app
during `run-tests.sh unit`** — see `docs/open-items.md`.
MCP `test_macos` — **378 passed / 1 failed** (2026-08-26, S10; the
now-diagnosed sidebar test — the retired UI target skipped), retained as its
own dated run. **`run-tests.sh all` — GREEN END TO END, exit 0, 2026-08-28**, on the tree carrying S9a and the Gate B fixture: **40 harnesses**, unit stage **387 passed / 4 skipped / 0 failed**, **zero FAIL lines and zero exit-69 preflight refusals in the retained log** (checked by grep, not by trusting the exit code — a `| tail` has swallowed a failing gate here twice). One `SKIP`:
`real-data-acceptance` correctly recognised a session sidecar sitting beside a
training dataset and skipped it rather than reading it as a datacube — backlog
**#43**, fixed 2026-08-18, exercised live for the first time. (That run's WS2
sidecar skip has since cleared — see the 2026-08-29 unit run above.)
**S19's blocking dependency is therefore met**, and the README/CHANGELOG
aggregate claim can be restated against this run rather than retired. Do not
quote an aggregate you did not just run.

**Verification runs in two tracks** (`docs/development-process.md` §6):
Track A is `tools/run-tests.sh`; Track B is the human visual pass at
[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md).
The XCUITest QC playthrough was retired 2026-08-17; its eval-only rule
carries over unchanged: never change app code to make an acceptance step
pass — that is a finding, not a bug fix.

## Where things are written down

- **[`CHANGELOG.md`](CHANGELOG.md)** — what v1.0.0 is, and what it was *not*
  verified by. Start here for scope.
- **[`docs/open-items.md`](docs/open-items.md)** — everything still live, and
  the working methods that earned their keep. **The only maintained status
  doc.**
- **[`docs/v2-release.md`](docs/v2-release.md)** — **the v2 release contract
  and session plan**, decided 2026-08-18. The claim, the five workstreams, the
  cut line, the refusal rule, the version evidence, the three gates (A/B/D —
  D is the structural guard against a confident wrong diagnosis), the numbered
  sessions S0–S21, and the live status checklist. **The single entry point.**
  Consult it for "what do I pick up?" and "is this in scope?".
- **[`docs/q-calibration-design.md`](docs/q-calibration-design.md)** — **S12's
  design, 2026-08-28**: what the origin-fit residual gate actually measures
  (#29, answered), the sane-origin / measure-Q split, the estimator-internal
  plausibility checks, and the coarse-step in-or-out call with its measurement.
  Read it before touching Q calibration, `OriginCalibration` or
  `Shaders/OriginMeasure.metal`; S13 implemented from it (2026-08-28, with
  Gate B's threshold cut recorded in
  [`s13.md`](docs/archive/v2-session-records/s13.md)).
- **[`docs/v2-scope.md`](docs/v2-scope.md)** — the 2026-08-17 phase-2
  priorities. **Superseded by `docs/v2-release.md`**; kept for the eight
  decisions and their reasons. *(It replaced `docs/v2-planning-draft.md`,
  which is deleted.)*
- **[`docs/visual-acceptance-checklist.md`](docs/visual-acceptance-checklist.md)**
  — **Track B**, the human visual pass, with the standing checklist and the
  known traps behind each row. The assistant writes the specific list; the
  release owner drives the app and sends screenshots.
- **[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)** — how L1–L6
  were built and reviewed, stage by stage, with the invariants and the
  py4DSTEM deviations. **Superseded 2026-08-18, kept as the authoritative
  history of that work.** Do not add stages or tick anything there.
- **`docs/py4dstem-pipelines.md`** — the pipelines step by step, the
  app-vs-py4DSTEM findings (§7), scope/roadmap (§8), empirical run findings
  (§9).
- **`mac4DSTEMUITests/` + `tools/ui-qc-playthrough/run.sh`** — **retired
  2026-08-17, unmaintained, still in the tree.** Do not spend a session
  repairing it and do not cite its numbers; see `docs/v2-scope.md` §6.2 for why.
  Whether to delete it is an open item.
- **[`docs/archive/s1-sidecar-under-the-sandbox.md`](docs/archive/s1-sidecar-under-the-sandbox.md)**
  — S1's full investigation, archived 2026-08-19. **History, not guidance**, but
  the *method* is the reusable part: a pre-registration written before its answer
  was known, and a Gate B correction that stopped one wrong errno sending the
  diagnosis the other way.
- **[`docs/archive/v2-session-records/`](docs/archive/v2-session-records/)**
  and **[`docs/archive/closed-items-2026-08.md`](docs/archive/closed-items-2026-08.md)**
  — the verbatim S1–S8 session records and the closed open-items entries,
  moved out of the live docs by M1 (2026-08-26). **History, not guidance.**
- **[`docs/archive/v1.0/`](docs/archive/v1.0/)** — the v1.0 phase's working
  memory: 46 numbered findings, the design passes, the QC-evaluation prompts.
  **History, not guidance.** Nothing current points into it; consult it for
  *why* a decision was made, never for what to do next.
- Session memory (direction + gotchas) lives in **Claude Code's** per-project
  memory directory,
  `~/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/memory/`
  (14 files as of 2026-08-28, `MEMORY.md` the index). **A session running from
  this file does not load it**, so nothing in it is context you have — read it
  from disk if you need it, and do not assume a fact is remembered. Three stale
  sibling directories from earlier checkout paths are history, not guidance.

## Standing references

- **`README.md`** — what the app does, build/run, HDF5 notes, developer
  notes, known limitations. The authoritative product overview.
- **`ROADMAP.md`** — the 3 standing priorities, the version policy, and the
  scope rule.
- **`docs/v1-scope.md`** — the **frozen** v1 release contract, kept as the
  record of what v1.0.0 promised. Superseded as the live contract by
  `docs/v2-scope.md`; consult it for what was in v1 and why, not for what to do
  next.
- **`docs/archive/v2-onramp.md`** — the phase-2 handover, archived 2026-08-18;
  everything it tracked is superseded by `docs/open-items.md` and
  `docs/v2-release.md`.
- **`docs/post-v1-ideas.md`** — parking lot for ideas that are out of v1 scope
  *and* would touch `Core/` (cropping, partial/binned loading). Deliberately
  separate from `docs/open-items.md` — whose original UI/workflow-only rule
  no longer holds: check an item's owning session and gate before handing it
  out as a prompt. Nothing here is committed to; entries record the
  non-obvious constraints so a later session doesn't rediscover them.

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
| CI workflows (the `unit` + `scientific` gates on every push; S21) | `.github/workflows/` |
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
  frozen record of the v1.0 phase. **`AGENTS.md` is generated from this file** —
  if you edit `CLAUDE.md`, run `tools/sync-agents-md.sh` (`--check` exits 1 when
  stale); it was hand-maintained until 2026-08-28 and drifted six sessions.
  Full conventions (model/subagent tiers, review gates, where new work goes,
  delivery, and **§9 what keeps a session agent-runnable** — the grants and
  attached disks that turn owner-only rows into work an agent can run):
  **`docs/development-process.md`**.
- Commit/push only when asked; this is a solo-dev repo with linear `main`.

## Build / test / run

```sh
# build (needs full Xcode toolchain, not just Command Line Tools)
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build

tools/run-tests.sh unit          # fast XCTest suite (isolated DerivedData)
tools/run-tests.sh scientific    # py4DSTEM-parity harnesses
tools/run-tests.sh all           # Track A, the aggregate gate
tools/free-space.sh              # exit-69 remedy: report build debris; --clear deletes
```

Track B (visual acceptance) is not a command — it is a person driving the app
against `docs/visual-acceptance-checklist.md`.

## Long-term goals

Three standing priorities (full text in `ROADMAP.md`): **(1) scientific
interpretation** — every result keeps its model/scale/units/validity through
display, export, and reopen; **(2) product clarity** — task-scoped controls,
persistent result labels, visible diagnostics; **(3) incremental architecture**
— shrink the `AppState` facade, one seam per stage, at green test boundaries.
Whether a new feature is picked up now is answered by `docs/v2-release.md`:
its workstreams, its cut line, and its refusal rule.
