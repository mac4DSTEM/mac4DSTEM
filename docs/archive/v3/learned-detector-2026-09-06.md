# Learned disk detector — the 2026-09-06 planning record (archived 2026-09-07, C1)

Verbatim: `docs/v3-plan.md` §3a as it stood from 2026-09-06 until the
consolidation plan's C1 replaced it with a short pre-registration
(`docs/consolidation-plan.md` §6). The decision transcript, the Core AI
notes, the loop design, the precipitate-chain exploration and the working
method are all here, unchanged; the owner's "forget no info" holds in the
archive. **History, not guidance** — the live registration is `v3-plan.md`
§3a, the runtime decision is Core ML (`decisions.md`, 2026-09-07), the
review of the branch is `consolidation-plan.md` §3, and one sentence below is
known false as of 2026-09-07: the stock `yolov8n.mlpackage` WAS committed
(C0 (3)); it leaves the tree in C2.

---

### 3a. Learned disk candidates — pre-registration (2026-09-05, revised 2026-09-06)

The complete record of the 2026-09-06 planning session, at the owner's
instruction ("we shouldn't forget any info, no matter the length"): the
cold-start set grows by it, knowingly. Nothing here is implemented. Every
number not marked *measured* is a design default to be settled by its step.

#### The decision, and why

Neural-Engine-native, trained by us, no py4DSTEM model, no py4DSTEM
fallback. The Neural Engine (ANE, in every Apple Silicon Mac) is reached
only through Apple's model runtimes — Core ML (macOS 14+) and, new in the
27.0 OS generation, Core AI (beta on 2026-09-06; its own block below); MLX
runs on the GPU and never touches the ANE. Core ML has no FFT operation and
neither runtime puts one on the ANE. py4DSTEM's own learned detector, FCU-Net
(Fourier Convolutional U-Net, Munshi et al. 2022; `crystal4D`, TF/Keras;
`braggvectors/diskdetection_aiml.py` in the pinned source), is built on a
Fourier layer — FFT, multiply, inverse FFT — so it can never compile for the
ANE; a custom Core ML layer would carry it on CPU or GPU and the ANE argument
evaporates. Once the goal is stated as "the macOS way, on the Neural Engine,
even at the price of new training and no py4DSTEM fallback" (owner,
2026-09-06), the model must be designed for Core ML from the first line and
FCU-Net is out.

Alternatives weighed the same day and not taken: (1) MLX Swift inside the
app running FCU-Net — native FFT, one architecture shared with Python, but
GPU-only, a second GPU tenant beside our Metal engine, never the ANE;
(2) Core ML with FCU-Net — impossible on the ANE, above; (3) FCU-Net via MLX
first and an ANE-native net later only if throughput demanded it —
superseded by going straight to ANE-native. Create ML is not applicable: it
has no custom heatmap-regression task. What FCU-Net still teaches and we
keep: the probe as a second input, and the shape "net paints a probability
map, classical peak-finding does the rest" (`get_maxima_2D` in the pinned
source). Running FCU-Net as a Python yardstick is optional and no step
requires it (it needs `crystal4D` + TensorFlow; `_get_latest_model()`
downloads a zip from Google Drive by `model_metadata.json`).

The accepted cost, stated once so nobody rediscovers it: **no py4DSTEM
parity for this feature.** Every other number in the app is checked against
py4DSTEM; this one rests on simulated truth and on a net-vs-classical
disagreement check on real cubes. That is a policy decision for the repo
(`decisions.md`, 2026-09-06) more than a technical one.

#### In plain terms

Today the app finds Bragg disks by sliding the probe image over each
diffraction pattern and looking for where it matches best. That works, and
it is fooled when the probe has rings (the bullseye case), when disks
overlap, or when they sit on a bright background. The learned detector is a
small neural network that looks at a pattern and paints a "here is a disk"
map, on the Neural Engine, the chip Apple puts in every Mac for exactly this
kind of work. The network only proposes where disks are; the existing
classical code still measures each one precisely, because the network is
not accurate enough for strain on its own.

**Pros.** It uses hardware the app leaves idle: the GPU is busy with
correlation and drawing, the ANE sits unused. Low power, quiet fans — on a
laptop that matters. It can learn what correlation cannot express:
correlation asks "does this spot look like the probe"; the net can learn
"this spot looks like the probe but it is a ring artifact, skip it", which
is the bullseye failure in one sentence. Our own weights, our own licence:
no py4DSTEM model, no Google Drive download, no licence question; the weights
ship in the app, pinned and hashed. The most durable Apple contract: Core ML
has been stable since 2017 and every new chip runs the same model file
faster — that is the future-proof part — and Core AI, Apple's new
Apple-silicon inference runtime (2026), reads the same PyTorch source, so
the training investment carries over. Fine-tuning stays cheap because we
trained it: retraining on the owner's own probe or camera is the same script
with more data.

**Cons.** No py4DSTEM parity (above). The simulation-to-reality gap: a net
trained on synthetic patterns can be confident and wrong on a camera it has
never seen — a real risk, not a formality. We build the training pipeline
ourselves: simulator, labels, training loop, export, each with its own
tests, all outside the app. Limited toolbox: the ANE runs plain convolutions
and simple math only — no FFT, no complex numbers, no clever layers — and
anything outside that set silently falls back to the GPU and loses the
benefit. Fixed input size: every cube is binned or padded to it; fine for
most data, awkward for unusual detectors. The speed win is not guaranteed:
our Metal correlation is already fast and whether the net is faster on wall
clock is an unmade measurement. Retraining is the fix for every failure:
when the classical detector is wrong we change a threshold; when the network
is wrong we need more data and a training run. And the learned detector
needs macOS 27 (Core AI): users below it keep the classical detector.

#### Shape of the detector

- **A candidate stage, never a measurement.** A second `DetectorClass`
  beside the classical one: the net paints a disk-centre heatmap,
  peak-picking on it gives CANDIDATES, the existing correlation/centroid
  refinement measures each to sub-pixel. No coordinate from the net reaches
  strain or Q calibration: strain needs 0.01 px, a heatmap peak is ~0.5 px.
- **Recall over precision.** A bad proposal is pruned by refinement for free
  (it refines to a poor correlation and is dropped); a missed disk is the
  expensive error. The net is trained to over-propose.
- **Architecture** inside the ANE's set: a small plain-convolution U-Net —
  convolutions, pooling, ReLU/SiLU, skip connections by concatenation —
  float16 weights and activations, fixed input shape, no FFT, no complex
  numbers, no custom layers, no dynamic shapes. Anything outside splits the
  graph onto GPU/CPU with copies between the pieces. Design default: four
  levels, 16–128 channels, order 1–2 M parameters, a few MB at fp16.
- **Inputs: three channels at one fixed size** (design default 128×128
  after the load spec's binning; larger patterns are binned or cropped
  around the measured origin, smaller ones padded; Core ML's *enumerated*
  shapes stay ANE-friendly if a second size is ever needed, *range* shapes
  do not):
  1. the pattern, log-scaled and normalised per pattern — dose-invariant,
     and it keeps raw counts inside float16's range;
  2. the probe (the measured kernel, centred, same size) — FCU-Net's trick
     for generalising across probe shapes, the bullseye failure class;
  3. the Metal cross-correlation the classical detector would use at its
     current settings — **decided in (owner, 2026-09-06).** Why: the net
     then sees the classical detector's evidence and learns which
     correlation maxima are ring artifacts, targeting the bullseye failure
     directly instead of rediscovering correlation. The price, accepted:
     the net is no longer an opinion independent of the classical path. The
     disagreement map (below) stays meaningful because the net can still
     add and reject candidates; it just cannot be sold as a blind second
     reading.
- **Output.** One heatmap with a Gaussian bump (σ ≈ 1–2 px, design default)
  at each disk centre — not a segmentation mask. Peak-picking: local maxima
  above a threshold with a minimum separation of about the probe radius.
  Loss: heatmap regression (MSE or a focal variant); settled in step 2.
- **Serving, Core ML route — insurance in the tooling, not in the app
  (decided 2026-09-06 late).** `coremltools` → `.mlpackage` from the same
  PyTorch net, with its own pixel check, kept so that if Core AI misses the
  ceiling or churns at step 3 the fallback is one Swift class, not a
  rewrite. No Core ML code ships in the app.
- **Serving, Core AI (decided 2026-09-06 late; the learned detector is a
  macOS 27-only option behind an availability check, the classical detector
  serves everyone else).** `coreai-torch` → `.aimodel` from the PyTorch
  net; in Swift `AIModel(contentsOf:)` (asynchronous — it specialises the
  model for the device on first load; `AIModelCache` keeps the result; the
  app shows "preparing the detector" once and never specialises inside a
  run; `coreai-build` ahead-of-time compiles per Mac architecture if the
  measured first-load time warrants it), `loadFunction`,
  `InferenceFunction.run(inputs:)` on `NDArray` with contiguous mutable
  views (zero-copy), `SpecializationOptions(preferredComputeUnitKind:
  .neuralEngine)` with `allowedComputeUnitKinds`. Every op's placement is
  read in Xcode's graph view or Instruments. Batching is not documented on
  the pages read; it is designed in as a model dimension and measured. The
  loop design is in the Core AI block.
- **Weights.** Ship in the bundle, pinned; never fetched at build or run
  time (py4DSTEM's loader fetches "latest" — we do the opposite). SHA-256 of
  the model file in provenance beside `detector_class`; a result must say
  which weights made it, and every retrain is a new hash. In the tree if
  the package stays under ~20 MB (a small U-Net will), else a release asset
  with the hash committed.

#### Owner of state

- `DetectorClass` beside `ProbeKernel`, owned by the detection settings —
  never new `AppState` stored state. The classical detector stays the
  default; the learned one is an option; making it the default is a later
  owner decision.
- The **disagreement map** is a product like any other per-position map:
  computed in `Core/`, drawn by a view, owned by the product store.
- The **confirmed/rejected patterns** are new stored state, so their owner
  is named now — **decided (owner, 2026-09-06): the session sidecar**, the
  repo's sharing unit,
  holding per entry the file, scan position, detector settings and weights
  hash, the confirmed disk list and the verdict. A fine-tuning export writes
  them to a local, gitignored folder under `tools/disk-detector/` (they are
  the owner's data).

#### Home in the repo

`tools/disk-detector/` — trainer, simulator, export, export check, fixture;
Python, never ships. Why no existing home would do: `tools/bragg-spacing-probe/`
is detection *diagnostics* on real data; `tools/training-dataset-campaign/`
is the real-data parity campaign (its "training dataset" is the owner's
collection of real cubes in the gitignored `References/training_dataset/`,
nothing to do with ML training). A thing that produces a shipped artifact
is a third kind. Same repo, not a spin-off: the fixture, the weights hash
and the simulator must match the app build that consumes them; a separate
repository earns its keep only if the trainer becomes a product on its own,
which it is not. The app gets one `.mlpackage` and one inference class in
`Core/`.

Contents: `simulate.py` (patterns + truth), `train.py` (PyTorch, MPS
backend), `export.py` (→ `.aimodel` via `coreai-torch`; → `.mlpackage` via
`coremltools` as insurance; both from the one PyTorch net),
`check_export.py` (each export vs PyTorch, pixel for pixel),
`fixture/` (a small, fully synthetic committed set with expected centres — a
reader must be able to reproduce it; runs on the owner's real cubes are
quoted from dated retained logs), `README.md` with pinned versions.
`run-tests.sh inventory` must classify the directory: the fixture runner
gated (`scientific`), the trainer diagnostic (machine-local data, GPU time).
`tools/lib/python.sh` resolves the pinned py4DSTEM environment; PyTorch and
`coremltools` are pinned in the detector's own requirements so the parity
environment stays as pinned (proposed). Mind the disk floor: run
`tools/free-space.sh` before installing PyTorch.

#### Training data

The Neural Engine is not trained on; it only runs models. Training is
PyTorch on the Mac's GPU (the MPS backend) — decided 2026-09-06, below; the result is
exported to Core AI through `coreai-torch` (decided; the `coremltools`
export stays in the tooling as insurance — Core AI block). The data is ours, generated
on the fly by our own simulator — nothing stored, nothing downloaded,
nothing to license:

- measured probes from real files in `References/training_dataset/`
  (`calibrationData_bullseyeProbe.h5`, `polycrystal_2D_WS2.h5` first), with
  randomised variants;
- random two-dimensional reciprocal lattices at realistic spacings,
  sometimes two overlapping grains;
- random per-disk intensities; real vacuum/amorphous backgrounds from real
  cubes with synthetic disks placed on top;
- Poisson noise at a range of real doses, readout noise, gain variation,
  hot pixels;
- randomised everything we do not control: disk size, ring strength, tilt,
  overlap, intensity spread, dose, background level, detector offset.

| Set | Size | Source |
|---|---|---|
| Training | 50–200 k patterns per run | simulated on the fly |
| Validation | a few thousand | held-out simulation + real cubes with classical labels |
| Fine-tuning | a few hundred | real patterns the owner confirmed in the app |

Minutes to a couple of hours on an M-series GPU for a net this size. A
handful of abTEM multislice patterns serve as an honesty check on the cheap
simulator, never as training data (abTEM is GPL-3.0, a tool only). Real
cubes labelled by the classical detector are validation only, never
training truth — otherwise the net learns the classical detector's
mistakes.

#### The simulation-to-reality gap — the risk that decides the feature

Four layers, cheapest first: (1) real ingredients in the simulator (the
measured probe, real backgrounds, real noise levels); (2) randomise what we
do not control; (3) recall over precision, so a wrong proposal costs
nothing; (4) make the owner's eyeballing systematic. The owner sits in front
of the app and can judge a fitted pattern by eye, but not 65 thousand of
them. So the app computes, per scan position, where the net and the
classical detector disagree — a different disk count, or a matched disk
whose position differs beyond a tolerance (the count is the main signal;
refinement makes positions agree) — and draws that as a map over the scan.
The owner clicks the hot spots instead of clicking at random. Each click
that says "this one is right" or "this one is wrong" is stored as a labelled
pattern (owner of state, above); that is how step 5's fine-tuning set is
built, from the owner's judgement on the owner's data.

#### Throughput

A 256×256 scan is 65 536 patterns. The detector states a per-pattern time
from a measurement, never a claim. **The ceiling, decided (owner,
2026-09-06): no slower than the classical detector by more than 2× on the
same cube**, measured at step 3 on the same tree, same settings. The
honest argument for the ANE is power and leaving the GPU free for
correlation and drawing; the wall-clock win is unproven.

#### Open and decided, in plain terms

- **Correlation as the third input channel — decided in (owner).** We can
  show the net only the picture and the probe and let it form its own
  opinion, or we can also show it the classical detector's "match score"
  picture. Showing it the score picture makes the ring problem easy to
  learn and costs one extra array the Metal engine already computes. What
  we give up is a second opinion formed without looking at the first one.
  The owner took the easier ring problem.
- **Getting the trained net into Core ML — decided (owner, 2026-09-06):
  train in PyTorch, not MLX.** The network is a recipe (the layers) plus a
  bag of learned numbers (the weights). The Neural Engine only reads recipes
  written by Apple's translator, `coremltools`, which understands PyTorch
  and TensorFlow, not MLX. Three ways were weighed: (a) keep training in
  MLX and spell the dozen layers out for the translator by hand in its MIL
  builder — stays in MLX, off the beaten path, needs a trial first; (b) keep
  training in MLX and maintain an identical PyTorch copy of the recipe for
  translation only — well documented, two copies that must never drift;
  (c) write the recipe in PyTorch from the start — PyTorch trains on the
  Mac's GPU perfectly well for a net this size and the translator reads it
  directly. (c) is the stupid-simple macOS way and the one Apple documents
  (PyTorch → `coremltools` → Core ML), with the fewest moving parts and the
  fewest places to be wrong. The trainer choice touches only the training
  kitchen: the app sees one `.mlpackage` either way and runs identically on
  the ANE. MLX stays available for experiments; it is not in this feature's
  loop. The exported model is still checked against PyTorch pixel for pixel
  on the same inputs before anything else. Core AI, read up on the same
  evening, exports from PyTorch only — the decision stands and gains a
  second reason.
- **Where the confirmed/rejected patterns live — decided (owner,
  2026-09-06): the session sidecar.** "Owned by" means the one place a
  remembered value lives and the only thing allowed to change it; everyone
  else asks the owner. The rule exists because everything used to live in
  `AppState` (5 593 lines, 497 stored properties at the 2026-09-06
  inventory) and the repo is moving responsibilities out of it. The sidecar
  fits because a label belongs to one file and one scan position, survives
  reopen, and travels with the sidecar when it is shared; the fine-tuning
  script reads labels out of sidecars.

- **The runtime — decided (owner, 2026-09-06 late): Core AI exclusively.**
  The learned detector is a macOS 27-only option; the classical detector
  serves everyone else; a Core ML export stays in the tooling as insurance.
  The reasons and the loop design are in the Core AI block.

#### Core AI (the owner's question, 2026-09-06 evening)

**What it is, source-locked** (developer.apple.com/documentation/coreai,
developer.apple.com/core-ai/, WWDC26 sessions 324 "Meet Core AI", 325
"Dive into Core AI model authoring and optimization", 326;
github.com/apple/coreai-models and /coreai-torch; all read 2026-09-06).
"Run AI models in your app on Apple silicon": a new framework, beta,
introduced in the 27.0 OS generation on every Apple platform including
macOS, Xcode 27, Apple silicon (M1 and later for ahead-of-time compiles),
the Metal Toolchain required to build. Models are `.aimodel` assets. The
Swift API is `AIModel` / `AIModelAsset` / `InferenceFunction` / `NDArray`
/ `ComputeStream` / `AIModelCache`; `ComputeUnitKind` is `cpu`, `gpu`,
`neuralEngine`, chosen through `SpecializationOptions` (`preferred` and
`allowed` kinds; the default uses everything). Python tooling:
`pip install coreai-torch` — `torch.export.export(model, example)` →
`TorchConverter().add_exported_program(...)` → `to_coreai()` →
`optimize()` → `save_asset("model.aimodel")`; `coreai-opt` casts to
float16 and quantises (int4/int8/FP4/FP8, palettization); custom Metal
kernels can be registered and ship inside the asset. Ahead-of-time:
`xcrun coreai-build compile Model.aimodel --platform macOS
--min-deployment-version 27.0` → one `.aimodelc` per device architecture.
Tools: Core AI Debugger app (traces ops back to the Python source), Xcode
graph inspection and validation, Instruments profiling. The tooling repo
is BSD-3.

**What Apple's pages do not say**, read the same day: anything about Core
ML — no deprecation, no migration, no "successor" claim; any batching
guidance; any MLX path — export is PyTorch, and PyTorch only.

**What it changes here.** (1) The ANE now has two doors, not one; the
sentence at the top of this section is corrected. (2) The PyTorch decision
gains a second reason: both exporters read it. (3) Explicit Neural Engine
targeting is a first-class API in Core AI; in Core ML it is a compute-units
hint plus a performance report. (4) The developer tooling answers the
owner's "how do I watch it" question better than Core ML does. (5) A
custom Metal kernel inside the asset means the Metal cross-correlation
(channel three) could one day live inside the model and the whole detector
ship as one asset — noted, not planned. (6) The constraint: macOS 27, beta
today; the app's floor is 14, nominal (compile-verified, never executed;
every machine here runs 26 or 27). The classical detector works
everywhere, so the learned detector can be a macOS-27-only option behind
an availability check without moving the floor.

**Decided (owner, 2026-09-06 late): Core AI exclusively in the app.**
What was weighed against it, none decisive: a beta API until 27.0 ships
(weeks; step 4 is 3–5 weeks out — pin the release Xcode before step 4 and
keep the Swift class thin); batching undocumented (designed in, measured
in step 2 against the 2× ceiling); first-load specialisation (asynchronous,
cached, shown once, never inside a run; ahead-of-time compiles if slow); a
Metal-Toolchain build dependency (installed here; 4.9 GB free on
2026-09-06); young tooling (the pixel check contains the correctness risk,
not the schedule risk); users below macOS 27 get no learned detector (the
classical one works; the floor stays 14 behind availability guards, which
must keep the "compiles for 14" claim true); and "the future" being Apple's
direction, not Apple's statement. This machine builds it today: macOS 27.0
(26A5388g), Xcode 27.0 beta (27A5209h), Metal Toolchain with
`coreai-build` present. The `coremltools` export stays in the tooling as
insurance unless the owner strikes it. Provenance records `runtime:
coreai`, the `.aimodel` SHA-256 (the source asset is the pinned identity;
the specialised artifact differs per device) and the model version.

**Running the loop inside the runtime** (owner, 2026-09-06 late: "make
use of these capabilities"). The owner pasted a third-party claim that
Core AI runs an LLM's token loop — KV cache and sampling — inside the
runtime and is up to 3.5× faster than Core ML for it. That is about
autoregressive generation; a disk detector is one forward pass per
pattern with no token loop, so the number does not transfer and is not a
reason here. The principle transfers: leave the CPU out of the
per-pattern loop. Apple's own pages give the tools — stateful execution,
zero-copy `NDArray` views, `ComputeStream` for asynchronous work, several
exported functions in one asset, custom Metal kernels inside the asset.
Applied, in the order they land:

1. **Batch as a model dimension.** The exported function takes
   `[B, C, 128, 128]` with B fixed at export and chosen by measurement in
   step 2: one call per batch, never per pattern.
2. **Peak-picking inside the graph.** Local maxima as
   `heatmap == maxpool3×3(heatmap)` and `heatmap > threshold`, then a
   fixed K per pattern (the app already caps at 70 peaks) with scores,
   zero-padded — plain ops; where the top-K lands is read in Xcode, and a
   CPU-placed top-K over 70 slots is cheap. The function returns candidate
   coordinates and scores, not heatmaps: a 256×256 scan is 65 536 × 128² ×
   2 bytes = 2.1 GB of float16 heatmaps back to the CPU, against kilobytes
   of candidates.
3. **The probe as model state.** It is identical for every pattern of a
   scan, so a second exported function writes it into a model buffer once
   per scan (the in-place-update pattern Apple shows for KV caches; step 2
   verifies the converter preserves a buffer across calls) and the detect
   function reads it; the per-pattern input drops to two channels.
4. **Compute streams.** Batches enqueued asynchronously so the ANE never
   waits for the CPU to unpack the previous batch's candidates.
5. **Later, not in step 4: the Metal cross-correlation as a custom kernel
   inside the asset**, channel three computed in-graph (its MSL possibly
   the engine's own source), only after it is verified pixel for pixel
   against the Metal engine — in step 4 the correlation still comes from
   the existing, parity-checked engine.

Refinement stays outside the graph: the classical sub-pixel measurement
runs in the Metal engine on the returned candidates. That is the number
that reaches strain, and it stays separately verified.

#### The Neural Engine beyond disk detection

Rule of thumb: **the ANE proposes, classifies and segments; Metal
measures.** Anything per-pattern, fixed-size and convolution-shaped fits;
anything needing FFTs, float32 precision, sub-0.1 px accuracy or a
reduction over the whole cube does not. Candidates, in rough order of
plausibility:

1. **Real-space segmentation of virtual images** for the needle-precipitate
   pipeline (§3): a textbook U-Net task on a small image, probably the
   second ANE feature and the easier one.
2. **Per-position classification** — vacuum, amorphous, crystal, thick — a
   mask from a classifier replacing a hand-drawn region.
3. **ACOM template pre-ranking**: which orientation families to try before
   the classical match; the truth comes free from the template library.
4. **Low-dose denoising** before detection or virtual imaging.
5. **Dead-pixel and beam-stop inpainting.**
6. **Per-pattern embeddings** for unsupervised phase clustering.
7. **Acquisition copilot** (§3, nothing designed): drift, contamination and
   beam-damage flags per frame — cheap enough to run live.

Not for the ANE: ptychography, strain, Q calibration, anything where
0.01 px matters.

**The precipitate chain (the owner's question, 2026-09-06 late;
exploration, not pre-registered).** Asked: segmentation, precipitate
analysis, number densities. Each is its own feature with its own simulated
truth, listed in the order the data flows. The shared payoff of Core AI
exclusively is one runtime class, one simulator, one export path, one
provenance rule and the sidecar labels, reused by every model:

1. **Per-pattern phase classification** — matrix, precipitate phase(s),
   amorphous, vacuum — from the diffraction pattern itself rather than a
   virtual-detector threshold: superlattice reflections are the signal.
   Truth for free: the app's ACOM template library already draws kinematic
   patterns from the imported CIFs; the simulator adds real backgrounds,
   noise and dose. Same loop design as the detector (batch in, a class
   vector per pattern out → a phase map). Checked against classical ACOM
   phase mapping; the disagreement map again.
2. **Real-space precipitate segmentation** — a U-Net over a stack of maps
   at scan resolution: the phase map from (1), virtual BF/ADF, a dark-field
   image at a precipitate reflection, orientation, strain. Instance
   separation for needles by a centre-plus-offset heatmap or a distance map
   (plain ops, ANE). One image per scan, so the loop does not matter here;
   the ANE only makes it free. Truth: synthetic needles (elongated shapes,
   random length, orientation, overlap, contrast, noise) first; the owner's
   brush corrections in the sidecar second.
3. **Per-object analysis** — length, width, orientation in real space; the
   mean pattern inside each object → phase, orientation, strain per object.
   Not ML: Metal/CPU reductions over the mask. This is the data-model change
   §3 names as the expensive part: a per-object result is not a map.
4. **Number density** — count over the analysed extent (the denominator is
   the area actually analysed, calibrated; §3), plus size and orientation
   distributions. Areal, not volumetric, until —
5. **Thickness from PACBED** — a CNN on the position-averaged CBED of a
   region, trained on multislice (abTEM) simulations, regressing thickness
   and mistilt: a published method (Xu & LeBeau, Ultramicroscopy 188, 2018)
   and the missing denominator that makes (4) volumetric. Own simulated
   truth per material and zone axis; heavy once, cheap after.

Also cheap on the same runtime: denoising of virtual images for lower dose,
dead-pixel and beam-stop inpainting, per-pattern embeddings for
unsupervised clustering, ACOM template pre-ranking. Order: nothing before
the disk detector's step 3 verdict proves the pipeline, one Gate B campaign
at a time; then (1) → (2) → (4) with (3) as the data-model session between
them, and (5) once a material's simulation library exists.

#### Working method (decided, owner, 2026-09-06)

- **A branch, with the rules loosened on it and re-applied at the merge**
  (confirmed by the owner, 2026-09-06).
  Steps 1–3 are Python under `tools/` and cannot break the app; step 4 is
  the app wiring. All of it on one feature branch off `main`:
  `ml/disk-detector`, created 2026-09-06. On the
  branch: commit freely, no docs-per-commit, no inventory, no gate per
  commit, experiments allowed to fail in the open. At the merge, in one
  landing: rebase onto `main` (linear `main`, no merge commit), the fixture
  broken and green, the Gate B campaign, `status.md` / `open-items.md` /
  `decisions.md` in the landing commit, inventory exit 0. What stays strict
  even on the branch: never commit the owner's data or the AGPL YOLO
  package; the weights hash from the first export; the `AppState` rule
  (structural — cannot be retrofitted cheaply); no science claim in a live
  doc until merged. `main` moves 20–50 commits on a heavy day, so rebase
  often; a branch older than a week is a merge problem.
- **What can be done away from this Mac.** The simulator, the net, the
  training loop, the export script and their Python tests run on any
  machine, a cloud session included, on the synthetic set. What must be
  local: training on the real probes (the data is in the gitignored
  `References/`), the Core ML pixel check (`coremltools` predicts only on
  macOS), the ANE placement report (Xcode), the Swift wiring, and the drive.
  A cloud GPU can train on synthetic data but the point of the feature is
  the Mac; use one only if the local GPU is the bottleneck.
- **How the owner watches training.** Training is a terminal script, not a
  GUI. PyTorch's own TensorBoard writer shows the loss curve and sample
  heatmaps in the browser while it runs; Xcode's model viewer opens the
  exported `.mlpackage` (inputs, outputs, per-op placement, the performance
  report); for a `.aimodel`, Xcode inspects the graph, Instruments profiles
  it, and the Core AI Debugger app traces ops back to the Python source; mac4DSTEM shows the results — the detector option, the
  disagreement map, the clicks — from step 4. Apple's Create ML app does
  not apply (no custom heatmap task). Training never enters the mac4DSTEM
  GUI.
- **Estimate (2026-09-06)**, anchored on the measured cadence — 239 commits
  in the 31 days since v1.0.0, 18 active days, ~8 commits per active day;
  the v2 release train was ~20 sessions in 15 days: step 1, 1–2 sessions;
  step 2, 2–3 plus training wall-clock; step 3, 1–2; step 4, 4–6 including
  Gate B, the drive and the v3.0 release; step 5, 1–2 at the owner's
  clicking pace. 10–16 sessions, 3–5 calendar weeks to a landed step 4 with
  one Gate B campaign in flight at a time; budget one loop back from step 3.

#### Steps, in order, each its own session

1. **Simulator + fixture** in `tools/disk-detector/`: patterns with known
   disk centres, and the classical detector at the 2026-09-05 Gate D
   settings recovers the drawn centres — the simulator and the fixture are
   proven before any net sees them, independently of any net. A few abTEM
   patterns as the honesty check. Break the fixture first. Classify the
   directory in `run-tests.sh inventory`.
2. **Net + training in PyTorch; export to Core AI (`coreai-torch`); the
   Core ML export kept as insurance.** The `.aimodel` checked against
   PyTorch pixel for pixel; every op's placement read in Xcode/Instruments
   with `.neuralEngine` preferred; the batch size, the in-graph
   peak-picking and the probe-as-state function verified (Core AI block);
   first-load specialisation timed; a per-pattern and per-scan time stated
   from a run against the 2× ceiling.
3. **Does it earn its place?** Net + refinement against the drawn centres
   (recall, precision, residual after refinement); against the classical
   detector on the bullseye and WS₂ cubes; against the throughput ceiling
   set before the comparison. The verdict goes to `decisions.md`.
4. **Wire in as an option**: `DetectorClass`, the hash in provenance, the
   disagreement map, the labelled-pattern store in the sidecar. Gate B
   campaign (it is `Core/` and it moves which disks are found); any
   real-cube disagreement that looks like a defect enters through Gate D.
   The first v3 feature to land bumps the version to v3.0 (`decisions.md`,
   2026-09-02). Owed before this step is called done: the licence table —
   own weights, none; abTEM GPL-3.0 as a tool; YOLOv8 code and weights
   AGPL-3.0, which is why the stock `yolov8n.mlpackage` dragged into the
   Xcode project on 2026-09-05 is a reference only and is never committed.
5. **Fine-tuning** on the owner's confirmed patterns, the bullseye probe
   first; retrained weights are a new hash, so old results still say what
   made them.


## C6 — the table (2026-09-07 night, completed 2026-09-08 morning; the verdict is owed)

Every number below is from one run of the EXPORTED asset
`disk-detector-heatmap-b32.aimodel` (run3, sha `a2794a8a…`) on the Neural
Engine at the shipped threshold **0.9**, under the one truth rule
(`simulate.VISIBLE_MIN` = 0.5), with py4DSTEM 0.14.19 (the lock) as the
classical side at the 2026-09-05 settings. Log:
`scratchpad/c6-evaluate-asset-0.9.log`, JSON `c6-eval-asset-0.9/evaluate.json`
(C2/C5/C6 session). Before this table the branch quoted 0.963 / 0.78 — at
threshold 0.3, from PyTorch, under a different truth rule.

| Set | Truth (visible) | Net at 0.9: recall / precision | Classical: recall / precision | Note |
|---|---|---|---|---|
| Fixture (16 patterns) | 230 | **0.939 / 0.896** (refined; raw recall 0.991; residual median 0.26 px) | **0.900 / 0.866** | the same visible truth for both; `verify_fixture.py` keeps its own intensity rule and stays 148/153 |
| Validation set (128 simulated, seed 999) | 2 808 | **0.679 / 0.939** (raw picks, 2 px) | — | the number the record JSON now states; 0.963 was at 0.3 |
| Bullseye cube, 143 positions (stride 8) | none (no labels yet) | 416 peaks vs classical 442; count difference median 0, 49 % of positions differ somewhere | — | unchanged from the branch's 2026-09-07 evening run |
| WS₂ cube, 256 positions, **counts-scaled by `to_counts`** | none | 6 566 peaks vs classical 256 (one per position at either `minRelativeIntensity`); net − classical median +24 per position | — | NEW: with the count-scaling rule the net proposes ~24 spots per position where it saw nothing before; whether they are disks is the owner's eye, then the labels |
| **Frozen hand-labelled bullseye set** — 40 positions, 306 centres, labelled by the owner 2026-09-08 00:20–00:30 in the native 250-px frame (`label_centres.py`, seed 1; JSON sha256 `3c43e89d…3aec`, gitignored) | 306, of which **126 are reachable by a 128-px frame** (the shipped asset sees the central 128 px of the 250-px pattern; a label outside that frame or inside its 6-px edge is unreachable by either detector — `truth_eligible` in the labels block, 2026-09-08) | **0.333 / 0.903** over all 306; **0.810** over the 126 reachable (113 predicted, 102 matched) | **0.271 / 0.735**; 0.659 over the 126 (113 predicted, 83 matched) | the same 128-px frame for both, 2 px match; `scratchpad/c6-eval-run3-labels.log`, `c6-compare-128-eligible.log` (C6 session, 2026-09-08) |

**The 256-px retrain (C0's accepted condition) ran unattended 2026-09-08 00:30–02:13** — `overnight-256.sh` on the branch worktree, output `References/training_runs/disk-detector-2026-09-08/` (`01-…05-*.log`, `overnight.log`): ingredients at 256 (192 textured backgrounds), a 90-minute train at width 12 (6 500 steps, best val loss 0.002 94, in-loop native-128 fixture 1.000 / 0.697 in PyTorch at the cap), every export variant, `check` recorded not fatal (heatmap-b32 on the Neural Engine max |diff| 0.075 against PyTorch float32 with a float16 floor of 0.006, tolerance 0.1; the GPU `detect-b16` and the stateful asset segfault as recorded 2026-09-07, and the GPU `detect` b32/b64 top-k returns 6.6 % / 2.7 % of numpy's peaks where ANE and CPU return 98.9–99.4 %), `evaluate --asset --labels` exit 0. Rows below: the EXPORTED `disk-detector-heatmap-b32.aimodel` of that run (sha `f4cd741f…`) on the Neural Engine at 0.9, 0.45 ms per pattern; `05-evaluate.log`, `evaluate/evaluate.json`, and the rerun with the eligible counts `evaluate/evaluate-eligible.json` (`scratchpad/c6-compare-256-eligible.log`, numbers identical).

| Set, 256 px | Truth (visible) | Net at 0.9: recall / precision | Classical: recall / precision | Note |
|---|---|---|---|---|
| Fixture, the 16 native-128 patterns PADDED to 256 | 308 eligible (230 at 128: the padding brings the disks the 128 border cut into the eligible set, and both detectors lose them) | **0.714 / 0.978** (raw 0.740; refined residual median 0.28 px) | **0.744 / 0.774** | not comparable with the 128 rows above; comparable between its own two columns |
| Validation set (128 simulated at 256, seed 999) | 5 689 | **0.476 / 0.995** (raw picks, 2 px) | — | the 256 simulator draws twice the disks per pattern; at 0.9 the net is precise and misses half |
| Bullseye cube, 143 positions, the whole 250-px pattern | none | 799 peaks vs classical 1 392; net − classical median +1, mean −4.1 (min −64); 87 % of positions differ | — | the classical's extra peaks are the outer-region ones the next row scores against labels |
| WS₂ cube, 256 positions, 128 padded to 256, counts-scaled | none | 5 671 vs classical 256; +21 median per position | — | same picture as at 128 (+24) |
| **Frozen hand-labelled bullseye set, all 306 reachable** | 306 | **0.667 / 0.840** (243 predicted, 204 matched) | **0.487 / 0.485** (307 predicted, 149 matched) | **the row the verdict rests on**, with the 128 row above |

Where the two detectors disagree with the labels (`scratchpad/c6-overlay.py`, `c6-overlay-256.png`, `-128.png`; the same frame, edge and 2-px match as the table): of the classical's 158 unmatched predictions at 256, 128 lie OUTSIDE the central 128-px window and 30 inside; of the net's 39, 27 outside and 12 inside. Inside that window (126 labels) the net reaches 0.794 and the classical 0.714; outside it (180 labels) the net matches 106 (0.589) and the classical 60 (0.333). In the eight-position grid the classical's unmatched peaks sit on the background of sparse patterns (position (5, 34): 13 classical peaks, 5 labels, 5 net), and the net's misses are the faint outer disks the owner labelled. Whether those labels are disks is the owner's eye; the counts are reproducible from the script and the retained npz.

Steps 1–3 of the four are done (the owner's labels; both assets scored against them; the retrain). **Step 4, the verdict in `decisions.md` in the owner's words, is the one owed line.** The Python tooling (without `scan-bench/` and `fixture/swift/`, the Swift side) is on `main` since 2026-09-08 with `disk-detector` in the `scientific` list.

Export check the same night (`c6-check-real.log`, `run3/export/check.json`
regenerated): six runtimes within tolerance 0.1 of PyTorch float16 — ANE
0.217 ms per pattern (max |diff| 0.062, float16 floor 0.009), CPU 9.6 ms,
GPU 0.685 ms; CHECK PASS, exit 0. The Core AI cache went stale between the
check and the evaluation (the generic ObjC error on `load_function`, the
recorded 2026-09-06/07 trap); `run_coreai_subprocess` now moves the cache
aside and retries once, and the rerun passed.

Labels-stage smoke test: three positions labelled with the CLASSICAL peaks
(not truth) ran end to end — net 4/5, classical 5/5 — proving the stage,
nothing about the detector.

**Where the work is.** Branch `ml/disk-detector` at `f057545` (2026-09-08: the size session — `--size` on every entry point, `fit_to` crop-or-pad, native-frame labels, `overnight-256.sh`, `truth_eligible`), on top of `219ae54` (the C6 Python side). Worktree `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/fc84678a-9c17-46c2-909a-0d4274668d4f/scratchpad/ml-wt`; the labels file lives there (gitignored). Gate logs: `c6-fixture-before.log`/`c6-fixture-after2.log` (2026-09-07), `c6-fixture-wt-20260908.log` and `c6-fixture-main-20260908.log` (148/153, every break fails, both trees). The verdict (step 4) is the owner's, in `decisions.md`, either way; C7 only if it says the net adds disks the classical path misses.
