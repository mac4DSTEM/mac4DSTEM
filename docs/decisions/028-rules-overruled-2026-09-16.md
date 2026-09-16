# 028 — Three rules overruled (C5 form, on-screen claims, commit freely); the merge split

Dates: 2026-09-07 night (precursor), 2026-09-16

Status: live

## Decision

Three standing rules are overruled by the owner on 2026-09-16. **C5's hard
form** (AppState.swift + ResultExport.swift forbidden to net positive lines)
is overruled — see ADR 002. **On-screen verification may be claimed by the
assistant** when it actually drove the app and is sure, superseding "the
owner drives" from Track B's retirement: name the build, say what was
clicked, say what was seen; if it was not driven, say it is unverified. An
assumed screen is worse than an admitted gap. **Commit freely; pushing stays
the owner's**, retiring "commit only when asked". Separately, the merge is
split: 69 of 90 commits since v3.0.0 had nothing to do with phase mapping and
were waiting on a band that may take weeks; `split/no-phase-mapping` carries
27 to `main`, including one cherry-picked CI fix, which costs the later
merge its fast-forward shape.

## Why

The C5 block was pushing state into worse homes to keep a count down. The
on-screen rule's precursor is the 2026-09-07 night "C3 delegated" entry,
which first distinguished agent-verified from owner-verified driving; by
2026-09-16 the owner's condition — "the assistant needs to drive the app
better" — made a bar rather than a blanket permission the right shape. A red
CI job on the public `main` is worse than a non-linear history.

## Governs

`CLAUDE.md`'s C5/on-screen-claim/commit-freely rules; `tools/run-tests.sh
inventory`'s size-delta report.

## Sources

- 2026-09-07 night "C3 delegated (owner)" (precursor: agent-verified vs. owner-verified), log line 530
- 2026-09-16 "three rules overruled by the owner, and the merge is split", log line 1551
