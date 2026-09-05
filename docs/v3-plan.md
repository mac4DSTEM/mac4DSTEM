# v3 plan — draft, for refinement

Imported 2026-09-03 from the "mac4DSTEM v3 Themes" artifact of 2026-08-28
(seven parallel surveys of the pinned py4DSTEM source against `Core/`: 166
findings, 45 high-value gaps, 77 absent, 54 partial, 7 absent by recorded
decision). The ranking is a recommendation; sizes are rough; nothing here is
committed to. The first v3 feature to land bumps the version to v3.0
(`decisions.md`, 2026-09-02). Origin records for the differentiators:
`docs/archive/v2/post-v1-ideas.md`. The consolidation this builds on is
`docs/archive/v2/v2.5-plan.md`.

## 1. Decided 2026-08-28 (owner)

1. **v3 is a sequence, not a bet.** All themes are wanted; order comes from
   two scarce resources — one Gate B science campaign in flight at a time,
   and the owner's driving time — plus hard dependencies. Front of the queue,
   dependency-free, may interleave: the calibration foundation (§2.1), the
   polar transform and I(q) (the smallest slice of §2.2), grain segmentation,
   notebook export, the Materials Project importer. Then, dependency-gated:
   multi-phase → precipitates → EDX; PDF and fluctuation microscopy once the
   polar transform exists; ptychography depth last.
2. **Grain segmentation and multi-phase ship together** — segment the grains,
   then identify each one's phase. Accepted consequence: multi-phase needs
   point-group coverage, so pairing them delays segmentation, which itself
   needs no crystal model.
3. **The notebook exports the recipe as py4DSTEM code, no comparison.** A
   translation, not a reproduction: a header saying so, an inline note at
   each step carrying a `DEVIATION`, and a step with no py4DSTEM equivalent
   emits a comment rather than vanishing.
4. **Materials Project as an importer that embeds** the fetched structure in
   the session sidecar with its provenance, so recipes reproduce offline.
   Required warning: MP lattice parameters are DFT-relaxed (~1 % off measured)
   — fine for phase identification, a silent systematic as a strain or Q
   reference.
5. **Precipitates enter v3 as a design session, implementation unscheduled**
   (the shape S12 used for Q calibration). It settles four questions only:
   what a per-object result is in a data model where everything today is a
   field per scan position; how it exports; how it lives in a sidecar; what a
   density refuses when it cannot state its denominator. A contrast-based
   first version (virtual dark field → segment → count → calibrated area)
   needs no ACOM.

Added 2026-09-03: a run layer (`AnalysisRunner` with an injected host, one
for every family) is the recorded next consolidation item, unscheduled; the
run functions stay on `AppState` until then (`decisions.md`).

## 2. Parity themes, ranked by value to a working microscopist

| # | Theme | Absent today | Size · depends on |
|---|---|---|---|
| 1 | **Calibration foundation** — everything else stands on it | vacuum probe from a separate scan (the largest detection-side gap; blocks samples with no vacuum in frame and is the real fix for the MgO disk-radius finding); beamstop-tolerant origin (`get_origin_friedel`; blocks Medipix/EMPAD beamstop data); an origin validity mask (owed by the 2026-08-28 admit-with-fraction decision — `OriginMaps` records no excluded positions); the discarded CoM beam centre in `probeSize` | small · after the origin-fit items in `open-items.md` |
| 2 | **Amorphous and nanocrystalline** — a modality the app lacks | polar / polar-elliptical transform (gates the rest); radial profile I(q); pair distribution function (scattering factors already ported); radial variance / fluctuation microscopy | large · polar transform first |
| 3 | **Strain where disk detection fails** — the peak-finding path finds no basis on three of four training datasets (`py4dstem-pipelines.md` §9.2/§10.3) | whole-pattern fitting; user-supplied reference lattice (absolute strain); strain from the ACOM solution | medium–large · — |
| 4 | **From maps to the numbers a paper reports** | grain segmentation (size distribution, boundary misorientation, twin fraction); multi-phase identification (which phase is where); full point-group coverage | medium · point-group coverage first |
| 5 | **Interoperability** | read a native py4DSTEM EMD (probe, Bragg vectors, calibration); the notebook export (§1.3) | medium · pinned py4DSTEM env exists |
| 6 | **Detector realism** | per-position detector shift (the origin map exists); arbitrary detector masks (the GPU path takes a weight image); hot-pixel filtering; ARINA reader, MIB packed modes | small each · — |
| 7 | **Phase-contrast depth** | direct ptychography (SSB / OBF / WDD); mixed-state; probe-position correction | large · — |

## 3. Beyond py4DSTEM — the differentiators

All requested by the owner; all out of v2 by the 2026-08-18 decision ("each
is its own product").

- **Needle-shaped precipitate pipeline** (2026-08-06, re-requested
  2026-08-26) — per-object, real-space segmentation driving per-object
  analysis; a per-object result is not a map, which is the expensive part to
  get wrong; the most plausible first home for MLX. **Precipitate density**
  (2026-08-26): count over a calibrated extent — the denominator must be the
  area actually analysed; areal is not volumetric without foil thickness.
  → v3 design session (§1.5).
- **EDX correlation** (2026-08-26) — a data-model change before a feature: a
  second signal with its own reader and units, registered onto the scan grid
  with the transform recorded. Unclaimed.
- **Live acquisition · copilot** — named, nothing designed. Unclaimed.
- **Learned disk candidates** (owner, 2026-09-05; Core ML + MLX preferred) —
  pre-registered below (§3a); the first ML feature, starting 2026-09-06.

### 3a. Learned disk candidates — pre-registration (2026-09-05)

**Shape.** A second detector class beside the classical one: a net proposes
disk CANDIDATES on a pattern, the existing correlation/centroid refinement
measures each to sub-pixel precision. No coordinate from the net reaches
strain or Q calibration — strain needs 0.01 px and a probability map or a
box centre is ~0.5 px. This is also how py4DSTEM's own ML mode works:
FCU-Net (Fourier Convolutional U-Net, Munshi et al. 2022; `crystal4D`,
TensorFlow/Keras) outputs a disk-probability map and `get_maxima_2D` does
the rest (`braggvectors/diskdetection_aiml.py`). It takes the PROBE as a
second input, which is why it generalises across probe shapes — the bullseye
failure class. Core ML is how the app runs a model (Neural Engine, Swift, no
Python); MLX is for experiments and fine-tuning in Python; an MLX model
reaches the app through `coremltools` like any other.

**Owner of state.** The kernel's owner today is `AppState.probeKernel`; a
learned detector adds a `DetectorClass` beside `ProbeKernel`, owned by the
detection settings, never new `AppState` stored state. Provenance carries
`detector_class` and the model file's SHA-256 — a result must say which
weights made it, so weights are pinned and hashed, never fetched "latest" at
build time (py4DSTEM's loader downloads a zip from Google Drive by a
`model_metadata.json`; we vendor one copy).

**Steps, in order, each its own session.**
1. FCU-Net as a reference in Python: `crystal4D` + TensorFlow in the py4DSTEM
   env, `_get_latest_model()` once, run on the bullseye and WS₂ cubes;
   compare its peak sets with the classical detector at the settings the
   2026-09-05 Gate D established. Decides whether the net earns its place.
2. Convert to Core ML with `coremltools`; check the converted model against
   Keras pixel for pixel on the same probability maps. The FFT layers are the
   likely hand-written part. MLX is NOT a Keras loader: the architecture is
   rewritten in MLX and the exported arrays loaded layer by layer, each
   layer checked numerically against Keras.
3. Fixture in `tools/` on SIMULATED truth — patterns drawn with known disk
   centres, run through net + refinement, checked against the drawn centres.
   No py4DSTEM parity exists for a Core ML model; simulated truth is the
   ground. Break it first, as always.
4. Wire it in as an option with the hash in provenance; Gate B campaign.
5. Only then MLX fine-tuning on the owner's own probes and cameras; the
   bullseye probe is the first case.

**Owed to the owner before step 4.** The licence of the FCU-Net weights
(py4DSTEM's project) before they ship inside a GPL-3.0 app; YOLOv8 code and
weights are AGPL-3.0, which is why the stock `yolov8n.mlpackage` in the tree
is a reference, not a dependency, and is not committed.

## 4. Leave alone; where the app is ahead

Not chased: py4DSTEM's visualization layer, `utils/` helpers for their own
sake, `.automatic` residency (needs a second machine). Ahead of py4DSTEM and
part of the product story: the load-specification and promote workflow,
provenance that survives export and reopen, refusals that name what failed,
the session sidecar as a sharing unit.

## 5. Open questions for the next pass

1. One theme done properly, or several started? Themes 1 and 2 are different
   bets — finish what exists, or open a new user base.
2. Which front-of-queue item leads? Gate B capacity is one at a time; the
   calibration foundation clears live defects and the validity mask is owed.
3. Does the notebook change who the app is for (results checkable without a
   Mac — a distribution argument)?

## 6. How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
