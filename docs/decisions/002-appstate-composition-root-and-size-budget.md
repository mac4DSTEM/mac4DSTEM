# 002 — `AppState` is the composition root; new state names its owner; C5 size is reported, not gated

Dates: 2026-08-17, 2026-09-03, 2026-09-07, 2026-09-16

Status: live; the 2026-09-07 hard-gate form is overruled 2026-09-16 (see 028)

## Decision

Any stage touching `AppState` extracts one seam first, at a green test
boundary, the extracted type itself `@Observable` — `extension AppState { }`
does not count. The run functions (`runACOM`, `applyACOMDisplay`,
`runStrainMapping`) stay on `AppState` for now rather than being pulled into
an injected-host session type, because that would move ~20-member coupling
rather than remove it; revisit as one run layer for every family
(`AnalysisRunner`, unscheduled — see 031). From 2026-09-07, `run-tests.sh
inventory` measured `App/AppState.swift` + `Support/ResultExport.swift`
against the prior commit and failed if they grew. From 2026-09-16 that hard
form is overruled: growth is allowed where it is the honest place for the
state, `inventory` **reports** the delta instead of failing on it, and a
commit that grows the files says in its message why no other home would do.

## Why

The facade was growing faster than it was being decomposed. The numeric C5
gate stopped a four-session waiver pattern, but pushed state into worse homes
just to keep a count down; the measurement stays because unmeasured growth is
how the files reached 5 461 and 1 939 lines, but the block was the wrong
enforcement for the goal.

## Governs

`mac4DSTEM/App/AppState.swift`, `mac4DSTEM/Support/ResultExport.swift`,
`tools/run-tests.sh` inventory's size check.

## Sources

- 2026-08-17 "The `AppState` seam rule", log line 12
- 2026-09-03 "The run functions stay on `AppState` (7c 4b)", log line 373
- 2026-09-07 "C5: the `AppState` rule is a number, not a sentence" (superseded), log line 497
- 2026-09-16 "three rules overruled" (C5 clause), log line 1551
