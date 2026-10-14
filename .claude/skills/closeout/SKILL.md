---
name: closeout
description: Close a mac4DSTEM development session with the repo's end-of-session discipline. Use whenever a session's work is landing — the user says "wrap up", "we're done", "close it out" — or a numbered session's scope is complete, and always before any commit.
---

# Session closeout

Done means the repo tells the next reader the truth. In order:

1. `tools/gate.sh unit` — exit 0 (it takes the machine-wide lock, logs, prints the exit line and stamps green; blocked, it exits 75 instead of waiting). If the session touched `Core/`, run
   the relevant `scientific` harnesses too. **A session that changed nothing
   under `mac4DSTEM/` owes no gate** — say so and name the last run that
   covers this tree, with its date and commit; running one for form proves
   nothing about the session and spends the disk this machine does not have.
   **The same applies when the tree HAS changed but a gate already ran green on
   it** (2026-09-11): prove it rather than assert it — `git diff --stat
   <gate-commit>..HEAD -- mac4DSTEM/ mac4DSTEMTests/ mac4DSTEM.xcodeproj/
   Package.swift` empty — and paste that emptiness, not an assurance. Put exit codes where you read
   them — a `| tail` pipe has already swallowed a failing gate here once
   (twice: S4's scientific run and S8's first aggregate both lost the
   harness count the same way — retain the full log, grep it after).
   Two non-zero exits are RECORDABLE outcomes, not gates to force green:
   **exit 69** is the S0 free-space preflight refusing (run
   `tools/free-space.sh` — report first, `--clear` deletes the known debris —
   before recording an owner re-run owed; never touch the floor — the MCP
   `test_macos` route is the warm fallback for the app suite, or the script's
   own `xcodebuild test` line run directly into a retained log), and **exit 65 with exactly the S17
   sidebar intermittent** is the documented flake (add the run to S17's
   observation log in `docs/open-items.md` with the measured heights).
2. If `AppState` was touched: move one responsibility out where that makes
   the app better, or say why no move would (`CLAUDE.md` "Rules serve the
   app"). Splitting into `extension AppState { }` does not count as a move.
3. If the session changed what the app draws: say so, and state the work as
   unverified on screen until a drive has seen it — the owner's, or the
   session's own on a scratch build with the build, clicks and shots named
   (`CLAUDE.md`).
4. If the session came from `ROADMAP.md`'s Session queue, tick its line there
   (with the commit), make the handoff name the next unchecked line, and write
   what the next session needs into that line or the record it points to — the
   next session knows only the repo.
   Update the step's row in `docs/status.md` (state, commit, what deviated)
   and the dated gate table. A new file in `docs/decisions/` and a row in
   `docs/decisions.md` if a decision was made.
5. Update `docs/open-items.md` — add, amend, or delete. Closed items move
   to `docs/archive/` immediately (§1 discipline); the file is loaded by
   every session, so its length taxes all of them.
   **Write findings, not narratives** — the file's own header carries the
   format rule adopted 2026-08-28: what is wrong, the evidence, the trap, the
   owner, the live residual; ≤ 12 lines (the file's own rule, and CLAUDE.md's). Refuted hypotheses and the story of
   how the diagnosis converged go to the dated archive with a pointer.
   **Run `tools/gate.sh inventory` and paste its output into the
   closeout message.** It must exit 0 (every `tools/` runner classified, no
   live doc claiming uncommitted work). Compare its numbers with the previous
   closeout: the cold-start set and live-markdown lines must not go up; if
   your session raised them, trim before landing. A session that adds a file
   says why one existing home would not do (`CLAUDE.md` hard rules).
6. State explicitly what was NOT verified. Silence about a gap is a claim,
   and claims need evidence here.
7. Update this repo's row on the suite board (suite `../CLAUDE.md`): `lanes/mac4dstem`, from `docs/status.md`'s
   table and handoff, every number dated to its own run; `pickup.prompt` is the exact text the owner pastes next.
8. One sentence on the skills themselves: did any skill misfire, get
   ignored, or fail to trigger when its moment came? Skills are repo files —
   if one needs reshaping, edit it now and it ships with this session's
   commit. Friction nobody records is friction the next session repeats.
9. **Commit** (rule changed by the owner 2026-09-16; this step used to say
   "do not commit unless the user asked"). Land the work as coherent commits
   with the gate numbers in the message, and the docs in the same commit as
   the code they describe. **Pushing is still the owner's** — ask if it should
   go out. `main` only — no feature or worktree branches (owner, 2026-09-17).
