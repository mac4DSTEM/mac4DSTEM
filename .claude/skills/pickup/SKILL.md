---
name: pickup
description: Start the next mac4DSTEM development target from docs/status.md. Use whenever the user says "pick up", "next session", "continue the app", or names a target — a bug they reported, an open item, a ROADMAP feature, an overnight plan — even when they don't say which list it comes from. Reads the status table, takes the named target, and states its scope.
---

# Pick up a target

`docs/status.md` is the source of truth for what is live and what is next. Targets come from the bugs the owner reports (each through `/diagnose`), `docs/open-items.md` (defects, debts, kit asks) and `ROADMAP.md` (features).

1. Read `CLAUDE.md` and `../CLAUDE.md` if not in context, then `docs/status.md` and the target's own record: its `open-items.md` entry, its `ROADMAP.md` section, or the owner's report. The board row `lanes/mac4dstem` carries the exact pickup prompt.
2. The user names the target. With no name, take the top of the status hand-off. If the target needs something only the owner can provide (his data, Apple ID, taste, names) and it is not in the conversation, do the parts that do not need it, then stop and say exactly what is needed. Decide engineering, order and tolerance questions yourself from the record. Unattended: decide, park what needs the owner on the row's `waiting`.
3. Before work, restate in one short block: the scope, the tests that will fail before and pass after, what it deletes, the release it lands in (`tools/release/README.md`), and any decision the owner makes in-step. A number a scientist reads gets a pinned regression test against py4DSTEM (`CLAUDE.md`, Numbers).
4. Rules that have burned this repo: diagnose before fixing a wrong number (`/diagnose`); one review by a second lane (`/adversarial-review`); a session touching `AppState` moves one responsibility out where that makes the app better; a change to what the app draws is unverified on screen until a drive saw it; do NOT set `ResidencyAdmission.measuredWorkingSetFraction`. Run gates as `tools/gate.sh <unit|core|scientific|inventory>`.
5. One target per conversation, unless a plan file names the night's list. When the work lands, invoke `/closeout`. Commit on `main` (no branches); pushing is the owner's.
