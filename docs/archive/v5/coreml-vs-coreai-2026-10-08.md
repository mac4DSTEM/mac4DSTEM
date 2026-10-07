# Decision sheet: learned disk detector on Core ML, Core AI, or both

Parked question (owner, 2026-09-23): "Core ML vs Core AI is to be decided again at a later stage" [docs/decisions/014-learned-disk-detector.md:24-25].
Read-only research, 2026-10-08. No repo file edited; nothing built or run.
Sources: `path:line` = repo file; "Apple:" = Apple documentation MCP page (path under `documentation/` and its URL). Anything I could not source is marked **unverified**. Effort figures are my estimates, not sourced.

## 1. The problem in plain words

The learned disk detector is a 256 px U-Net that proposes Bragg disk centres. The app runs it on the Neural Engine through Core ML. Apple's Core AI framework (macOS 27) can also run such a model. ADR 014 chose Core ML on 2026-09-07 for three reasons: speed was a wash, Core ML worked on the old macOS 14 floor, and the Core AI beta had a segfaulting stateful asset [docs/decisions/014-learned-disk-detector.md:11-13]. The macOS 27 floor (ADR 008) has since removed the first of these reasons, and the other two stand until re-measured [docs/decisions/014-learned-disk-detector.md:24-27; docs/decisions/008-macos-floor-and-arm64-only.md:6-9].

ADR 048 already took the revisit "under delegation: Core ML for every model, overrule on sight" [docs/decisions.md:24]. The owner's parked question therefore needs a confirm-or-change answer, not a fresh start.

Three facts drive the choice:
- **Training writes Core ML.** The in-app fine-tune writes a `.mlpackage` (`mac4DSTEM/Training/ModelPackageWriter.swift:14, 63-70`), and ADR 048 states "Core AI has no on-device writer" [docs/decisions/048-clearing-the-board-decisions.md:23-24]. A Core AI-only app cannot produce the fine-tuned model that ADR 043 and ADR 048 describe [docs/decisions/043-fine-tuned-models-judged-by-detection.md:11-21].
- **The Core ML path needs a workaround on this Mac.** On the M5 Pro under macOS 27.0.1, `.all` plans every op on the GPU, and `.cpuAndNeuralEngine` runs the Neural Engine only at batch 32 and falls back silently to the CPU at other batches [docs/archive/v4/ane-return-2026-09-30/record.md, section E1; docs/archive/v4/newmac-gateD-2026-09-30/record.md:48-53]. The app now refuses at load any model the Neural Engine did not run [mac4DSTEM/Core/ML/LearnedDiskDetector.swift:85-89, 124-136, 617-628]. The mechanism is recorded as **unproven** [docs/archive/v4/newmac-gateD-2026-09-30/record.md:70-71].
- **Apple now documents explicit Neural Engine targeting in Core AI.** `ComputeUnitKind.neuralEngine`, `preferredComputeUnitKind`, `allowedComputeUnitKinds` and `availableKinds` are listed in Apple: `documentation/CoreAI/ComputeUnitKind.md` (https://developer.apple.com/documentation/coreai/computeunitkind) and `documentation/CoreAI/SpecializationOptions.md` (https://developer.apple.com/documentation/coreai/specializationoptions). This contradicts the ADR 014 sentence "The ANE is reached only through Core ML" [docs/decisions/014-learned-disk-detector.md:33]. The archive also records Core AI targeting as "a first-class API" [docs/archive/v3/learned-detector-2026-09-06.md:344].

## 2. Sourced facts

### Repo
- Runtime: `LearnedDiskDetector` holds an `MLModel` and loads with `.cpuAndNeuralEngine` [mac4DSTEM/Core/ML/LearnedDiskDetector.swift:73, 94-95]. It compiles the package at load unless a precompiled `.mlmodelc` is passed [LearnedDiskDetector.swift:108-115; mac4DSTEM/Session/LearnedDetection.swift:204-208].
- Batch: the package's default batch (32 as shipped) is used, and short batches are zero-padded [LearnedDiskDetector.swift:54-60, 351-352, 540]. The load runs one fixed batch on the Neural Engine and on `.cpuOnly`, and throws if they agree bit for bit [LearnedDiskDetector.swift:124-136]. The error text is at [LearnedDiskDetector.swift:617-628].
- Compute-unit choice and reason: [LearnedDiskDetector.swift:85-89]. Measured 2026-09-30 on M5 Pro, macOS 27.0.1 [docs/archive/v4/ane-return-2026-09-30/record.md, E1 table].
- Speed, 2026-09-07 (old Mac, not M5): Core ML `CPU_AND_NE` 0.305-0.338 ms per pattern, Core AI 0.344-0.363 ms [docs/decisions/014-learned-disk-detector.md:11-12; docs/archive/decisions-log-2026-08-17-to-2026-09-16.md:432-440]. **Not re-measured on the M5 or on macOS 27.0.1.**
- Core AI code was removed. It was about 110 lines of Core AI API and lives only in history and the dropped `ml/disk-detector` branch [docs/archive/consolidation-plan.md:174; docs/archive/2026-09-11-ai-port-analysis.md:84, 170; docs/archive/git-cleanup-2026-09-17.md:70].
- The old Core AI export ran `coreai-torch` and had a stale-cache trap and a subprocess workaround [docs/archive/v3/learned-detector-2026-09-06.md:326-331, 591-593]. Separately, user memory records that topk crashed ANE load and needed a subprocess (auto-memory `coreai-tooling-facts-2026-09-06.md`; not in the repo).
- Training stays off the Neural Engine: the ANE runs the model, training runs on the GPU [docs/decisions/048-clearing-the-board-decisions.md:24-25]. Training is written in Swift and MPSGraph or MLX, not Core ML [mac4DSTEM/Training/DetectorGraph.swift; the MPSGraph/MLX grep hit only, not read in detail].
- Other archive: "Core AI has no on-device writer" [docs/archive/v4/c2-mlx-spike-2026-09-28.md:60; docs/archive/v4/c3-training-preregistration-2026-09-30.md:109]. The Core AI research note says "No, inference only... `.aimodel` authored only in Python (`coreai-torch`)" [docs/archive/v4/ondevice-training-research-2026-09-28.md:17, 37].
- Open item: the ANE load refusal and its residuals (M5 only, macOS 27.0.1; a partial Neural Engine plan not pinned by a test) [docs/open-items.md:353-357].
- Bundled model: `Models/DiskDetector/disk-detector-heatmap-256.mlpackage` (listed in the working tree; not inspected further).

### Apple (MCP)
- Core AI is macOS 27.0+ and "helps you build, run, and deploy AI models... across the CPU, GPU, and Neural Engine" [Apple: Core AI, `documentation/CoreAI/CoreAI.md`, https://developer.apple.com/documentation/coreai].
- Conversion: models are converted to `.aimodel` with Core AI PyTorch Extensions [Apple: `documentation/CoreAI/CoreAI.md`, Overview]. Core AI Optimization and the Core AI Debugger are listed as separate tools [same page].
- The Core AI page says "If your app uses model types other than neural networks... see Core ML" [Apple: `documentation/CoreAI/CoreAI.md`, Overview]. This suggests Core AI is the neural-network path, but the page does not say Core ML is deprecated (**unverified**).
- Loading: `AIModel(contentsOf:options:)` is async and specializes the model for the device; the result is cached [Apple: `documentation/CoreAI/integrating-on-device-ai-models-in-your-app-with-core-ai.md`; `documentation/CoreAI/managing-model-specialization-and-caching.md`].
- Default specialization picks the compute units itself to minimise latency; `.cpuOnly` and `preferredComputeUnitKind` override it [Apple: `documentation/CoreAI/managing-model-specialization-and-caching.md`; `documentation/CoreAI/SpecializationOptions.md`]. Whether `preferredComputeUnitKind = .neuralEngine` guarantees Neural Engine execution is **unverified**; the Apple page says "preferred".
- Ahead-of-time compile: `xcrun coreai-build compile` produces one `.aimodelc` per device architecture; it needs the Metal Toolchain and targets Apple Intelligence devices (Mac M1 or later) [Apple: `documentation/CoreAI/compiling-core-ai-models-ahead-of-time.md`].
- Core ML compute units: `.all` lets the OS pick, including the Neural Engine; `.cpuAndNeuralEngine` allows CPU and Neural Engine but not GPU [Apple: `documentation/CoreML/mlcomputeunits.md`; `documentation/CoreML/mlcomputeunits/all.md`; `documentation/CoreML/mlcomputeunits/cpuandneuralengine.md`].
- Core ML can "train or fine-tune models, all on a person's device" [Apple: `documentation/CoreML/CoreML.md`, https://developer.apple.com/documentation/coreml/coreml].
- Per-operation placement can be read from the Xcode performance report or from `MLComputePlan` in code [Apple: `documentation/CoreML/analyzing-a-core-ml-model-s-performance-in-xcode.md`]. The page says the plan can differ from what runs, and it does not show the Core AI equivalent.
- `MLModel` has `predictions(fromBatch:)` [Apple search hit: `documentation/CoreML/mlmodel/predictions-frombatch.md`]. Its behaviour on the Neural Engine is **unverified**; the page was not read.

## 3. Options

### (a) Stay on Core ML
- **Lets the app:** keep the shipped detector, the fine-tune flow (ADR 048), the `.mlpackage` as the one format, and the load-time Neural Engine refusal already tested on the M5.
- **Effort:** 0 sessions to keep. The re-measure at the trigger is about 1 session (estimate).
- **Risk:** the compute-unit workaround stays in place, and the mechanism is unexplained [docs/archive/v4/newmac-gateD-2026-09-30/record.md:70-71]. Core ML has no explicit "run on the Neural Engine" request beyond the enum. Whether Core ML is still Apple's direction for neural networks is **unverified** (see section 2).

### (b) Move the bundled detector to Core AI
- **Lets the app:** an explicit Neural Engine preference and an `availableKinds` check (Apple: `ComputeUnitKind.md`); the Core AI debugger and Instruments tools (Apple: `CoreAI.md`); ahead-of-time compile (Apple: `compiling-core-ai-models-ahead-of-time.md`).
- **Cannot do:** write a model on device. The in-app fine-tune would need Core ML anyway, or the feature would be dropped [docs/decisions/048-clearing-the-board-decisions.md:23-24]. Training stays Core ML, so this is not a full migration.
- **Effort (estimate):** 3-4 sessions. Port the Core AI runtime (about 110 lines, archive); add a coreai-torch export and a Python env with a torch pin (auto-memory, not in repo); run Gate D because the numerics move. The threshold 0.7 and the 0.77/0.71 fixture numbers were measured on Core ML [docs/decisions/014-learned-disk-detector.md:14-16]. Also re-check Neural Engine placement and migrate the provenance keys, because `learned_model_sha256` names a different asset [docs/decisions/014-learned-disk-detector.md, Governs].
- **Risk:** high. Core AI is new (macOS 27); the ADR 014 beta segfault report is not re-tested (**unverified** whether it still happens on GA 27.0.1). No Core AI op-coverage check for the U-Net (no FFT in Core ML, ADR 014:33; Core AI FFT support **unverified**).

### (c) Both behind one protocol
- **Lets the app:** choose a runtime per model. Core AI could serve the bundled model while Core ML serves trained packages, and the two could be compared side by side during a migration.
- **Effort (estimate):** 1 session for the protocol and its parity harness, plus 3 sessions for the Core AI backend as in (b). Total about 4-5 sessions.
- **Risk:** highest maintenance. Two runtimes means two numerics paths, and ADR 043 judges a detector on the runtime it ships on, so each backend needs its own held-out run [docs/decisions/043-fine-tuned-models-judged-by-detection.md:21-26]. The app also becomes less simple, which the owner's rule against extra surface and complexity counts against [CLAUDE.md, "What the app is"].

## 4. Recommendation

**Option (a): stay on Core ML, and close the revisit with a measurement, not a migration.** Set a trigger in `docs/decisions/014`: run a time-boxed Core AI spike on the M5 with the 40-position labelled set and the shipped 256 px model. Measure three things: (1) Neural Engine placement, using the Core AI tools; (2) ms per pattern; (3) detection parity with the Core ML run at threshold 0.7. Reopen the runtime only if Core AI wins on all three and the fine-tune path has an answer. Correct the ADR 014 sentence "The ANE is reached only through Core ML" in the same edit [docs/decisions/014-learned-disk-detector.md:33], since Apple's Core AI pages document Neural Engine targeting (section 1).

Trigger: the precipitate classifier on the Neural Engine (S8) or the next change to the learned detector, whichever comes first [docs/decisions/014-learned-disk-detector.md:27-29].

## 5. Argument against the recommendation

Staying on Core ML means keeping a workaround for a scheduler we cannot explain. On the M5 the `.all` setting ran the detector on the GPU, the Neural Engine served only one batch size, and the app's answer is a load-time check that refuses the model [docs/archive/v4/newmac-gateD-2026-09-30/record.md:48-53, 70-71; LearnedDiskDetector.swift:124-136]. Core AI documents an explicit Neural Engine request and an availability check (Apple: `ComputeUnitKind.md`), which could remove the need for the workaround. Waiting also raises the cost of switching later. The 27 release is when Apple's neural-network documentation is written for Core AI, so each release in which Core ML stays our only path adds more code that Core AI would replace. The strongest counter-point is the one the recommendation accepts: the fine-tune path has no Core AI writer, so a migration cannot be the whole answer. The recommendation's measurement step is the only thing that would tell whether the explicit Neural Engine request does better than the Core ML check on this Mac.

## 6. Second opinion

Not obtained. ADR 050 requires an independent second opinion on decision sheets; this sheet has not been reviewed by a different model or refuter. It is owed before the owner answers.

## 7. Unverified list

- Whether Core AI is still beta on macOS 27.0.1 (Apple pages read did not say).
- Whether `preferredComputeUnitKind = .neuralEngine` guarantees Neural Engine execution, and whether Core AI reproduces the batch-32-only behaviour (untested).
- Whether the ADR 014 Core AI segfault reproduces on GA 27.0.1 (repo report from 2026-09-06, beta).
- Whether Core AI has no on-device writer and no training API in the current docs (checked only for pages read; the repo's archive claims it).
- Whether `predictions(fromBatch:)` changes Neural Engine placement (page not read).
- Whether Core ML is deprecated or receives no neural-network updates (not stated in pages read).
- Core AI support for the U-Net's ops, including the no-FFT point (not checked).
- All effort figures in sections 3-4 are estimates.

## Supervisor check (2026-10-08, Apple documentation MCP, opened by the supervisor)
- CONFIRMED: `ComputeUnitKind` has `.cpu`, `.gpu`, `.neuralEngine` and `availableKinds`; "by default, specialization uses all available
  compute units" (documentation/CoreAI/ComputeUnitKind.md).
- CORRECTION: that page's availability list is iOS, iPadOS, tvOS, visionOS and watchOS 27.0+ — **macOS is not listed**, and a macOS-filtered
  search returns only the Core AI overview, not `SpecializationOptions`. The framework overview names no platform list; the repo ran Core AI
  on a macOS 27 beta on 2026-09-06. So **whether explicit Neural Engine targeting is available on macOS 27 is unverified** — this weakens
  §5's main argument, and the proposed spike must check it first (a doc-metadata gap or a real platform limit).
- CONFIRMED: the overview sends non-neural-network models to Core ML; it does not call Core ML deprecated.
- Second opinion still owed (ADR 050) before this goes to the owner.
