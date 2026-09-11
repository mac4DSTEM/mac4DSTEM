# CLAUDE.md — start here

mac4DSTEM: native macOS (Swift / SwiftUI / Metal) 4D-STEM analysis on Apple
Silicon, validated against py4DSTEM at one pinned upstream commit
(`tools/lib/fetch-py4dstem.sh` fetches it into the gitignored `References/`).
**v2.5.1 is the released artefact (2026-09-04); v3.0.0 is prepared and not yet
cut.** The consolidation plan **exited 2026-09-11**
(`docs/archive/consolidation-plan.md`, §7 checked line by line) and the feature
freeze it carried lapsed with it. Rules only here; status and history elsewhere.

## Read, in this order (2451 lines on 2026-09-11, after the plan was archived)

1. `docs/status.md` — what is live now, one table. Every session starts here.
2. `docs/v3-plan.md` — the feature plan (draft): the themes, the 2026-08-28
   decisions, how a feature is pre-registered and built.
3. `docs/open-items.md` — live defects and debts only, ≤ 12 lines each.
4. `docs/development-process.md` — how work is done, gated and recorded.
5. `docs/architecture.md` — layering, ownership, where files go.
6. `docs/decisions.md` — append-only; why things are the way they are.

History is `docs/archive/` (the v2 chronology under `docs/archive/v2/`).
Consult it for *why*, never for what to do next. Reference docs that are
neither status nor history: `docs/releasing.md`, `docs/dm4-format.md`,
`docs/q-calibration-design.md`, `docs/py4dstem-pipelines.md`.

Skills: `/pickup` takes the next step from `docs/status.md`'s handoff;
`/diagnose` is Gate D; `/adversarial-review` is Gate B; `/closeout`.
A feature target is no longer refused — `docs/v3-plan.md` §6 says how a v3
feature is pre-registered and built.

## Hard rules

- Views describe UI only; loading, parsing and compute live in `Core/`.
  `AppState` is the single source of truth until the plan's stores replace it.
- No new stored state in `AppState`: a feature names its owner first.
  `AppState.swift` + `Support/ResultExport.swift` never net positive lines in
  a commit; `inventory` measures it (C5, 2026-09-07). Extractions follow the
  plan's §4 order, one at a time, each with a green boundary and a reopen test.
- **Gate D applies when a change can move a scientific number, or when the
  cause of a defect is not yet established** — not to every change in `Core/`.
  Diagnosis, refuting observation, predicted outcome, then the experiment,
  before the fix; an independent refuter after; a fixture. The model that
  wrote the change never approves it alone. Review the diagnosis, not the diff.
  The refuter stays because this repo has shipped three confident wrong
  diagnoses that passed every test written for them; a model that forms a
  hypothesis writes tests that confirm it.
- **What does NOT need Gate D**, and saying so is the point (2026-09-04): pure
  placement and presentation changes, renames, docs, tooling, and defects whose
  mechanism is already proven by a reproducing observation. State which of the
  two triggers applies, or say that neither does and proceed.
- Break every new test before trusting it. Do not drive the app during the
  unit gate. Quote test numbers only from a dated run, named by its log;
  `tools/run-tests.sh` is the only thing that knows the harness count. A log
  name is a name, not a path — session logs are gitignored and not retained
  (2026-09-09: all 24 cited `scratchpad/` paths were already gone). Evidence a
  reader must open is committed under `docs/archive/`; the inventory gate fails
  on a repo-rooted path a truth doc cites and does not have.
  **Never read a gate's exit code through a pipe** — `run-tests.sh … | tail`
  reports `tail`'s status, not the gate's. Redirect to a log, `echo $?` on
  its own line, then grep the log. This has swallowed a failing gate three
  times (S4, S8, and twice in one session on 2026-09-04).
- No claim a reader cannot reproduce. The repo is public.
- Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by
  decision; `.automatic` residency was dropped, not tuned.
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the
  matching `.metal` structs (all 4-byte fields).
- Port deviations from py4DSTEM get an inline `DEVIATION` note.
- Don't add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch; use
  `tools/run-tests.sh unit` for unsigned XCTest work.
- On-screen verification is the owner driving the app (Track B retired
  2026-09-03). A drawing change is stated as unverified on screen until the
  owner has seen it; a bug report enters through `/diagnose`, never as an
  app change made to satisfy a checklist.
- Docs are part of done. Update `docs/status.md` and `docs/open-items.md` in
  the same commit as the code. Every session nets negative markdown lines or
  says why. No new file without saying why an existing home would not do.
  `AGENTS.md` is generated: run `tools/sync-agents-md.sh` after editing this.
- Commit only when asked; never push — the owner pushes (2026-09-07). Linear
  `main`.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
tools/run-tests.sh unit | scientific | all | inventory | core | benchmark | campaign   # inventory = the repo's own review
tools/free-space.sh                                     # exit-69 remedy
```
