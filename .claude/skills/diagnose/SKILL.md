---
name: diagnose
description: Diagnose before fixing in mac4DSTEM. Use whenever the user reports a bug, crash, wrong number or odd behaviour, or asks why the app does X, before proposing a fix, even when the cause seems obvious. A confident wrong diagnosis that passed its own tests has been shipped here before.
---

# Diagnose before touching code

Not a registered gate any more (retired 2026-10-15), still the cheapest way to avoid fixing the wrong thing.

1. **Read what is known.** Search `docs/open-items.md` for the symptom (the error string, the file, the room) and read the whole entry: it may carry hypotheses a previous session already refuted. Older records are under `../_archive/mac4DSTEM/docs/archive/`. If your account differs from a recorded one, say so.
2. Write down before any code changes: the diagnosis and its evidence; the observation that would refute it; the predicted outcome of a discriminating experiment.
3. Run the cheapest discriminator (deterministic against intermittent, a local copy against the NAS, a footprint watch). If none exists, say what the cheapest one costs.
4. The fix lands on a diagnosis that survived its refutation test, with a test that fails before and passes after. The one review by a second lane (`/adversarial-review`) is given the evidence, not only the diff, and is told to attack the harness too.
5. Record the outcome, with refuted hypotheses and dates, in `docs/open-items.md` so the next reader does not re-walk a dead end.

A defect whose mechanism a reproducing observation already proves needs no diagnosis: state that and fix it.
