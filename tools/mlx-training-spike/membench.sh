#!/bin/zsh
# tools/mlx-training-spike — ROADMAP C2.5 (2026-09-29): the memory of ONE training step, per option. A DIAGNOSTIC.
#   membench.sh <scratch dir> [steps=50]     env: SPIKE_BATCH (8) SPIKE_ACCUM (1) SPIKE_DTYPE (f32|bf16|f16)
#                                            SPIKE_CROP (0 = 256 px) SPIKE_CACHE_MB SPIKE_LR (1e-4)
# Exports the inputs and builds on the first call (as run.sh), reuses them after. Prints one `MEMBENCH {json}` line:
# MLX peak (reset before the loop), lifetime-max phys_footprint, s/step, first/last-10-step mean loss, held-out loss
# before/after. One job at a time on the 8 GB Mac.
cd "$(dirname "$0")" && SPIKE_MODE=membench SPIKE_REUSE=1 exec ./run.sh "${1:?usage: membench.sh <scratch dir> [steps]}" "${2:-50}"
