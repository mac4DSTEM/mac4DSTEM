# New-Mac Gate D, 2026-09-30 evening — M5 Pro, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a)

Two unit failures on the first gate run of the new Mac (`unit-newmac.log`: 1300 / 3 / 4 = 1307). Both diagnosed with an
independent Fable refuter each; records below are the session's verbatim, the repro programs sit beside this file
(`mpsgraph-pool-bisect.swift`: `xcrun swiftc -O mpsgraph-pool-bisect.swift -o b && ./b bf16 vo`, exit 139 = the crash;
flags in its header; `coreml-compute-plan.swift <mlpackage>`: the per-op device plan and the compute-unit heatmap diffs).

## 1 — DetectorTrainer SIGSEGV (MPSGraph PoolMaxGradientOp) — FIXED

Prior record: none in open-items.md (grep PoolMax/MPSGraph/DetectorTrainer: no hits).
Evidence: 4 .ips (14:31:28, :35, 14:32:43, :48), all EXC_BAD_ACCESS at 0x8, top frames
  mlir::Value::getParentRegion <- GPURegionRuntime::getTensorDataFromDataMap <- PoolingGradientOpHandler<PoolMaxGradientOp>::encodeNDArrayOp
  macOS 27.0.1 (26A434), Apple M5 Pro. Forward-only test (testTheFP32GraphMatches…) passes; both TRAINING tests crash.
  Default recipe: bf16 activations. Old Mac passed the same tests (unit-polish2.log, 1305/0/2) — old Mac OS build UNKNOWN (asked owner).
1. Diagnosis (believed): an MPSGraph defect on this OS/GPU — encoding the max-pool gradient looks up a tensor that is not in
   the runtime's data map (null mlir::Value) — triggered by the op itself, not by a malformed graph of ours.
2. Refuting observation: a minimal graph (placeholder -> [cast] -> maxPool2x2 -> sum, gradients wrt the placeholder) runs
   clean on this Mac in f32, f16 AND bf16 -> the crash needs something specific to DetectorGraph (skip concat, fusion, cast chain).
3. Prediction (before running): the minimal bf16 graph crashes with the same top frames; f32 — no prediction held with confidence.
## Experiment 1 (minpool.swift): x->[cast]->maxPool->sum, grads wrt x, f32/f16/bf16 — all exit 0. PREDICTION REFUTED (bf16 did not crash).
   Side note: every reduced-precision run prints "Incompatible element type for ANE" (MPSGraph on 27 considers ANE placement).
## Experiment 2 (graphA.swift = trainer's graph A, real bundled weights, compiled from repo DetectorGraph/DetectorWeights):
   bf16 & f16 exit 139 under default, level0, level1; f32 exit 0 (loss 0.08562293). Crash frames identical to the test's .ips.
   => optimisation level (ANE delegation) is NOT the switch. Reproduces outside XCTest.
## Experiment 3 (bisect.swift): minimal trigger = x -> cast(bf16) -> maxPooling2D -> conv2d(w cast bf16) -> cast f32 -> sum sq,
   grads wrt [x,w]: bf16 139, f16 139, f32 0. Pool without a following conv: 0 (r, rn, ra, i, in). SiLU/bias/concat irrelevant.
   Pool done in f32 between casts: still 139 (cast pair presumably folded). maxPooling4D: 139. maxPooling2DReturnIndices[0]: 0 in bf16 & f32.
   Revised diagnosis: MPSGraph (macOS 27.0.1 26A434, M5 Pro) crashes encoding PoolMaxGradientOp when a reduced-precision max-pool
   feeds a convolution; the index-returning pool takes a different gradient path and does not crash.
   Open discriminator: same `bisect bf16 vo` binary on the OLD Mac (chip vs OS) — owner.
## Refuter (Fable, independent, 2026-09-30 evening): HOLDS.
   Harness: DG-copy differs from repo only by the POOL switch; dumps deterministic (md5 over repeated runs); env reaches graph
   (POOL=idy / unset crash, idx runs); repeated run of one graph object stable. (a) lldb under MallocScribble: null operand
   (x1=x9=0) at getParentRegion, not heap corruption. (b) CORRECTION: returnIndicesMode matters — .globalFlatten2D + following conv
   still crashes (bf16, f16); .globalFlatten4D/.localFlatten4D/.localFlatten2D and int64 run. Ship .globalFlatten4D/int32 and name it.
   (c) Tie routing: bf16 plain vs every idx mode byte-identical without a following conv (first tied element, raster order);
   f32 plain vs idx with conv byte-identical. The 0.0067 rel-L2 measures precision, not the pool change; f16 recipe not viable (0.0465).
   Open (old Mac): bisect bf16 vo / graphA2 bf16 default exit there (chip vs OS); dump-bf16-plain vs this Mac's dump-bf16-idx.
## Fix + break (2026-09-30 evening): DetectorGraph.pool -> maxPooling2DReturnIndices(.globalFlatten4D, int32)[0]; spike mirrored.
   Fixed: -only-testing DetectorTrainerTests exit 0, 10/10 passed (fix-test.log, 10 `func test` in the file).
   Mutation (plain maxPooling2D restored): exit 65, exactly testTwoSteps… + testTheFootprint… fail (mut-test.log); restored, cmp OK.

## 2 — testLearnedPathMatchesPythonReference, 8 extra raw picks (2.26 %) — DIAGNOSED, owner decision open

Prior record (LearnedDiskDetectorTests.swift:227-238 + open-items "Learned-detector parity is a same-runtime claim"):
  2026-09-14, refuter-remeasured: forced .cpuAndGPU -> raw picks 346/354 with 8 extras (2.26 %); .cpuOnly 341/354 with 14.
  Named blind spot: "a Neural Engine that is present but not used".
1. Diagnosis: on M5 Pro + macOS 27.0.1, Core ML with computeUnits .all does not run this model on the ANE (runs on GPU),
   so the same-runtime fixture (written on the ANE) is compared against GPU numerics — the recorded .cpuAndGPU signature, to the pick.
   The earlier session's hypothesis ("M5 float16 rounding at the threshold" on the ANE) is the rival.
2. Refuting observation: MLComputePlan under .all places the model's ops on the Neural Engine, and the .all heatmap equals the
   .cpuAndNeuralEngine heatmap and differs from .cpuAndGPU -> then the ANE runs it and the M5 ANE's numerics differ (rival wins).
3. Prediction: the plan prefers GPU for (nearly) all ops under .all; heatmap(.all) == heatmap(.cpuAndGPU) bitwise, != (.cpuAndNeuralEngine).
## Experiment 1 (plan.swift, MLComputePlan, computeUnits .all): 39/39 ops preferred on GPU, 0 on ANE, although ANE is listed.
   heatmap max|all - cpuAndGPU| 0.0032, max|all - cpuAndNE| 0.0237, max|NE - GPU| 0.0242 (random inputs, batch 32).
   Prediction "all == cpuAndGPU bitwise" MISSED: close to GPU, not identical (a different GPU kernel choice under .all?).
## Experiment 2: the real test, temporary env override of computeUnits (patch saved temp-measurement.patch, reverted),
   build-for-testing to scratch DerivedData, 6 runs, counts via XCTContext activity from the .xcresult:
   default  hits 347/354 extra 8  accepted 16/16 pos 295/295 worst 7.6e-5  FAIL (2.26 %)   (x2, identical)
   ane      hits 354/354 extra 1  accepted 16/16 pos 295/295 worst 7.6e-5  PASS            (x2, identical)
   gpu      hits 345/354 extra 8  ... FAIL      cpu hits 342/354 extra 14 ... FAIL
   Matches the 2026-09-14 record (.cpuAndGPU 8 extras, .cpuOnly 14) to the pick.
   CONCLUSION: diagnosis survives its refutation test — on M5 Pro/macOS 27.0.1 Core ML's .all does not use the ANE for this model;
   the ANE, when forced, reproduces the fixture (1 extra). Rival "M5 ANE rounds differently" REFUTED.
   Accepted peaks (the science output) identical in every mode: 16/16, 295/295, worst 7.6e-5 px.
## Refuter (Fable, independent, 2026-09-30 evening): diagnosis HOLDS on an independent signal.
   aned log: ANE_ProgramCreate only in the two "ane" test pids (31370, 31495); default runs (31355, 31443) created none.
   Warm timing b32: cpuAndNE 16.9 ms, all 23.5, cpuAndGPU 26.8, cpuOnly 78.9. CORRECTION: "matches 2026-09-14 to the pick" is
   extras only (8, 14); hits 345 vs 346, 342 vs 341. .all at b32 is a third numerics path (!= cpuAndGPU at 87 % of pixels).
   NEW: under .cpuAndNeuralEngine the ANE serves ONLY batch 32; other batches fall back silently to CPU (bitwise = cpuOnly).
   Mechanism UNPROVEN: fixed-b32 and enumerated-shape exports also go 100 % GPU under .all; hints change nothing -> a Core ML
   scheduling decision on M5 Pro/27.0.1, not a model property. Science claim holds for the 16-pattern fixture only (raw picks
   differ 2-4 % between units); measure accepted peaks on real scans before any app change.
   Preconditions (a) test-only: assert ANE executed (heatmap != cpuOnly), assert batch 32, rename the claim, record what .all gives.
   (b) app: gate batch-32-only ANE in code; scan-level accepted peaks on Thronsen A + one more; throughput on Detect All; open item.
