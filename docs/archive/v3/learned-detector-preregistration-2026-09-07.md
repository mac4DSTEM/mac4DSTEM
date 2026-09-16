> History, not guidance. Moved verbatim from `docs/v3-plan.md` §3a on 2026-09-16 (docs consolidation); the live replacement is `ROADMAP.md`.

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
