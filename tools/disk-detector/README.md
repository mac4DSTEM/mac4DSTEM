# tools/disk-detector — the learned disk detector's tooling

`docs/v3-plan.md` §3a. Python that never ships: a simulator with known disk
centres, a plain-conv U-Net trainer, exports to Core AI (`.aimodel`) and Core ML
(`.mlpackage`, insurance), the export checks, and a committed synthetic fixture.
The app gets one asset and one inference class at step 4; nothing here touches
`Core/`, `UI/` or `AppState`.

## Environments (two, on purpose)

| Environment | Used for | Pinned |
|---|---|---|
| `$HOME/miniconda3/envs/py4dstem` (py4DSTEM 0.14.17, python 3.12.4) | the reference detector in `verify_fixture.py` and `evaluate.py` — only to call py4DSTEM | `tools/lib/python.sh` resolves it |
| `$HOME/miniconda3/envs/disk-detector` (python 3.12) | `train.py`, `export.py`, `check_export.py` | `requirements.txt` (2026-09-06: torch 2.11.0 — coreai-opt 0.2.1 pins it — numpy 2.3.5, coremltools 9.0, coreai-torch 0.4.2 + coreai-core 1.0.0b2 + coreai-opt 0.2.1, tensorboard 2.21.0) |

`simulate.py` imports in both (numpy + scipy only). Run `tools/free-space.sh`
before installing anything; the machine runs near its disk floor.

## Conventions

A centre is `(row, col)` — py4DSTEM's `(qx, qy)`, axis 0 first — everywhere,
so the fixture is checked against `find_Bragg_disks` without a transpose.
Inputs are three channels at 128×128: log-scaled normalised pattern, the given
probe, and the flat-kernel cross-correlation (`simulate.model_inputs` is the one
normalisation; step 4 reproduces it in Swift). The correlation is py4DSTEM's
`get_probe_kernel_flat` + `get_cross_correlation` ported line for line
(`simulate.flat_kernel`, `simulate.cross_correlation`) and checked against the
originals on every fixture run — the app's Metal engine matches that route at
peak level (878/878, `docs/status.md`).

## Modes

```sh
tools/disk-detector/run.sh            # fixture — gated, seconds, no real data, no network
tools/disk-detector/run.sh train …    # diagnostic: on-the-fly simulation on the real probes, MPS
tools/disk-detector/run.sh export …   # .aimodel via coreai-torch, .mlpackage via coremltools
tools/disk-detector/run.sh check …    # each export vs PyTorch on the same inputs
tools/disk-detector/run.sh evaluate … # step 3 numbers: fixture, real cubes vs classical
```

Real ingredients (owner-local, gitignored, read-only, absolute paths):
`References/training_dataset/calibrationData_bullseyeProbe.h5` (the measured
bullseye probe, `probe_template` slice 0, centre of mass (124.76, 124.74)) and
`polycrystal_2D_WS2.h5` (no probe inside; the central disk of a mean pattern
stands in, `simulate.load_ws2_probe`). Run outputs go to
`References/training_runs/disk-detector-<date>/`.

## The fixture (`fixture/`)

16 patterns, 128×128, uint16, seed 20260906, a DRAWN bullseye probe (soft disk
with a cosine ring, fractional centre (63.6, 64.3)), a drawn background, no real
data — 254 KB committed so a reader needs nothing else; `simulate.py fixture`
regenerates it and `expected.json` carries the patterns' SHA-256, the config and
every truth centre. `verify_fixture.py` (py4DSTEM env) passes only if the port
parity holds (relative difference ≤ 1e-9) AND py4DSTEM's classical detector at
the 2026-09-05 bullseye settings (flat kernel, minPeakSpacing 8, edgeBoundary 6,
minRelativeIntensity 0.05, sigma_cc 2, poly) recovers ≥ 90 % of the eligible
truth (relative intensity ≥ 0.1, ≥ 8 px from the edge) within 1.5 px with a
median matched residual ≤ 0.5 px. The default `run.sh` then breaks the fixture
four ways — truth shifted 3 px, axes swapped, three disks dropped from the
render but kept in the truth, the probe rolled by (4, −3) — and requires each
to fail. First proof 2026-09-06: 148/153 = 0.967 within 1.5 px, median residual
0.244 px; every break failed (recall 0.000 / 0.026 / 0.699 / 0.000). The five
misses are the classical detector's own: a tilted ring disk pulls its
correlation peak by about a pixel and ring ridges from neighbours swallow faint
disks — the failure class the net is for. The fixture's lattice spacing is
≥ 2 disk radii and its intensity falloff gentle on purpose: overlapping and
near-extinct disks are training material, not a proof of geometry.

## Step 2 — the net, the exports, the checks (2026-09-06/07)

`train.py`: U-Net, four levels, width × (1, 2, 4, 8) channels (width 24 →
1.1 M parameters), conv/BN/SiLU, max-pool, nearest upsample + concat, sigmoid
head; loss `mean((1 + 20·target)·(pred − target)²)` so a missed bump costs
more than a false one. On-the-fly simulation (six worker processes) from the
measured bullseye probe (55 %), the WS₂ stand-in (30 %) and the drawn probe
(15 %), real radial backgrounds from both cubes 70 % of the time. MPS.
Validation: 128 held-out simulated samples and the committed fixture, recall
and precision of numpy peak-picking (3×3 local maxima above 0.3, top 70)
within 2 px. TensorBoard: `tensorboard --logdir References/training_runs/`.

`export.py`, three function variants per batch size, one `.aimodel` each:
`detect` (heatmap + in-graph top-K = 70 peaks: `heatmap == maxpool3×3`,
`> threshold`, `topk`, `(row, col)` from the flat index without a remainder
op — coreai-torch 0.4.2 has no lowering for `aten.remainder`), `scoremap`
(heatmap + peak-masked score map, no top-k) and `heatmap` alone. Pipeline:
`torch.export` → `run_decompositions(get_decomp_table())` → coreai-opt
`cast_fp32_to_fp16` → `TorchConverter` → `to_coreai()` → `optimize()` →
`save_asset`. The probe-as-state attempt is a fourth asset: `set_probe`
writes a model buffer in place, `detect` reads it and takes two channels.
Core ML insurance: `torch.jit.trace` → `coremltools.convert` (float16,
macOS 15 target) with the same three outputs. `export.json` carries the
SHA-256 of every asset — the weights hash provenance will record.

`check_export.py`: the fixture plus simulated inputs through PyTorch float32
(reference) and float16 (the floor), then every Core AI asset under
`SpecializationOptions` Neural Engine preferred, CPU only and GPU preferred —
**each in a subprocess**, because a Neural Engine program-load failure kills
the process — with first-load specialisation time, per-batch and per-pattern
time, max |diff| of the heatmap, and whether the in-graph peaks equal numpy's;
then the `.mlpackage` through coremltools' predict. It runs through
macOS 27's own runtime (`USE_OS_COREAI=1`; the in-package runtime has no
compute-unit delegates).

`evaluate.py` (step 3) runs in two stages because torch and py4DSTEM live in
different environments: `--stage net` (detector env) writes heatmaps for the
fixture and every stride-th position of the two real cubes; `--stage compare`
(py4DSTEM env) applies py4DSTEM's `poly` sub-pixel refinement on the
flat-kernel correlation at each candidate (standing in for the Metal engine),
matches to the drawn centres (fixture) and to `find_Bragg_disks` at the
2026-09-05 settings (real cubes), and saves PNGs of disagreeing patterns.

**Numbers (2026-09-07, `References/training_runs/disk-detector-2026-09-06/`,
the full account is `docs/v3-plan.md` §3a "Step 3 — evidence").** run1: 9 500
steps in 80 min, best validation loss 0.0526, validation recall@2 px 0.80,
fixture recall 1.000; run2 (a 55-min anneal from run1, the checkpoint of
record, asset `0df112f4f593…`): validation loss 0.0473, recall 0.82, ANE
0.363 ms per pattern, 98.2 % of numpy's peaks in-graph. Neural Engine, `detect` B32: 0.344 ms per pattern
(22.6 s per 65 536), first load 3.3 s, 98.6 % of numpy's peaks reproduced
in-graph; CPU-only 14.4 ms, GPU-preferred 1.45 ms (and half the peaks — a
GPU-delegate top-k defect); the probe-as-state asset segfaults on load; a
top-k graph failed the ANE program load once inside a torch-importing process
(hence the subprocess check). Classical stand-in 0.602 ms per pattern
(`tools/performance-baseline/bench.json`, 2026-08-27): the net alone is 0.57×,
the whole learned path ≤ 1.57×, under the 2× ceiling. On the real bullseye
crop the net marks every visible disk and, at threshold 0.3, ~65 background
peaks per position (5 at 0.9); WS₂ is float-normalised so `log1p` is linear
on it — step 4 must scale float cubes into counts first.

## 2026-09-07 revisions (after the morning review; `docs/status.md` handoff)

- **Targets.** `simulate.disk_visibility`: a truth centre's bump amplitude is its
  visibility in [0, 1] — an integrated Poisson signal-to-noise ramp (0 at SNR 2,
  1 at 8) times a display-contrast ramp on the net's own log-normalised input
  (disk mean minus the 20th percentile of a 1.3–1.9 R annulus; 0 at 2 %, 1 at
  10 % of the range). Extinct and faint reflections stay in `Sample.centres`
  (the truth) but no longer teach the lattice. The ramps are a judgment,
  checked by eye on `disk-detector-2026-09-07/visibility-eye-check.png` (owner-local), not a measurement. Validation
  recall is against visible centres (≥ 0.5). The fixture is unchanged (SHA
  identical; every drawn disk is amplitude 1).
- **Backgrounds.** `simulate.radial_background(textured=True, kernel, radius)`:
  the azimuthal median plus the pattern's own residual texture, with every
  correlation-detected disk and the beam cut to 1.5 R and refilled with
  Poisson-scale noise, and the beam cut from the profile too. The 2026-09-06
  medians were texture-free by construction; the net had never seen the
  texture it fired on. `collect_real_backgrounds(probes=…)` builds them;
  `References/training_runs/disk-detector-2026-09-07/ingredients.npz` (192).
- **Evaluation.** `evaluate.py --asset <.aimodel>` takes the heatmaps from the
  EXPORTED asset (Neural Engine, subprocess) instead of PyTorch; `accept()`
  applies an acceptance rule after refinement — edge exclusion and greedy
  non-maximum suppression at `minPeakSpacing` by net score, the same spacing
  rule the classical side obeys; no correlation-relative cut — and the fixture
  is scored at 0.3/0.5/0.7/0.9 in one run (`fixture_by_threshold`).
- **Width.** Untrained nets timed on the Neural Engine (`scoremap` B32, the
  serving shape; weights do not change the cost): width 12 (275 k params)
  0.139 ms/pattern = 9.1 s per 65 536; width 16 (489 k) 0.178 ms = 11.6 s;
  width 24 (1.1 M) 0.276 ms (2026-09-06 check). run3 trains width 12.
- **The ceiling, from Swift.** `scan-bench/` (`run.sh dump`, `run.sh bench`)
  times the app's own scan path (`DiskDetection.detectAll`, all cores) and the
  exported asset through the CoreAI framework on identical bullseye patterns —
  the comparison the 2026-09-06 numbers lacked (they used the serial
  single-pattern benchmark as the baseline).

**run3 numbers (2026-09-07, `References/training_runs/disk-detector-2026-09-07/`):**
width 12, 20 000 steps, 72.8 min, best validation loss 0.0052, recall@2 px
0.963 / precision 0.78 (visible truth), fixture recall 1.000. Exported
`heatmap`/`scoremap` B32 assets (`export.json` hashes): ANE 0.138 / 0.173
ms per pattern from Python, heatmap max |diff| vs PyTorch fp32 0.062 (fp16
floor 0.009), CPU-only 6.5 ms. `scan-bench` on 2 100 bullseye patterns
(stride 2, Release, `scan-bench-run5…8-gateB.log`): classical `detectAll`
8 cores 0.105–0.113 ms/pattern (3.16 peaks per pattern); the `heatmap` asset
via CoreAI.framework, input construction included, 0.13–0.156 ms/pattern,
load 0.9–1.4 s; the learned `detectAll` end to end 0.212 ms/pattern =
1.87–1.99× (2.94 peaks per pattern at 0.9). Evaluation of the exported asset
with the acceptance rule after Gate B — bullseye net − classical per
position: 0.9 → median 0 (416 vs 442, no pair beyond 0.5 px), 0.6 → median
0 (501 vs 442); fixture 0.967 / 0.244 px refined at every threshold, 241
accepted, precision 0.61; WS₂ as stored equals classical.

- **Step 4 slice 1 (Swift).** `fixture/write_swift_fixture.py` writes
  `fixture/swift/` (the 16 patterns as uint16, the probe, Python's model
  inputs for two patterns, and per pattern the raw picks and the accepted
  refined peaks from the committed asset `Models/DiskDetector/`); the app's
  `mac4DSTEMTests/LearnedDiskDetectorTests` reproduces all of it through
  `Core/ML/LearnedDiskDetector`. `evaluate.refine` now applies the parabolic
  shift unguarded like py4DSTEM and the app (a non-finite shift is not
  applied), and rejects a candidate whose snapped pixel is not a local
  maximum (Gate B: py4DSTEM's precondition; it fabricated 10 of 255 fixture
  peaks before). Trap: the Python runtime and the Swift CoreAI framework
  share `~/Library/Caches/coreai-cache` and each fails to load on the ANE
  after the other has written it (a generic ObjC error) — move the cache
  aside whenever switching. `scan-bench` also times `LearnedDiskDetector.
  detectAll` end to end and, with `SCAN_BENCH_PROFILE=1`, each stage.

abTEM honesty check: skipped 2026-09-06. The existing `abtem` conda env does not
import (numpy's `libgfortran.5.dylib` missing) and a reinstall would eat the disk.

## Retraining — when and how

Coverage of a larger detector is NOT a reason — the app tiles 128-px windows
(decided 2026-09-07, `docs/status.md`), so a bigger detector is more tiles.
Reasons: a disk-size regime outside `SimConfig.zoom` (0.6–1.4× the probe
radius, ~7–15 px at 128 px — binning a 250-px detector 2× puts the bullseye
disks at ~3.7 px, below the trained range: widen `zoom` and retrain, don't
extrapolate); a new probe family (`load_ingredients`'s three-probe mix gets
a fourth); a larger input (256 px, about four times the pixels, so roughly four times the Neural Engine cost (an estimate, not a measurement) — a new `S`, a new net,
new assets, not a drop-in); or the owner's confirmed/rejected patterns from
the app (step 5, `docs/v3-plan.md` §3a) — fine-tune with `--resume`.

### Recipe

```sh
run.sh train --ingredients <npz> \
  --out References/training_runs/disk-detector-<date>/runN --width 12 --max-minutes 90
#   fine-tuning: add --resume runN/best.pt, fold the owner's patterns into <npz>
#   new regime: widen SimConfig.zoom, add a probe to load_ingredients, or bump S — before running

run.sh export --run … --variants heatmap --batches 32 --threshold 0.9 --skip-coreml --skip-stateful
run.sh check --run … --prefer ane cpu --skip-coreml
run.sh evaluate --run … --asset <heatmap .aimodel> --threshold 0.9

fixture/write_swift_fixture.py --asset <heatmap .aimodel> --threshold 0.9
#   then copy the asset + a regenerated record JSON (Models/DiskDetector/*.json fields) in
```

One heavy job at a time on this 8 GB Mac — a training run beside an ANE
timing crashed it. Move `~/Library/Caches/coreai-cache` aside when switching
between the Python runtime and the Swift framework — each fails to load on
the ANE after the other has written it.

### Before a new asset ships

The fixture gate green (`run.sh`); `mac4DSTEMTests/LearnedDiskDetector*` and
`LearnedDiskDetectionScanTests` green against the regenerated Swift fixture;
the SHA-256 in the record JSON equal to `export.py`'s `sha256_tree` of the
asset; the numbers in `docs/status.md` re-run (bullseye evaluate at 0.9, the
scan-bench); Gate B at the merge. Every retrain is a new hash — old results
keep saying which weights made them (`learned_model_sha256` in provenance).
