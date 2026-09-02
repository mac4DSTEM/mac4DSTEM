---
name: pickup
description: Start the next mac4DSTEM development step from docs/status.md and the v2.5 consolidation plan. Use whenever the user says "pick up", "next session", "continue the app", "take step 3", or asks what to work on next — even when they don't name the plan or a step. Reads the status table, takes the next step, and enforces its gate.
---

# Pick up the next step

`docs/status.md` and `docs/v2.5-plan.md` are the source of truth; this skill
only makes sure you enter them correctly.

1. Read `CLAUDE.md` (if not in context), then `docs/status.md`, then the
   step's row in `docs/v2.5-plan.md` §5 and the rules in §7.
2. Take the lowest step in `docs/status.md` not marked done. The user naming
   one ("/pickup step 3") wins. If the step needs something only the user can
   provide — a decision from the plan's §8, a Track B drive, a data file —
   and it is not in the conversation, do the parts that don't need it, then
   stop and say exactly what is needed. Never guess the user's answer to keep
   an unattended run moving.
3. Before any work, restate in one short block: the step's scope, its gate
   (none / unit+scientific / B / short Track B), what it deletes, and any
   decision the user makes in-step.
4. Non-negotiables (each has burned this repo): Gate D before any fix
   (`/diagnose`); an independent refuter for anything that changes a number
   in Core (`/adversarial-review`); a session touching `AppState` moves one
   responsibility out; break every new test before trusting it; a change to
   what the app draws queues Track B rows (`/track-b`); do NOT set
   `ResidencyAdmission.measuredWorkingSetFraction`.
5. One step per conversation. When the work lands, invoke `/closeout`.
   Commit only if asked.
