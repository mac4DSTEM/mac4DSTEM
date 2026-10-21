# Performance of the main actions on the demos

Measured by `PerformanceJourney` (XCTest metrics, five iterations each, the Debug build with `SWIFT_OPTIMIZATION_LEVEL=-O` as the UI
gate builds it). Run with `tools/run-tests.sh ui Performance` (a bare `ui` skips it, `ui all` includes it). The first numbers:
2026-10-21, Apple M5 Pro, macOS 27.0.1, the commit that adds this file. Medians of five.

| Action (demo data) | Clock (s) | Peak memory (MB) | CPU time (s) | What one iteration drives |
|---|---|---|---|---|
| Open the demo (launch to ready) | 4.24 | not measured | not measured | launch, load, preview, workspace ready |
| Prepare: Re-calibrate Origin (origin and probe) | 2.75 | 254 | 0.30 | one click, wait for the busy state to end |
| ADF virtual image | 4.37 | 203 | 0.46 | two clicks (workspace, action), wait |
| Bragg disk detection, all 144 positions | 4.35 | 193 | 0.40 | two clicks, wait |
| Strain from the disks | 6.04 | 212 | 0.56 | three clicks (workspace, task, action), wait |
| Auto ID and Quantify (demo spectrum image) | 4.45 | 348 | 0.69 | three clicks, wait |

How to read it, honestly:

- **The clock includes the UI driver.** Every iteration is clicks and waits through XCUITest; one click-and-wait cycle costs about
  1.5 to 2.7 s on its own (the Prepare row has one click and is the floor: 2.75 s; each further click adds about 1.5 s). The actions
  themselves on the 12 x 12 x 64 x 64 demo are therefore well under a second and are not resolved by this journey. Do not read the
  clock column as the app's speed; read it as a regression tripwire (a step that moves by seconds).
- **CPU time** is the app process's CPU time in the iteration (the compute the app really did): 0.3 to 0.7 s per action.
- **Peak memory** is the app's physical footprint peak (it includes the app's idle footprint of about 100 to 200 MB).
- Meaningful speed numbers need a real cube (the study datasets, 28 GB class) and a driver that reads the app's own timings
  (the status line's "Last run" values) instead of the UI round trip; that is a later session (a `--benchmark` launch flag that
  writes the app's own per-action durations to `--export-dir`).
