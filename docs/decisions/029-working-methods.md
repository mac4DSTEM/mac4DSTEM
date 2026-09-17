# 029 — Working methods

Dates: 2026-08-31 (drafted), 2026-09-02 (adopted), 2026-09-07 (moved in), 2026-09-16 (threshold rule)
Status: live

## Decision
**Three named methods**, each earned by a dated incident. *Read the gate's own
exit line, never the wrapper's* — `| tail` reports `tail`'s exit, not the
gate's (swallowed a failing gate three times); redirect to a log, `echo $?`
on its own line, grep the log. *Resume a lost session from its scratchpad,
not from memory* — the scratchpad survives a session death; never re-derive a
number a retained log already holds. *Count a gate's tests by name, and
reconcile against the expected delta* — unique method names via grep, diffed
against the expected count; never conclude a test vanished from a count alone.

**Eight numbered methods**, each earned the same way: (1) cost a UI change
before designing it; (2) adversarially review anything touching the science,
review the diagnosis not just the code — three fixes have passed every test
written for them and still been wrong; (3) never widen a gate that fails
silently; (4) open the app — ten minutes of driving twice found defects a
green suite could not; (5) a green suite can be green about the wrong thing —
check the calling convention it actually exercises; (6) a test written for
your own fix proves nothing until it fails without it; (7) do not drive the
app while `unit` runs — both share an `AppStorage` domain; (8) break every
new test before trusting it — three green-but-worthless suites were caught
only this way.

**Threshold rule** (2026-09-16): a guard's number is a property of the
dataset and settings it was measured under, never of the method, until
measured on every dataset it will run on — adopted after a fall-back
pre-registered at an unmeasured `f=0.8` (actual ≈0.29) and a bar measured on
one dataset that flagged 46% of a passing second. **Corollary**: do not infer
a mechanism from a null result — refuted by the next measurement when 98%
turned out to come from an unrelated, previously-unfired path.

**Five evidence levels** — reported, source-confirmed, reproduced,
regression-protected, visually accepted — answer different questions; a
review can be complete with unresolved findings, but a release cannot treat
those as verified.

## Why
Each method is distilled from a specific incident that cost real time, named
inline above, not a hygiene preference.

## Governs
`CLAUDE.md`'s hard rules; `.claude/skills/diagnose`, `.claude/skills/adversarial-review`; `tools/run-tests.sh`.

## Sources
`docs/archive/development-process-2026-08-31.md` lines 175/186/193 (three
named methods); 170–174 (eight numbered methods); 66–90 (threshold rule +
corollary); 91–108 (five evidence levels). Corroborating decisions-log
entries: 2026-09-01 "v2 endgame scope" (token conservation is a standing
directive — lower-tier models when safe, terse docs, heavy gates only for
science), log line 25; 2026-09-02 "Live doc set" (the live-doc-set convention
`CLAUDE.md`'s reading order continues), log line 390.
