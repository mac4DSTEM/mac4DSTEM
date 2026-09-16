# 015 — Even-count median pinned to `np.median` below the `all` gate

Dates: 2026-09-09

Status: live

## Decision

The even-count median rule is pinned by a unit test on a fixture where the
two rules (round-to-nearest-index vs. `np.median`'s true average-of-two)
differ by 0.144px, reachable from `run-tests.sh unit`. The
`calibrationData_bullseyeProbe.h5` fixture is pinned in `expected.json`.

## Why

A 2026-09-08 red gate turned out to be a stale-golden Gate D, not a
regression: `ba6360d`'s `np.median` parity correction was correct, but until
this decision the ONLY thing standing behind it was one harness reachable
solely from `run-tests.sh all`, so a corrected number sat against a stale
golden for three days undetected. Pinning the bullseye cube closes the
matching gap: `compare.py` only compares what is pinned, and the cube had
drifted invisibly behind an `UNPINNED:` line nobody was reading.

## Governs

The `median` implementations in `EllipseCalibration`, `OriginCalibration`,
`ParallaxAlignment`, `QCalibration`, `StrainMapping` (kept deliberately
separate — see `docs/audit/REPORT.md` §3.2 item 9); `expected.json`'s
bullseye pin.

## Sources

- 2026-09-09 "the even-count median is pinned below the `all` gate", log line 759
