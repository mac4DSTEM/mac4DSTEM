---
name: pickup
description: Start the next mac4DSTEM development target from docs/status.md. Use whenever the user says "pick up", "next session", "continue the app", or names a target — a bug they reported, an open item, a ROADMAP feature, an overnight plan — even when they don't say which list it comes from. Reads the status table, takes the named target, and enforces its gate.
---

# Pick up a target

`docs/status.md` is the source of truth for what is live and what is next.
Targets come from three lists: bugs the owner reports (each through
`/diagnose`), `docs/open-items.md` (defects, debts, open questions), and
`ROADMAP.md` (features, pre-registered before they are built) — and,
the consolidation plan closed 2026-09-11 (`docs/archive/consolidation-plan.md` §6: gates C0–C8, each with an
exit criterion, executed in order before any feature (owner, 2026-09-07).
This skill only makes sure you enter them correctly.

1. Read `CLAUDE.md` (if not in context), then `docs/status.md`, then the
   target's own record: its `open-items.md` entry, its `ROADMAP.md` section,
   or the owner's report.
2. The user names the target ("/pickup the origin-fit guard", "/pickup the
   Results crash I reported"). With no name, take the top of the status
   handoff. If the target needs something only the user can provide — a
   decision, a data file — and it is not in the conversation, do the parts
   that don't need it, then stop and say exactly what is needed. Unattended
   (owner, 2026-09-29, "decide, don't stall"): decide from the record (ADRs,
   `CLAUDE.md`, the owner's recorded preferences); otherwise ask an Opus advisor
   subagent to argue against the proposal; if it endorses and the step is
   reversible, do it and list it as "decided overnight — overrule on sight".
   Stop only on a push, a delete, a moved shipped number, a Frozen Shell
   redesign, or anything outside the repo.
   The consolidation plan closed 2026-09-11, so a feature target is no
   longer refused: a v3 feature is a target, pre-registered and built the
   way `ROADMAP.md`'s "How a v3 feature is done" section says. A closed consolidation gate ("/pickup C1")
   is history now — read it in `docs/archive/consolidation-plan.md`.
   **A red gate outranks a verification gate** (2026-09-09): when the plan's
   first failing exit criterion needs the owner's eye and the handoff also
   names a defect blocking the release, take the defect — it is the one a
   session can finish alone, and diagnosing it runs gates, which forbids
   driving anyway. Say which you took and why.
3. Before any work, restate in one short block: the target's scope, its gate
   (unit / unit+scientific / Gate D / Gate B), what it deletes, which release
   it lands in (a driven bug cuts v4.0.x, a landed science number v4.1.0 —
   `docs/releasing.md`), and any decision the user makes in-step. A feature
   is pre-registered first (`ROADMAP.md`'s "How a v3 feature is done" section).
4. Non-negotiables (each has burned this repo): Gate D before any fix
   (`/diagnose`); an independent refuter for anything that changes a number
   in Core (`/adversarial-review`); a session touching `AppState` moves one
   responsibility out where that makes the app better (never a move for its own
   sake — `CLAUDE.md` "Rules serve the app"); break every new test before trusting it; a change to
   what the app draws is unverified on screen until a drive has seen it (the
   owner's, or a session's on a scratch build, pid-pinned, every shot reviewed —
   `CLAUDE.md`); do NOT set `ResidencyAdmission.measuredWorkingSetFraction`.
5. One target per conversation, unless a plan file names the night's list
   (then log each item in it as it lands). When the work lands, invoke
   `/closeout`. Commit freely on `main` (no branches); pushing is the owner's.
