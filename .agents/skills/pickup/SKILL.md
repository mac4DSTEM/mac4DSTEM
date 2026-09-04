---
name: pickup
description: Start the next mac4DSTEM development target from docs/status.md. Use whenever the user says "pick up", "next session", "continue the app", or names a target — a bug they reported, an open item, a v3 feature, a consolidation item — even when they don't say which list it comes from. Reads the status table, takes the named target, and enforces its gate.
---

# Pick up a target

`docs/status.md` is the source of truth for what is live and what is next.
Targets come from three lists: bugs the owner reports (each through
`/diagnose`), `docs/open-items.md` (defects, debts, open questions), and
`docs/v3-plan.md` (features, pre-registered before they are built). This
skill only makes sure you enter them correctly.

1. Read `CLAUDE.md` (if not in context), then `docs/status.md`, then the
   target's own record: its `open-items.md` entry, its `v3-plan.md` section,
   or the owner's report.
2. The user names the target ("/pickup the origin-fit guard", "/pickup the
   Results crash I reported"). With no name, take the top of the status
   handoff. If the target needs something only the user can provide — a
   decision, a data file — and it is not in the conversation, do the parts
   that don't need it, then stop and say exactly what is needed. Never guess
   the user's answer to keep an unattended run moving.
3. Before any work, restate in one short block: the target's scope, its gate
   (unit / unit+scientific / Gate D / Gate B), what it deletes, which release
   it lands in (a v2.5.x patch for a bug; no number for a science item; v3.0
   for the first feature), and any decision the user makes in-step. A feature
   is pre-registered first (`v3-plan.md` §6).
4. Non-negotiables (each has burned this repo): Gate D before any fix
   (`/diagnose`); an independent refuter for anything that changes a number
   in Core (`/adversarial-review`); a session touching `AppState` moves one
   responsibility out; break every new test before trusting it; a change to
   what the app draws is stated as unverified on screen until the owner has
   seen it; do NOT set `ResidencyAdmission.measuredWorkingSetFraction`.
5. One target per conversation. When the work lands, invoke `/closeout`.
   Commit only if asked.
