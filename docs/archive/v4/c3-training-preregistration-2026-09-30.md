# C3 — on-device fine-tuning of the learned disk detector: pre-registration (draft for phase B3, 2026-09-30)

This registers ROADMAP track C under ADR 043: a fine-tuned model is judged by what it detects on held-out labels. It builds on
`c2-mlx-spike-2026-09-28.md`, `ondevice-training-research-2026-09-28.md` and `a2-label-scoring-2026-09-28.md`. Preparation was
read-only; nothing was built or run. **Gate D** covers criterion 4 and the C4 scorer, because they produce the numbers a user
acts on. The C2.5 grid is tooling.

**Runtime, as C2 left it.** Swift with mlx-swift 0.31.6 (MIT, pinned), built by xcodebuild. The weights reach Core ML as fp16
blobs written at the shipped `weight.bin` offsets (OHWI → OIHW). **C4 uses the on-disk route only**: a patched copy of the
`.mlpackage`, compiled, which runs at 1.00× the shipped speed. The in-memory `blobMapping` route (3.2× slower) is dropped. That
retires owed item 4 (P6, the 0.0034 gap between the two compile paths), since no heatmap bar remains for it to bind.

**Found while reading.** `main.swift` never calls `Memory.resetPeakMemory()`, and criterion 1 ran an MLX batch-32 forward
pass before training. The recorded 2 776 MB "MLX peak" is therefore the larger of that pass and training, so C2's claim that
training alone exceeds 2 GB is **not established**. What run 3 does show is the lifetime-maximum footprint rising from
1 562 to 3 339 MB during training: **+1.78 GB**, cache (256 MB) included (`852efe2a…/scratchpad/c2/spike-run3.log`).

## 1. C2.5 — a training step under 2 GB (tools only)

**Probe addition, break test first.** A new `SPIKE_MODE=memory`, set by `SPIKE_BATCH`, `SPIKE_CROP` (random crops of the 256
frame), `SPIKE_DTYPE` (f32|f16) and `SPIKE_ACCUM` (gradient accumulation). It loads training data only: no Core ML model and
no MLX forward pass before the loop. Each grid point is its own process, because a lifetime maximum only rises. It resets the
peak just before step 1, then runs 100 steps at lr 1e-5, seed 20260928, cache 256 MB. It logs the baseline, the lifetime-max
increase I, MLX's active peak and s/step. The break test: moving the reset after the loop must change the logged peak.
**Command** (serial, one heavy job, at least 4 GB free):
`SPIKE_MODE=memory SPIKE_BATCH=$B SPIKE_CROP=$C SPIKE_DTYPE=$D SPIKE_ACCUM=$A SPIKE_CACHE_MB=256 tools/mlx-training-spike/run.sh $S/c25 100 > $S/c25-$B-$C-$D-$A.log 2>&1`
then `echo $?` on its own line, then `grep 'memory:'` in that log.
**Predictions (fixed now).** I ≈ 0.26 GB + 190 MB × B × (C/256)², halved for f16. The 190 MB per sample comes from run 3; it
is about twice the research's 100 MB activation estimate, which suggests convolution workspace.

| # | batch · crop · dtype · accum | predicted I | purpose |
|---|---|---|---|
| G0 | 8 · 256 · f32 · 1 | 1.5–2.1 GB | **replication**: outside this band the instrument is off, and nothing else is read |
| G1 | 4 · 256 · f32 · 2 | 0.8–1.3 GB | effective batch 8; same frame, same precision |
| G2 | 2 · 256 · f32 · 4 | 0.45–0.85 GB | the floor if G1 fails |
| G3 | 8 · 128 · f32 · 1 | 0.45–0.85 GB | the loss sees crop edges the app never runs on |
| G4 | 8 · 256 · f16 · 1 | 0.8–1.3 GB | gradients may underflow at loss ≈ 3e-3 (the held-out loss will show it) |
| G5 | G1, cache 0 | G1 − ≤ 0.26 GB | separates the cache from the step |

There is no checkpointing option: `checkpoint` is absent from mlx-swift 0.31.6's Swift sources (grepped at that tag), and a
hand-written recompute would be new code, not a setting. **Refuted if** G1's I > 1.5 GB: memory then does not scale with
batch, so look for fixed allocations. **Bar:** I ≤ 2 048 MB, and held-out loss at step 100 ≤ step 1. **Recommendation:
G1**, which keeps the 256 frame, fp32 and the effective batch.
**D2's cost, from the same run:** `du -sk` of the Release binary and `mlx-swift_Cmlx.bundle`; Cmlx's clean-build time; and
the patched package's compile plus first `.all` load (the bundled package takes ≈ 1.3 s). Predicted metallib: 60–110 MB.
The one comparable file on this Mac, GESS.framework's `mlx.metallib`, is 102 072 920 B; the 4.0 `mac4DSTEM.app` is 11 MB.

## 2. Criterion 4: "through the app's Swift path"

The weights come from the chosen grid point after 500 steps at a fixed seed and are written into an on-disk copy of the
shipped package. The **unchanged** `LearnedDiskDetector.load(assetURL:)` loads it on `.all` (batch 32, zero-padded). It runs
`heatmaps` → `pickPeaks` → `DiskDetector.refine` → accept on the 16-pattern Swift fixture.
**(a) Same runtime as Python.** `write_swift_fixture.py --coreml <patched>` writes `fixture/swift-finetuned/`, committed
with its 551 kB weight.bin. A test class parameterised on that directory holds the four existing bars of
`testLearnedPathMatchesPythonReference`. It needs a Neural Engine.
**(b) Recall and precision.** A Swift port of `evaluate.match` in `Core/ML`: greedy nearest pairing within 2 px, each
prediction used once. Its matched, truth and predicted counts against `expected.json`'s truth must equal Python's exactly.
**(c) MLX vs ANE at detection level (ADR 043),** measured in the spike. The MLX heatmap of the same weights goes through the
same Swift picking. Its |Δrecall| and |Δprecision| against the ANE must each be ≤ the shipped weights' own |Δ| (measured
first) + 1/N_truth.
**Break tests:** OHWI written unpermuted must turn (a) red; a 3 px radius must turn (b) red. **Refuted if** (a) fails only
on raw picks while the shipped package passes. That is ANE rounding near 0.7, not the port, and is reported with its counts.

## 3. C4 in Bragg Disks (a room, not the frozen shell): about 2 inspector rows (≈ 44 pt) and one sheet

1. **Labels:** the existing Training labels section (click centres, Save to Sidecar).
2. **Split row**, e.g. "Train 28 · Held out 12": by position, never by centre; held out when SHA-256("ry,rx") → [0,1) < 0.30.
   New labels never move a position. "Train Model…" is disabled, with its reason, until ≥ k_min positions are held out (§4).
3. **Train.** Admission refuses when `os_proc_available_memory()` is below C2.5's measured I. The run uses
   `beginCancellableOperation`, so the status strip shows "Step 120/400 · 0.4 s/step" with Cancel. A memory-pressure
   warning cancels and calls `Memory.clearCache()`. Training always starts from the bundled weights, with the fixed recipe
   (D5); targets come from a port of `simulate.heatmap_target` (σ 1.5).
4. **Evaluate.** The candidate is written to the store, compiled, and loaded on `.all`. The active model and the candidate
   each run `detect` at the held-out positions with the user's current parameters and threshold, scored by §2(b) at 2 px.
5. **Sheet.** Columns Active and Fine-tuned; rows recall, precision, and held-out N positions / M centres, with radius,
   threshold and "Neural Engine". **Use Fine-Tuned Model** appears only if the candidate passes D7; otherwise the sheet
   names the number that fell. **Keep Current Model** is always there and is the default. It never says "validated".
6. **Store.** `Application Support/mac4DSTEM/DiskDetectorModels/<sha8>/` holds the `.mlpackage`, `.mlmodelc` and
   `record.json`. The record lists the parent and labels sha, dataset, held-out list, recipe, MLX version, both models'
   numbers and the date. Nothing is deleted automatically; Remove moves a model to the Trash.
7. **Provenance and revert.** `learned_model_sha256` already tells models apart. Two optional keys join it:
   `learned_model_origin` and `learned_model_parent_sha256`, and old sidecars still read. `replayRefusal` searches the
   store before refusing ("model a1b2… is not on this Mac"). To revert, pick "Bundled" in the Model row, now a picker.
   The active model is app-wide, owned by `LearnedDetectionSession`. **Blocked** by "Drive before more surface" until phase A
   clears; the owner accepts a mock of steps 2–5 before any UI code.

## 4. The minimum number of held-out labels (measured)

**Data:** A2's bullseye labels, 40 positions and 370 centres. **Models:** the bundled package; C2 run 1 (lr 1e-4, whose
held-out loss rose) and run 2b (lr 1e-5), both patched on disk; and classical at the app's settings. Each is scored per
position by §2(b) on the ANE.
**Method:** for k ∈ {4, 6, 8, 10, 12, 16, 20, 30}, draw 10 000 subsets of k positions (seed 20260930). For each pair of
models, P(k) is how often the subset's verdict matches the verdict on all 40. **k_min** is the smallest k with P ≥ 0.90 for
every pair whose full-set gap is ≥ δ = 0.03; closer pairs are reported as indistinguishable.
**Prediction:** k_min = 12–25. **Refuted if** < 6; if > 30, report "≥ 30". It belongs to this dataset and labeller: a floor; N always shown.

## 5. Owner decisions (B3), each with a recommendation

- **D1 Where training lives:** a separate local package `DSTEMTraining`, linked only by the app and run in process, so `core`
  (`swift build`) never sees MLX. The alternative is an XPC service, which isolates jetsam kills on the 8 GB Mac.
- **D2 MLX or MPSGraph:** MPSGraph adds no bytes, has autodiff, and the graph is 39 ops. If MLX adds more than 11 MB (the
  app's own size), run a one-day MPSGraph mirror of C2's criteria 1–2 first.
- **D3 Split:** 30 % held out by position hash, k_min as a floor. **D4 Parent:** always the bundled weights; judged vs the active.
- **D5 Recipe:** fixed steps, lr 1e-5, the C2.5 batch, flips/rot90 on training positions only. Set the step count from an
  inner split of the training positions, with no early stopping.
- **D6 Scope:** one active model app-wide; each run records its model. **D8 Badge:** "judged on N held-out positions of <dataset>".
- **D7 Ties:** offer only if ≥ on both and > on one. ADR 043's "at least" would offer an equal model.
- **D9 ADR 014 revisit** (this change is its named trigger): Core ML for every model. The comparison needs one runtime, and
  Core AI has no on-device writer. Record it as an amendment to ADR 014.

## 6. Risks

- **mlx-swift is pre-1.0**, so pin it exactly. Its vendored code: fmt and json (MIT), metal-cpp and swift-numerics
  (Apache-2.0); the mlx and mlx-c submodules (MIT) are unaudited. NOTICE and its hashes must be updated.
- **Size and notarisation:** ≈ 100 MB metallib likely; the nested bundle is signed (`codesign --verify --deep --strict`); owner notarises.
- **Neural Engine:** compiling takes seconds (cache the `.mlmodelc`); a candidate can pass on the GPU and fail on the ANE.
- **Label bias:** a model can learn the labeller's 1.2 px scatter (A2); the inter-labeller check is owed before C5. Held-out
  positions neighbour training positions, so the result holds within this dataset only.
- **Memory:** training runs beside a resident cube on 8 GB (the 2026-09-24 panic). Admission and the pressure cancel guard
  it; D1's XPC route is the fallback.
