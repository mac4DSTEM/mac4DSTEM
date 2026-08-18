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
primary evidence — the log, the fixture output, not the diff. Record the
outcome in `docs/open-items.md`, including the refuted hypotheses with
dates, so the next reader does not re-walk a dead end that looks fresh.
