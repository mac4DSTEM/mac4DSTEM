# C2.5 — a training step under 2 GB (2026-09-30, clearing the board phase C)

Question: can the learned detector's MLX training step (C2: 2.78 GB MLX peak at batch 8, over the 2 GB bar) run under
2 GB on this 8 GB Mac without changing what it learns? Predictions were written before any run (session scratchpad
`c25/prediction.md`, not retained). Every run: 50 steps at lr 1e-4 on the C2 spike's training data, peak memory reset
before the loop, one process at a time. `SPIKE_BATCH=… SPIKE_ACCUM=… SPIKE_DTYPE=… tools/mlx-training-spike/membench.sh
<scratch> 50`. Loss columns are the mean train loss over the first / last 10 steps (×1e-3).

| option | predicted MLX peak (GB) | MLX peak (GB) | process footprint (GB) | s/step | loss first→last 10 | held-out before→after |
|---|---|---|---|---|---|---|
| b8 fp32 (control) | 2.7 | 2.69 | 3.60 | 0.515 | 4.96→2.54 | 3.48→3.72 |
| b4 fp32 | 1.45 | 1.62 | 2.44 | 0.233 | 6.05→3.17 | 3.48→4.11 |
| b2 fp32 | 0.8 | 0.96 | 1.69 | 0.116 | 5.65→3.89 | 3.48→5.46 |
| b8 bf16 | 1.5 | 1.43 | 2.39 | 0.373 | 4.96→2.54 | 3.48→3.72 |
| b8 fp16 | 1.5 | 1.43 | 2.39 | 0.365 | 5.10→3.12 | 3.48→4.19 |
| b8, 128-px crops | 0.8 | 0.97 | 1.69 | 0.116 | 11.7→10.0 | not comparable |
| b2 × 4 accumulated, fp32 | 0.8 | 1.29 | 1.82 | 0.492 | 4.96→2.54 | 3.48→3.72 |
| **b2 × 4 accumulated, bf16** | — | **0.69** | **1.48** | 0.407 | 4.96→2.54 | 3.48→3.72 |
| b4 × 2 accumulated, bf16 | — | 1.00 | 1.95 | 0.398 | 4.96→2.54 | 3.48→3.72 |

- **Chosen: micro-batch 2, 4-step accumulation, bf16 activations from fp32 master weights** — 1.48 GB footprint (the
  bar C2 used), faster than the control, and its losses equal batch 8's to the logged precision (same gradients).
- The footprint runs ≈ 0.8 GB above MLX's own peak here (data-load transients, Metal libraries): the app must stream
  its data and re-measure inside the app.
- Held-out loss rises slightly at lr 1e-4 even for the control (as in C2 run 1): 50 steps judge training loss only.
- Gradient checkpointing is not available: mlx-swift 0.31.6 exposes only the C `mlx_checkpoint`.
- The training pre-registration (C3) also found that C2's 2.78 GB included a batch-32 forward pass before training
  (the peak counter was never reset); training alone rose 1.78 GB. This run's reset removes that confound.
