Research by a general-purpose agent on 2026-09-28, filed verbatim. Sources are cited inline, and claims it could not confirm are listed in its own section. Adopted as the input to ROADMAP track C2 (not yet measured).

# On-device training for the learned disk detector (2026-09-28)

Research only; no repository file was edited. "doc:" means Apple documentation JSON under developer.apple.com/tutorials/data/documentation/, read today.

**The shipped net.** `train.py` is a 4-level U-Net (conv3×3/BN/SiLU ×2 per block, max-pool, nearest upsample, concat skips, sigmoid head). Loss is weighted MSE `(1+20t)(p−t)²` with AdamW. The shipped ML Program contains 15 conv, 14 silu, 3 max_pool, 3 upsample_nearest_neighbor, 3 concat, 1 sigmoid, and **no batch_norm** (BN is folded). Weights are one `weight.bin` of 551 064 B.

## Comparison

| Option | Trains this U-Net? | Training compute | ANE inference path | Maturity | Licence | Sources |
|---|---|---|---|---|---|---|
| **MLX Swift** 0.31.6 | Yes: Conv2d (NHWC), BatchNorm, MaxPool2d, Upsample, SiLU, `valueAndGrad`, AdamW | GPU (Metal), CPU | None native; inject weights into Core ML (Q3) | Active; MNISTTrainer example; WWDC26 guide names MLX for training | MIT | github.com/ml-explore/mlx-swift, …/mlx-swift-examples, developer.apple.com/wwdc26/guides/machine-learning/ |
| **MPSGraph** | Yes, hand-built: `gradients(of:with:name:)`, conv gradient ops, `adam(…)` | GPU (`.level1` "placement pass" may use ANE; no control) | Same injection | macOS 11+; PyTorch MPS (our trainer) runs on it | OS framework | doc: metalperformanceshadersgraph, mpsgraphoptimization/level1; docs.pytorch.org/docs/2.14/notes/mps.html |
| **Core ML updatable** | **No.** Only conv/innerProduct updatable; legacy NeuralNetwork format, fp32 only; plain MSE/CCE only; **no backprop through concat** (secondary) | Undocumented (2019 test: CPU) | Direct | Not deprecated; unchanged since 2019 | OS | coremltools `NeuralNetwork.proto`, `builder.py`; doc: mlupdatetask; machinethink.net/blog/coreml-training-part1/, part4/ |
| **Create ML** | No: fixed tasks (MLObjectDetector = boxes); no heatmap task | — | Emits Core ML | Mature | OS | doc: createml |
| **Core AI** (27, beta) | **No, inference only.** No weight-update API; `.aimodel` authored only in Python (`coreai-torch`) | — | `.aimodel`, built off-device | Beta | OS | doc: coreai, coreai/aimodelasset; WWDC26 sessions 324, 325 |
| **BNNS** | Training API **deprecated in macOS 15**; BNNSGraph is inference | CPU | — | Deprecated | OS | doc: accelerate/bnnsoptimizerstep |

## Q1: Which options can train it

Only **MLX Swift** and **MPSGraph** can train this net in a Swift app.
- **MLX Swift** gives a PyTorch-like layer and optimizer stack.
- **MPSGraph** needs no dependency, but every gradient is wired by hand.
- **MLX caveat:** its README says command-line SwiftPM "cannot build the Metal shaders". `run-tests.sh core` uses `swift build`, so MLX must stay out of DSTEMCore, or `core` must change.

## Q2: ANE for training

**No documented public route.** Your assumption holds.
- Core AI describes `ComputeUnitKind` as a compute unit "for model inference".
- MLX closed its ANE-support issue as wontfix; the maintainer's reason is that the ANE API is closed source (github.com/ml-explore/mlx/issues/18).
- ANEForge (arXiv 2606.17090, June 2026) trains on the ANE only through Apple's private daemon and driver stack.
- MPSGraph's `.level1` placement is undocumented for gradient ops; treat it as no.

## Q3: From in-app training to ANE inference

There is no on-device converter: coremltools and coreai-torch are Python, and there is no Swift `.aimodel` writer. One documented Core ML door exists:

- **The door.** `MLModelAsset(specification:blobMapping:)` (macOS 15+) builds a model from an ML Program spec with "in-memory blobs" replacing blob-file references. Per the doc, the blob format "must be the same as the external files".
- **The blob format** is public only as source: coremltools `MILBlob/Blob/StorageFormat.hpp` (BSD-3). A 64-B header is followed by 64-B-aligned per-blob metadata (sentinel `0xDEADBEEF`, dtype, size, offset).

The path:
1. Keep the shipped spec as the architecture.
2. Mirror its BN-free graph in MLX (conv+bias only, 1:1 with the blobs).
3. Initialise from `weight.bin`.
4. Fine-tune on the user's labels.
5. Write fp16 blobs at the same offsets, transposing MLX OHWI to MIL OIHW.
6. Load with `.all`.
7. Check ANE placement with `MLComputePlan` (macOS 14.4+): `deviceUsage(for:)` gives `preferredComputeDevice` per op.

Fallback: write a patched `.mlpackage` and compile it with async `MLModel.compileModel(at:)`.

`MLParameterKey.weights` is no alternative: per the doc it overrides only "updatable layers", which means the legacy format.

## Q4: Feasibility on 8 GB M3

**Parameters.** Parameters plus AdamW state are about 4.4 MB.

**Activations (my estimate, not measured).**
- About 25 M floats per 256² sample, roughly 100 MB fp32.
- With backward, about 2× that: roughly 1.6 GB at batch 8 and 6 GB at batch 32 (fp32); fp16 halves both.

**Measured on this Mac** (PyTorch-MPS, batch 32, width 12, standalone; `References/training_runs/disk-detector-2026-09-08/02-train.log`):
- Val recall 0.775 at step 1000, after 14.6 min.
- The 90-min cap hit at step 6500: about 0.83 s/step, or 38 samples/s including the simulator.
- Footprint was not recorded.

**Plan for the app:** batch 8 fine-tuning, not from-scratch training. I found no published MLX timings for a comparable net.

Side note: `disk-detector-heatmap-256.json` records `"steps": 20000`. That is the argument; the log shows the run stopped at 6500.

## Q5: Licences vs GPL-3.0

- **MLX Swift (MIT):** GPL-compatible. Its notice must be kept in `NOTICE`. Its transitive C/C++ submodules are **not audited**.
- **OS frameworks:** covered by GPL-3.0's System Libraries clause.
- **coremltools (BSD-3):** matters only if format code is ported.

## Could not confirm

- ANE placement and caching for models built with `blobMapping`.
- `MLUpdateTask`'s compute unit.
- Apple's own list of layers that can backprop (the concat limit comes from a 2019 blog).
- Whether MPSGraph ever places gradient ops on the ANE.
- MLX memory on this net.
- Whether the Evaluations framework (named on the Core AI page) fits detector scoring.

## Recommended ≤1-day spike (CLI or test target, no app surface)

**Hypothesis:** an MLX-Swift mirror of the shipped BN-free graph, initialised from `weight.bin` and fine-tuned on this M3, can be written back through `MLModelAsset(specification:blobMapping:)`. Core ML then runs the convs on the Neural Engine with a heatmap matching MLX.

**Build:**
- A blob reader and writer.
- The MLX mirror.
- A weighted-MSE fine-tune on the 16-pattern fixture plus a fixed simulated set exported once from `simulate.py`. The 306 hand labels are not on disk.
- Core ML load with `.all`, then `MLComputePlan`.

**Pass criteria (all four):**
1. Before training, MLX-forward vs the shipped Core ML heatmap: max |Δ| ≤ 1e-2 on the fixture.
2. Loss falls over 500 steps at batch 8, with `phys_footprint` ≤ 2 GB and s/step logged.
3. The injected model matches MLX to ≤ 1e-2; `MLComputePlan` reports `neuralEngine` preferred for all 15 convs; latency is within 20 % of the shipped package.
4. Swift fixture recall and precision (2 px) equal `evaluate.py` on the same weights.

**If it fails:**
- **Criterion 3:** the ANE half is dead. Try the patched-package fallback, or accept GPU inference.
- **Criterion 1:** the mirror is wrong. Fix it before any training.
