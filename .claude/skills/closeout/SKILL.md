---
name: closeout
description: Close a mac4DSTEM development session with the repo's end-of-session discipline. Use whenever a session's work is landing — the user says "wrap up", "we're done", "close it out" — or the session's scope is complete, and always before any commit.
---

# Session closeout

Done means the repo tells the next reader the truth. In order:

1. **Gate.** `tools/gate.sh unit` (machine-wide lock, log, exit line; blocked, it exits 75 instead of waiting). If the session touched `Core/`, also `tools/gate.sh scientific`. A session that changed nothing under `mac4DSTEM/` owes no gate: say so and name the last run covering this tree. When a gate already ran green on the tree, prove it with an empty `git diff --stat <gate-commit>..HEAD -- mac4DSTEM/ mac4DSTEMTests/ mac4DSTEM.xcodeproj/ Package.swift`. Put the exit code on its own line (a `| tail` once swallowed a failing gate). Exit 69 is the free-space preflight: free regenerable build debris (DerivedData, `.build`), never touch the floor.
2. If `AppState` was touched, move one responsibility out where that makes the app better, or say why no move would (`CLAUDE.md`, Rules serve the app). Splitting into `extension AppState { }` is not a move.
3. If the session changed what the app draws, say so and state it as unverified on screen unless a drive saw it (build, clicks and shots named).
4. One review by a second lane before the commit (`/adversarial-review`).
5. Update `docs/status.md` (the hand-off and the dated gate table) and `docs/open-items.md` (add, amend or delete; findings, not narratives; at most 12 lines each; closed items to `../_archive/mac4DSTEM/docs/archive/`). A new file in `docs/decisions/` and a row in `docs/decisions.md` only if a decision was made that is not obvious. `CHANGELOG.md` gets the entry, with a Migration paragraph where consumers must change something. Say if a ROADMAP feature finished or was added (the coordinator keeps the board's "What's coming").
6. **Run `tools/gate.sh inventory`** and paste its output; it exits 0. Its live-markdown and cold-start numbers must not go up; a session that adds a file says why no existing home would do. The repo-light pass: anything that no longer builds, tests or explains moves to `../_archive/mac4DSTEM/`; proof is the tests green and `git grep` finding no path into what left.
7. State what was NOT verified. Silence about a gap is a claim.
8. Update this repo's row on the suite board, `lanes/mac4dstem` (`../CLAUDE.md`): fields, the version pin, `pickup.prompt` as the exact text the owner pastes next, and the push commands in `waiting`.
9. **Commit** coherent changes on `main` with the gate numbers in the message and the docs in the same commit as the code. Pushing and tagging are the owner's.
10. One sentence on the skills: did one misfire or fail to trigger? Edit it now.
