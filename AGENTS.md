# AGENTS.md — start here

> **Generated from `CLAUDE.md` by `tools/sync-agents-md.sh` — do not edit this
> file.** Edit `CLAUDE.md`; the two passages that differ for a non-Claude-Code
> agent are substituted by that script and listed in its header. Hand-maintained
> until 2026-08-28, when it was found six sessions stale.

mac4DSTEM: native macOS (Swift / SwiftUI / Metal) 4D-STEM analysis on Apple Silicon, validated against py4DSTEM at one pinned upstream commit (`tools/lib/fetch-py4dstem.sh` fetches it into the gitignored `References/`).
**v3.0.0 was released 2026-09-11**, version/build 3.0.0 / 6. The consolidation plan **exited 2026-09-11** (`docs/archive/consolidation-plan.md`, §7 checked line by line) and the feature freeze it carried lapsed with it. Rules only here; status and history elsewhere.

## Read, in this order

1. `docs/status.md` — what is live now, one table. Every session starts here.
2. `ROADMAP.md` — the feature plan: themes, priorities, and how a v3 feature is pre-registered and built (§6).
3. `docs/open-items.md` — live defects and debts only, ≤ 12 lines each.
4. `docs/architecture.md` — layering, ownership, where files go.
5. `docs/decisions.md` — the ADR index; one row per decision, the record itself in `docs/decisions/`.

Skills in `.claude/skills/` — `pickup`, `diagnose` (Gate D), `adversarial-review`
(Gate B), `closeout` — are **Claude Code skills and cannot be invoked
from here**; read the matching `SKILL.md` as a document before doing that kind
of work. Session memory lives in Claude Code's per-project memory directory and
is not loaded here: do not assume a fact is remembered.

## Hard rules

- Views describe UI only; loading, parsing and compute live in `Core/`. `AppState` is the single source of truth until the plan's stores replace it.
- New stored state in `AppState` names its owner first; `inventory` now reports (not blocks) growth of `AppState.swift` + `Support/ResultExport.swift`, and a commit that grows them says why no other home would do.
- **Gate D** applies when a change can move a scientific number, or the cause of a defect is not yet established — not every change in `Core/`. Diagnosis, refuting observation, predicted outcome, experiment, then the fix; an independent refuter after; a fixture; the model that wrote the change never approves it alone — review the diagnosis, not the diff.
- **What does NOT need Gate D**: placement/presentation changes, renames, docs, tooling, and defects whose mechanism a reproducing observation already proves. State which trigger applies, or that neither does.
- Break every new test before trusting it — confirm it goes red on the mutation it claims to catch; do not drive the app during the unit gate.
- Never widen a gate that fails silently. Cost a UI change (rows/pt) before designing it, and open the app periodically — minutes of driving have found defects a green suite could not, which can be green about the wrong thing.
- Quote test numbers only from a dated run named by its log, not a path (session logs are gitignored, not retained); evidence a reader must open is committed under `docs/archive/`.
- Never read a gate's exit code through a pipe or backgrounded wrapper — redirect to a log, `echo $?` on its own line, grep the log's own exit line; count tests by method name and reconcile against the expected delta.
- A lost session resumes from its own scratchpad, never from memory.
- A threshold (a fraction, a bar, a cliff) is a property of the dataset and settings it was measured under, not of the method, until measured on every dataset it will touch — measure the distribution first, or ship the quantity and let the reader judge. Never infer a mechanism from a null result.
- No claim a reader cannot reproduce. The repo is public.
- Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by decision; `.automatic` residency was dropped, not tuned.
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the matching `.metal` structs (all 4-byte fields).
- Port deviations from py4DSTEM get an inline `DEVIATION` note.
- Don't add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch; use `tools/run-tests.sh unit` for unsigned XCTest work.
- On-screen verification may be claimed only when it actually drove the app and is sure — name the build, say what was clicked, what was seen; otherwise it is stated as unverified on screen.
- Docs are part of done: update `docs/status.md` and `docs/open-items.md` in the same commit as the code, net negative markdown lines or say why, and run `tools/sync-agents-md.sh` after editing this file.
- Commit freely: land work as coherent commits with the gate numbers in the message. Pushing stays the owner's — ask before any push.
- **`main` only** (owner directive 2026-09-17): no feature or worktree branches, local or remote; every change lands as a commit on `main`. The one-time cleanup back to a single branch is `docs/archive/git-cleanup-2026-09-17.md`.
- Decisions are a file in `docs/decisions/` plus a row in `docs/decisions.md`; the pre-2026-09-16 log is verbatim in `docs/archive/decisions-log-2026-08-17-to-2026-09-16.md`.
- What code already enforces: `run-tests.sh core` holds the layering; `run-tests.sh inventory` holds the UI contract greps, harness manifest, tools classification, NOTICE hashes, AGENTS sync and the size report.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
tools/run-tests.sh unit | scientific | all | inventory | core | benchmark | campaign   # inventory = the repo's own review
tools/free-space.sh                                     # exit-69 remedy
```
