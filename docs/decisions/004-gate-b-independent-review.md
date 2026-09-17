# 004 — Gate B: independent review of science; review the diagnosis

Dates: 2026-08-18, 2026-08-31, 2026-09-02

Status: live

## Decision

Gate B is an independent refuter for changes that alter a number in `Core/`.
Gate A fleets (multi-reviewer passes) are retired in favour of one reviewer;
Track B is a ten-row drive per user-visible slice plus the full checklist
once per tag (later itself retired, see 010). Session records are commit
messages plus one paragraph in the decisions log — as short as "S14 and S15
merged by owner decision" when that is all there is to say.

## Why

Three confident wrong diagnoses had each passed every test written for them;
the model that wrote a change is not positioned to find what it did not think
to check. Reviewing the diagnosis, not the diff, is what catches a test suite
that confirms its own author's hypothesis.

## Governs

`.claude/skills/adversarial-review/SKILL.md`; any commit touching `Core/` or
`Session/` that can move a scientific number.

## Sources

- 2026-08-18 "The v2 contract and the three gates", log line 17
- 2026-08-31 "W4a merged", log line 23
- 2026-09-02 "Gate ceremony", log line 48
