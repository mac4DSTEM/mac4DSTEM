---
name: closeout
description: Close a mac4DSTEM development session with the repo's end-of-session discipline. Use whenever a session's work is landing — the user says "wrap up", "we're done", "close it out" — or a numbered session's scope is complete, and always before any commit.
---

# Session closeout

Done means the repo tells the next reader the truth. In order:

1. `tools/run-tests.sh unit` — exit 0. If the session touched `Core/`, run
   the relevant `scientific` harnesses too. Put exit codes where you read
   them — a `| tail` pipe has already swallowed a failing gate here once.
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
6. State explicitly what was NOT verified. Silence about a gap is a claim,
   and claims need evidence here.
7. Do not commit unless the user asked. If they did: linear `main`,
   descriptive message, and the docs updated in the same commit as the code
   they describe.
