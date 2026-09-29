# Phase C — the MPSGraph training mirror passes ADR 048's bar (2026-09-30)

`tools/mpsgraph-training-spike` (Swift, MetalPerformanceShadersGraph only, no packages): the learned detector's UNet
with the shipped weights (`weight.bin`, OIHW, no permutation), MPSGraph autodiff through max-pool, concat and nearest
resize, AdamW, micro-batch 2 × 4 accumulated, fp32 master weights. `tools/mpsgraph-training-spike/run.sh <scratch> 50`
(`SPIKE_DTYPE`, `SPIKE_MODE=forward|train`). Predictions written first (session scratchpad, not retained).

**Criterion 1** (batch 32, fp32 graph vs the shipped Core ML heatmap): GPU 0.00272 (MLX mirror 0.0027); CPU 0.01488
(0.0149); Neural Engine 0.03553 (0.0355).

**Criterion 2** (50 steps, lr 1e-4; loss ×1e-3, first → last 10-step means; C2.5's batch-8 control 4.96 → 2.54,
held-out 3.48 → 3.72):

| dtype | loss | held-out | footprint (lifetime max) | MPS allocated | s/step |
|---|---|---|---|---|---|
| f32 | 4.963 → 2.540 | 3.48 → 3.72 | 1510 MB | 1354 MB | 0.126 |
| bf16 | 4.961 → 2.543 | 3.48 → 3.72 | 1068 MB | 887 MB | 0.109 |
| f16 | 5.02 → 2.69 | 3.48 → 3.84 | 1121 MB | 887 MB | 0.107 |

Verdict: **PASS** — the mirror equals MLX on every compute unit, trains identically, fits 2 GB in fp32, and runs ≈ 4×
faster than MLX's 2 × 4 step. Refuted predictions: MPS allocation above the predicted 0.5–1.1 GB in fp32 (bf16 fixes
it); speed 0.126 s/step against 0.4–1.0. Not done: a break test of the comparison itself (agreement with MLX on three
compute units is the check); AdamW mirrors mlx-swift's defaults from memory (the loss match supports it).
Integration: a local package, bf16 activations, data streamed per micro-batch, in-app re-measurement beside a resident
cube with `os_proc_available_memory` admission, the unchanged on-disk `.mlpackage` route.
