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
fixture recall 1.000. Neural Engine, `detect` B32: 0.344 ms per pattern
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

abTEM honesty check: skipped 2026-09-06. The existing `abtem` conda env does not
import (numpy's `libgfortran.5.dylib` missing) and a reinstall would eat the disk.
