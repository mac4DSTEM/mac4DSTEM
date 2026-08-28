---
name: closeout
description: Close a mac4DSTEM development session with the repo's end-of-session discipline. Use whenever a session's work is landing — the user says "wrap up", "we're done", "close it out" — or a numbered session's scope is complete, and always before any commit.
---

# Session closeout

Done means the repo tells the next reader the truth. In order:

1. `tools/run-tests.sh unit` — exit 0. If the session touched `Core/`, run
   the relevant `scientific` harnesses too. **A session that changed nothing
   under `mac4DSTEM/` owes no gate** — say so and name the last run that
   covers this tree, with its date and commit; running one for form proves
   nothing about the session and spends the disk this machine does not have. Put exit codes where you read
   them — a `| tail` pipe has already swallowed a failing gate here once
   (twice: S4's scientific run and S8's first aggregate both lost the
   harness count the same way — retain the full log, grep it after).
   Two non-zero exits are RECORDABLE outcomes, not gates to force green:
   **exit 69** is the S0 free-space preflight refusing (run
   `tools/free-space.sh` — report first, `--clear` deletes the known debris —
   before recording an owner re-run owed; never touch the floor — the MCP
   `test_macos` route is the warm fallback for the app suite), and **exit 65 with exactly the S17
   sidebar intermittent** is the documented flake (add the run to S17's
   observation log in `docs/open-items.md` with the measured heights).
2. If `AppState` was touched: confirm one seam was extracted
   (`docs/development-process.md` §7). Splitting into
   `extension AppState { }` does not count.
3. If the session changed what the app draws: Track B rows are queued (the
   `track-b` skill) and the work is stated as unverified on screen.
4. Tick the session in `docs/v2-release.md` §9 with one line: what shipped
   and what deviated.
5. Update `docs/open-items.md` — add, amend, or delete. Closed items move
   to `docs/archive/` immediately (§1 discipline); the file is loaded by
   every session, so its length taxes all of them.
   **Write findings, not narratives** — the file's own header carries the
   format rule adopted 2026-08-28: what is wrong, the evidence, the trap, the
   owner, the live residual; ≤ 20 lines. Refuted hypotheses and the story of
   how the diagnosis converged go to the dated archive with a pointer. This is
   the discipline that slipped: M1 cut the three-file kickoff tax to 1,901 and
   it was 2,548 two days later, all of it narrative. **Check the tax at
   closeout** — `wc -l CLAUDE.md docs/v2-release.md docs/open-items.md` — and
   if your session pushed it up, say so in the record and trim something.
   **If you edited `CLAUDE.md`, run `tools/sync-agents-md.sh`** (or
   `--check`, which exits 1 when stale). `AGENTS.md` is generated from it since
   2026-08-28 — hand-maintained before that, it drifted six sessions and ended
   up calling a claim unreproduced that S19 had reproduced.
6. State explicitly what was NOT verified. Silence about a gap is a claim,
   and claims need evidence here.
7. Republish the owner's living v2 board (owner request, 2026-08-26):
   artifact `https://claude.ai/code/artifact/02ef433e-3888-4afc-9292-aba62912e5d9`
   ("mac4DSTEM v2 Board"). Update the session rail, workstream fractions,
   the dated test-claim table, and the what's-next queue from
   `docs/v2-release.md` §9 — same honesty bar as the docs: every number
   dated to its own run. From a fresh conversation, pass that address as
   the Artifact tool's `url` (publishing without it forks a new artifact).
8. One sentence on the skills themselves: did any skill misfire, get
   ignored, or fail to trigger when its moment came? Skills are repo files —
   if one needs reshaping, edit it now and it ships with this session's
   commit. Friction nobody records is friction the next session repeats.
9. Do not commit unless the user asked. If they did: linear `main`,
   descriptive message, and the docs updated in the same commit as the code
   they describe.
