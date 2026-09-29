# Phase-match tolerance D1 — results (2026-09-29 night; YELLOW, measured, nothing shipped)

Registered first (`phase-tolerance-registration-2026-09-29.md`, `7f99ded`; amendment `3f828d5` before the raw grid
was read). Sonnet runner, Opus refuter (`d1-refuter.md`: tables faithful on 16 spot-checks), the orchestrator read raw.
Instrument: `tools/phase-map-probe --tolerance-px k` (pair = matrix = k·Q, verdict 0.75·k·Q; refuses a value that
does not parse), break tests (i) k 1 = `--scale-to-detector` label map identical, (ii) k = 0.02/Q = the no-flag run,
(iii) pair-only mutation red; the verdict line does not bind on the demo (0.015 → 0.020 Å⁻¹ at k 1.667 changes no
result). Reproduction points: Thronsen 383 = 1.31 %, demo 97.0 %, binned 91.1 / 0.8 / 8.1, raw k 4 exact and k 1
96.9 vs 97.0 (a three-way tie of equivalent matrix axes; within the amendment's tie noise). Peaks constant per dataset.

**Result: the shipped rule R0 = max(0.02 Å⁻¹, one detector pixel) lies inside every dataset's band; a fixed 0.02 misses
the binned cube (22.2 % not indexed vs 8.1 % at its one pixel); tolerances below ~0.01 Å⁻¹ fail everywhere.** The raw
cube at the app's 0.02 (3.04 px) gives matrix 84.4 %, not indexed 14.2 % — the "97 % not indexed" was the probe's own
one-pixel rule, never the app's. Supports option (a): keep R0, fix nothing in the app.

Predictions: **P1** τ_sat held on Thronsen (0.010), binned (0.0265) and raw (0.0197 = 3 px), refuted on the demo
(0.030, where its explained fraction is inflated — mean residual 0.0214 vs 0.0177). **P2** held on both halves (raw 0.02
→ 84.4 % ≥ 80, 0.0132 → 61.2 % ≥ 60; binned 0.02 → 75.4 %, 0.01 → 4.5 %). **P3** partly refuted (0.076 is only
+0.14 pp worse; the search rule is not flat: 10.96 / 4.44 / 17.79 % at 0.01 / 0.02 / 0.03). **P4** direction held, size
refuted (grain A −16.4 pp vs the predicted 5–15). **P5** "no single k fits every band" REFUTED — 3 px passes all four
registered bands; R0 does too. Unregistered, real in the logs: the demo's [111] grain C is 100 % not indexed at ≤ 0.010
and at ≥ 0.030 (matrix at 0.012–0.024) — one synthetic grain, not a mechanism, but a fixed 0.03 would lose it. At
exactly one pixel (0.0190) Thronsen passes every T4 metric; at 0.0200 it fails θ′ edge-on speckle 7 > 5 — a two-speck
margin on one dataset, not a validation. Tables verbatim below; logs `tol-*.log` (session scratchpad, not retained).

## Thronsen A (known variants; T4)
|---|---|---|---|---|---|---|---|
| 0.5000 | 0.0095 | 774245 | 72.4 | 970, 3.32 | FAIL | T1/raw spurious=39; T1/raw merge=2; T1/P/9 split=4; T1/P/9 merge=2 | 0 |
| 0.5252 | 0.0100 | 774245 | 73.3 | 804, 2.75 | FAIL | T1/raw spurious=28; T1/P/9 split=4; T1/P/9 merge=1 | 0 |
| 1.0000 | 0.0190 | 774245 | 75.6 | 384, 1.31 | PASS |  | 0 |
| 1.0504 | 0.0200 | 774245 | 75.6 | 383, 1.31 | FAIL | θ′ edge-on/raw spurious=7 | 0 |
| 1.5756 | 0.0300 | 774245 | 75.8 | 409, 1.40 | FAIL | θ′ edge-on/raw spurious=6 | 0 |
| 2.0000 | 0.0381 | 774245 | 75.8 | 420, 1.44 | FAIL | θ′ edge-on/raw spurious=9 | 0 |
| 3.0000 | 0.0571 | 774245 | 75.8 | 424, 1.45 | FAIL | θ′ edge-on/raw spurious=9 | 0 |
| 4.0000 | 0.0762 | 774245 | 75.8 | 424, 1.45 | FAIL | θ′ edge-on/raw spurious=9 | 0 |

Search rule:
| k px | tol Å⁻¹ | peaks | explained % | mislabelled (n, %) | matrix % | exit |
|---|---|---|---|---|---|---|
| 0.5252 | 0.0100 | 774245 | 73.3 | 3206, 10.96 | 73.1 | 0 |
| 1.0504 | 0.0200 | 774245 | 75.6 | 1297, 4.44 | 73.7 | 0 |
| 1.5756 | 0.0300 | 774245 | 75.8 | 5202, 17.79 | 73.7 | 0 |

## Demo cube (truth mode)
| k px | tol Å⁻¹ | peaks | explained % | matrix % | grain A as matrix | end-on β″[010] | needle β″[001] | grain B as β″ | vacuum no data | exit |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.5000 | 0.0060 | 93635 | 13.1 | 56.1 | 83.6 | 100.0 | 100.0 | 43.8 | 100.0 | 0 |
| 0.8333 | 0.0100 | 93635 | 13.1 | 66.0 | 83.6 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 1.0000 | 0.0120 | 93635 | 18.9 | 97.0 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 1.6667 | 0.0200 | 93635 | 37.9 | 97.0 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 2.0000 | 0.0240 | 93635 | 38.0 | 97.0 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 2.5000 | 0.0300 | 93635 | 75.7 | 74.0 | 99.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 3.0000 | 0.0360 | 93635 | 75.7 | 74.0 | 99.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |
| 4.0000 | 0.0480 | 93635 | 75.7 | 73.5 | 99.0 | 1.0 | 100.0 | 0.0 | 100.0 | 0 |
| no flag | 0.0200 | 93635 | 37.9 | 97.0 | 100.0 | 100.0 | 100.0 | 0.0 | 100.0 | 0 |

## Binned Al-Mg-Si (stride 2, distortion-corrected)
| k px | tol Å⁻¹ | peaks | top-axis explained % | matrix % | β″[010] | β″[001] | not indexed % | EXIT | guard peak MB |
|---|---|---|---|---|---|---|---|---|---|
| 0.3771 | 0.0100 | 1010514 | 49.0 | 4.5 | 6.4 | 0.7 | 88.5 | 0 | 1405 |
| 0.5000 | 0.0133 | 1010514 | 67.5 | 22.7 | 8.3 | 0.6 | 68.4 | 0 | 1074 |
| 0.7542 | 0.0200 | 1010514 | 88.0 | 75.4 | 2.3 | 0.1 | 22.2 | 0 | 1405 |
| 1.0000 | 0.0265 | 1010514 | 94.5 | 91.1 | 0.7 | 0.1 | 8.1 | 0 | 1357 |
| 1.1313 | 0.0300 | 1010514 | 95.4 | 93.0 | 0.0 | 0.2 | 6.8 | 0 | 1268 |
| 2.0000 | 0.0530 | 1010514 | 96.3 | 94.0 | 0.0 | 0.0 | 6.0 | 0 | 1074 |
| 3.0000 | 0.0796 | 1010514 | 96.3 | 94.0 | 0.0 | 0.0 | 6.0 | 0 | 1298 |
| 4.0000 | 0.1061 | 1010514 | 96.3 | 94.0 | 0.0 | 0.0 | 6.0 | 0 | 1183 |

## Raw Al-Mg-Si, stride 3 (read after the amendment)
| k px | tol Å⁻¹ | peaks | top-axis explained % | matrix % | β″[010] | β″[001] | not indexed % | EXIT | guard peak MB |
|---|---|---|---|---|---|---|---|---|---|
| 0.5000 | 0.0033 | 116150 | 14.6 | 0.0 | 0.6 | 0.0 | 99.4 | 0 | 1125 |
| 1.0000 | 0.0066 | 116150 | 42.7 | 2.0 | 0.9 | 0.1 | 96.9 | 0 | 1126 |
| 1.5205 | 0.0100 | 116150 | 67.7 | 28.0 | 2.0 | 0.4 | 69.6 | 0 | 1126 |
| 2.0000 | 0.0132 | 116150 | 81.7 | 61.2 | 2.3 | 0.7 | 35.8 | 0 | 1125 |
| 3.0000 | 0.0197 | 116150 | 91.3 | 84.2 | 1.1 | 0.4 | 14.3 | 0 | 1125 |
| 3.0409 | 0.0200 | 116150 | 91.3 | 84.4 | 1.0 | 0.4 | 14.2 | 0 | 1125 |
| 4.0000 | 0.0263 | 116150 | 92.3 | 86.4 | 0.8 | 0.2 | 12.6 | 0 | 1125 |
| 4.5614 | 0.0300 | 116150 | 92.4 | 86.5 | 0.0 | 0.3 | 13.2 | 0 | 1124 |
