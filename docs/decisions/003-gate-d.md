# 003 — Gate D: trigger, exemptions, refuter, fixture

Dates: 2026-08-18, 2026-09-04

Status: live

## Decision

Gate D (written diagnosis and experiment before a fix) applies when a change
can move a scientific number, or when the cause of a defect is not yet
established — not to every change in `Core/`. What does NOT need it: pure
placement and presentation changes, renames, docs, tooling, and defects whose
mechanism is already proven by a reproducing observation. Diagnosis, refuting
observation, predicted outcome, then the experiment, before the fix; an
independent refuter after; a fixture.

## Why

Three confident wrong diagnoses had each passed every test written for them
before Gate D existed. The trigger was later sharpened because "anything that
changes a scientific number" was in practice reached for on changes that
touch no number; the day it was sharpened, the same refuter discipline caught
that the session's own sidecar fix was aimed a level too low, finding a worse
defect underneath that the author had not looked for.

## Governs

`.claude/skills/diagnose/SKILL.md`, any change under `mac4DSTEM/Core/` or
`mac4DSTEM/Session/` that can move a scientific number.

## Sources

- 2026-08-18 "The v2 contract and the three gates", log line 17
- 2026-09-04 "Gate D's trigger is sharpened; the refuter stays", log line 308
