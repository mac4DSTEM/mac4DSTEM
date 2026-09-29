# Training step loop leak — Gate D record (2026-09-30)

**Observation** (`c5-training-leak-run-2026-09-30.log`): the app's Training/ path grew 227 MB (step 1) → 1313 (100) →
2404 MB (200), 10.9 MB/step, linear; 500 steps → ~5.7 GB. Arithmetic, not a measurement: one step creates ~11.7 MB of
MPSGraphTensorData (4 micro-batch feeds 8.4 MB + optimizer outputs 3.3 MB) — consistent with "every tensor made per step
stays alive", silent on why.

**Candidates, each with its refuting observation (pre-registered before any change):**
M1 autorelease accumulation — `trainBlocking` runs as one `Task.detached` job, so MPSGraph's autoreleased results drain
only when it returns; refuted if the slope stays ≥ 5 MB/step with per-step pools. M2 MPSGraph per-run caching (tested
only if M1 refuted); M3 Swift-side retention (refuted if M1 or M2 flattens it); M4 growth outside the loop (refuted: the
slope is per step); M5 per-step recompilation (shapes are constant). Prediction: slope ≤ 1.0 MB/step over steps 10–60.

**Experiments** (`tools/training-run-probe`, `TR_PROBE_TRAIN_ONLY=1`, 23 training samples, recipe defaults, one build
script, the working-tree `Training/*.swift` compiled into the probe; slope = least squares, steps ≥ 10):

| run | change | steps | slope MB/step | footprint 10 → end | lifetime max |
|---|---|---|---|---|---|
| e0 | none | 60 | 10.895 | → 880 MB | 944 MB |
| e1a | pool round each micro-batch only | 60 | 4.713 | 273 → 510 | 576 MB |
| e1b | pools round micro-batches and the optimizer run | 60 | 0.050 | 232 → 236 | 302 MB |
| e2 | one pool round the whole step (shipped) | 120 | 0.040 | 230 → 236 | 391 MB |

Losses identical at every logged step across e0–e2 and equal to the C5 run's at step 100: the pool changes memory only.
M1 confirmed; both runs leak (micro-batches ~6.2, optimizer ~4.7 MB/step). M2/M3/M5 not implicated.

**Fix.** `DetectorTrainer.trainBlocking`: one `autoreleasepool` per step (it rethrows, so cancellation propagates; the
progress callback and the loss record stay outside it). The probe calls the same `DetectorTrainer.train` →
`trainBlocking` that `DetectorFineTuning.run` and the app's Train Model… call.

**Test.** `DetectorTrainerTests.testTheFootprintDoesNotGrowWithTheStepCount`: phys_footprint growth over steps 10 → 40
< 120 MB (the leak: ~330 MB; flat runs: −7 to +4 MB). Green 2026-09-29 ~16:39 (session eb2a2d51 `me/green.log`, exit 0);
with the pool replaced by a plain closure, red (`me/mut.log`, exit 65). Swap pressure can only shrink the delta.

**Independent refuter (Fable, 2026-09-30): COMMIT.** Slopes recomputed from the per-step samples (10.903, 4.714, 0.049,
0.037); probe path = app path; diff is the pool alone. The C5 log's "the run started anyway" was the probe's own retry
loop passing admission on attempt 9 — the app throws once, no bypass.

**Owed.** The full 500-step C5 run on a quiet machine (peak predicted < 1.5 GB); the in-app Train Model… drive.
