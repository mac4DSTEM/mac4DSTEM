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

abTEM honesty check: skipped 2026-09-06. The existing `abtem` conda env does not
import (numpy's `libgfortran.5.dylib` missing) and a reinstall would eat the disk.
