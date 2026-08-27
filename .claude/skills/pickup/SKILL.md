---
name: pickup
description: Start the next mac4DSTEM development session from the v2 release plan. Use whenever the user says "pick up", "next session", "continue the app", "take S7", or asks what to work on next — even when they don't name the plan or a session. Reads the release contract, takes the next unstarted session, and enforces its review gate.
---

# Pick up the next v2 session

You are starting one numbered development session from this repo's release
plan. The plan, not this skill, is the source of truth — this skill only
makes sure you enter it correctly.

1. Read `CLAUDE.md` (if not already in context), then `docs/v2-release.md`:
   §1 (the claim), §7 (the gates), §8 (the session briefs), §9 (status).
2. Take the lowest session in §9 not ticked `[x]` — a partial `[~]`
   session continues before a fresh one starts. **If CLAUDE.md and §9 disagree
   about a session's state, §9 wins and you say so out loud** — it is the
   checklist and it carries the per-session evidence. This is not
   hypothetical: from 2026-08-18 to 2026-08-27 CLAUDE.md said S18 was `[~]`
   with its Gate B second read outstanding while §9 ticked it `[x]` and
   recorded that review running with 24 agents and 30 mutations. Both
   sentences landed in the same commit. Reconcile it in the session that finds
   it rather than leaving the next reader to pick. The user naming one
   ("/pickup S7") wins over both. If the session's next step needs
   something only the user can provide — an experiment result, a decision,
   a Track B drive — and it is not already in the conversation, do the
   parts that don't need it, then stop and state exactly what is needed.
   Never guess the user's answer to keep an unattended run moving; in that
   case prefer the next session that can proceed autonomously, and say
   which gate you routed around. **A supplied answer that still carries the
   prompt's `<placeholder>` brackets is not an answer** — it is the template
   pasted back, and reading it as one is guessing with extra steps
   (2026-08-19: an S1 probe arrived as `<panel appeared / saved silently>`).
   Say which bracket is empty and what each branch would have meant. If dependencies in §8 aren't met, say so
   before starting rather than discovering it mid-session.
3. Before any work, restate in one short block: the session's scope, its
   gate (A, B or D), and any decision the brief says the user makes
   in-session — so those moments don't ambush them.
4. Non-negotiables, each of which has burned this repo before:
   - Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by
     decision; `.automatic` residency is being dropped (S3), not tuned.
   - Gate D: diagnosis, refuting observation, predicted outcome — written,
     then the experiment run — BEFORE any code. Invoke the `diagnose` skill.
   - A session touching `AppState` extracts one seam first
     (`docs/development-process.md` §7).
   - A change to what the app draws queues Track B rows (`track-b` skill)
     and is unverified on screen until the user drives them.
   - Break every new test before trusting it.
5. One session per conversation. When the work lands, invoke the `closeout`
   skill. Commit only if asked.
