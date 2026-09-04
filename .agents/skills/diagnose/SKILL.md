---
name: diagnose
description: Apply mac4DSTEM's Gate D diagnosis protocol before fixing anything. Use whenever the user reports a bug, crash, wrong number, or odd behaviour, or asks "why does the app do X" — BEFORE proposing a fix, even when the cause seems obvious. This repo has three times shipped a confident wrong diagnosis that passed every test written for it.
---

# Gate D — diagnose before touching code

A confident wrong diagnosis that passes its own tests is this repo's
documented failure mode (2026-08-05, 2026-08-06, 2026-08-18 — the last one
twice in a day, both refuted by a second reader of the same code). The
protocol exists because "obvious" causes here have repeatedly been wrong
while the refuting evidence sat in plain sight in a log nobody re-read.

**First, read what is already known.** Search `docs/open-items.md` for the
symptom — the error string, the file, the workspace — and read the whole entry,
not the first paragraph. Then check the archived checklist
(`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`) for a row that
names it. These entries carry hypotheses a previous session already
*refuted*, with dates, and a symptom seen twice is usually recorded once.

Skipping this wastes the expensive half of the protocol. On 2026-08-19 (S1) it
was entered from the top, and the hypothesis it produced — a generic "the sandbox
denies the sibling" — was one a prior review agent had already recorded in
`open-items.md`, sharper, naming a mechanism. That entry also already carried a
*refuted* race hypothesis and the conclusion that the silencing had to be fixed
regardless of which hypothesis won. All of it was re-derived from scratch, and
the entry was found only later, by grepping for the error string while editing
something else. Nothing was wrong in the end — but every minute spent
rediscovering a recorded hypothesis is a minute not spent refuting it.

Read it first; then, if it changes your account, say so explicitly rather than
quietly adopting it — a diagnosis that converged with a recorded one is stronger
evidence than either alone, and a diagnosis that contradicts one is a finding.

Write down, in this order, before any code changes:

1. **The diagnosis** as currently believed, with its evidence.
2. **The observation that would refute it** — what the world would look
   like if the diagnosis were wrong.
3. **The predicted outcome** of a discriminating experiment, stated before
   running it.

Then run the experiment. Cheap discriminators are the norm here, not the
exception: opening the same file three times from a cold launch separated
sandbox-denial from race (deterministic vs intermittent); a `footprint`
watch on a local copy vs the NAS separates memory-mapping from a hidden
full read. If no cheap discriminator exists, design the cheapest one and
say what it costs — do not skip ahead to the fix.

A fix may land only on a diagnosis that survived its own refutation test.
Before the session closes, a second agent reviews the diagnosis against the
primary evidence — the log, the fixture output, not the diff.

**Ask for that second agent EARLY, not at closeout.** Some sessions run under
a harness that forbids spawning subagents unless the user asks for one, so the
gate cannot be satisfied silently. Raise it as soon as the diagnosis firms up,
while there is still time to act on what the refuter finds — on 2026-08-27 the
refuter overturned the stated cause of the defect (it had already reached four
files), corrected an overstated correlation and a reversed chronology, and
supplied the causal control the evidence was missing. All of that needed
follow-up work, not just a note.

**Give the refuter the evidence, not the diff:** the probe logs, the
screenshots, the trial counts, the harness script itself — and tell it to
attack the harness too. Its sharpest finding that day was that five "cold
opens" were two byte-identical screenshots. Record the
outcome in `docs/open-items.md`, including the refuted hypotheses with
dates, so the next reader does not re-walk a dead end that looks fresh.
