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
  get wrong; the most plausible second Neural Engine feature (§3a). **Precipitate density**
  (2026-08-26): count over a calibrated extent — the denominator must be the
  area actually analysed; areal is not volumetric without foil thickness.
  → v3 design session (§1.5).
- **EDX correlation** (2026-08-26) — a data-model change before a feature: a
  second signal with its own reader and units, registered onto the scan grid
  with the transform recorded. Unclaimed.
- **Live acquisition · copilot** — named, nothing designed. Unclaimed.
- **Learned disk candidates** (owner, 2026-09-05; Core ML on the Neural Engine,
  2026-09-07) — pre-registered below (§3a); the first ML feature.

### 3a. Learned disk candidates — pre-registration (2026-09-05; rewritten 2026-09-07, C1)

The planning transcript, the Core AI notes and the evidence block that stood
here until 2026-09-07 are verbatim in
[`docs/archive/v3/learned-detector-2026-09-06.md`](archive/v3/learned-detector-2026-09-06.md).
This is the registration the work is checked against; nothing is merged to
`main` — the work is `ml/disk-detector` (`18bb13b`), reviewed in
`docs/archive/consolidation-plan.md` §3 and gated by C6/C7 there.

**What it is.** A second `DetectorClass` beside the classical one: a small
plain-convolution U-Net (fp16, fixed 128×128 input, no FFT, no custom layers)
paints a disk-centre heatmap; peak-picking on it gives CANDIDATES; the
existing correlation/centroid refinement measures each to sub-pixel. No
coordinate from the net reaches strain or Q calibration. Recall over
precision: the net over-proposes, refinement prunes. Opt-in, off by default;
the classical detector serves everyone.

**Inputs.** Three channels: the pattern (log-scaled, normalised per pattern),
the measured probe, and the classical detector's cross-correlation at its
current settings (owner, 2026-09-06: the net sees the classical evidence and
learns which maxima are ring artifacts; the price is that it is not a blind
second reading). Training data is simulated on the fly by our own simulator
from measured probes and real backgrounds in the gitignored
`References/training_dataset/`; real cubes labelled by the classical detector
are validation only, never truth. No py4DSTEM model, no download, and no
py4DSTEM parity for this feature — the accepted cost (`decisions.md`).

**Runtime and weights.** PyTorch trains (MPS); `coremltools` exports one
`.mlpackage`; Core ML serves it on the Neural Engine on the macOS 14 floor
(owner, 2026-09-07, inverting the 2026-09-06 Core AI choice; that export
stays in the tooling as insurance). Weights ship in the bundle, pinned;
SHA-256 in provenance beside `detector_class`; every retrain is a new hash.

**Owners of state and home.** `DetectorClass` lives in the detection
settings, never in `AppState`; the disagreement map (net vs classical per
scan position) is a product like any other; the owner's confirmed/rejected
patterns belong to the session sidecar, exported for fine-tuning to a
gitignored folder. `tools/disk-detector/` (Python, never ships; on the
branch only) is classified by `run-tests.sh inventory` when it lands.
Licences: own weights; abTEM GPL-3.0 as a tool only; the stock AGPL
`yolov8n.mlpackage` WAS committed (C0 (3)) and left the tree in C2 (2026-09-07;
`NOTICE` says so).

**Gates, in order, each its own session; the bar is `archive/consolidation-plan.md`
§3 "The minimum bar".** (1) Simulator + fixture proven and broken before any
net — met on the branch, the one reproducible item. (2) Net trained; the
exported asset checked against PyTorch with a stated tolerance and a
non-zero exit; every op's placement read in Xcode or Instruments. (3) Does it
earn its place: the EXPORTED asset at one pre-declared threshold on the
fixture, the validation set and a frozen hand-labelled real test set (≥ 30
positions, bullseye plus one other camera, never used for selection) —
recall, precision, n — beside the classical detector on the same test set;
`detectAll` wall clock from the app on the same cube against the ceiling C6
restates (the 2× target was missed at 2.81× with 3×3 tiling; accepted for
now, a 256-px retrain owed — C0 (2)). (4) Wire in as an option: Gate B
campaign, the drive, v3.0 (C7). (5) Fine-tuning on the owner's clicks.

**Verdict (step 3): passed 2026-09-08** — on the frozen hand-labelled set
the net finds the same real disks with far fewer inventions (256 px: 0.667 /
0.840 against the classical 0.487 / 0.485; `archive/v3/learned-detector-2026-09-06.md`,
"C6 — the table"). The owner's decisions are the `decisions.md` entry of
2026-09-08: the 256-px model, the picker in Disk detection, default 0.7.

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
