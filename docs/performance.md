# Performance of the main actions on the demos

Measured by `PerformanceJourney` (XCTest metrics, five iterations each; the Debug build with `SWIFT_OPTIMIZATION_LEVEL=-O` as the UI
gate builds it). Run with `tools/run-tests.sh ui Performance` (a bare `ui` skips it, `ui all` includes it). Machine: Apple M5 Pro
(64 GB), macOS 27.0.1. Medians of five. Every iteration is a fresh launch and the way to the room, unmeasured (except "open"); the
measured part runs from the click to the busy state ending.

| Action (demo data) | App compute (signpost, s) | UI clock (s) | App CPU time (s) | Peak memory (MB) |
|---|---|---|---|---|
| Open the demo | 0.52 | 2.15 | not measured | not measured |
| Prepare: Re-calibrate Origin | 0.083 | 2.78 | 1.74 | 277 |
| ADF virtual image | 0.078 | 2.77 | 2.20 | 209 |
| Bragg disk detection, all 144 positions | 0.078 | 2.76 | 1.75 | 213 |
| Strain from the disks | 0.045 | 2.70 | 2.44 | 280 |
| Auto ID | 0.062 | 4.42 (with Quantify) | 2.53 (with Quantify) | 361 |
| Quantify (pooled fit) | 0.122 | (above) | (above) | (above) |

How to read it:

- **App compute** is the app's own `os_signpost` interval around the action (`Signposts`, read by `XCTOSSignpostMetric`): the number to
  watch. On the 12 x 12 x 64 x 64 demo every action is well under a second; the demo is too small to rank them.
- **UI clock** includes XCUITest's own click latency and the wait for the busy state: about 2.7 s for any one click, so it is a floor of
  the harness, not the app (an earlier run without the unmeasured preparation read 2.75 to 6 s for the same actions).
- **App CPU time** includes the app's UI work while XCUITest drives it (about 1.7 to 2.5 s per iteration), not just the compute.
- Real speed needs a real cube (the study datasets, 28 GB class): the signposts are in place for it; run the journey's actions by
  hand on that cube with Instruments, or add a launch flag that opens it, in a later session.
