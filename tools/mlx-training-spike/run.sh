#!/bin/zsh
# tools/mlx-training-spike — ROADMAP C2 (2026-09-28), a DIAGNOSTIC: never gates. Exports the fixed
# training/held-out/fixture inputs once from tools/disk-detector (the detector env), builds the MLX
# spike with xcodebuild (SwiftPM from the command line cannot build MLX's Metal shaders, which is why
# MLX stays out of DSTEMCore), and runs it against the shipped Core ML package.
#   run.sh <scratch dir> [steps]          env: SPIKE_LR (1e-4), SPIKE_CACHE_MB, SPIKE_VAL_CHUNK (32)
#   SPIKE_REUSE=1 skips the export and the build when <scratch dir>/data.json and the binary exist (membench.sh uses it).
# Needs References/training_runs/disk-detector-2026-09-08 (owner-local). Record:
# docs/archive/v4/c2-mlx-spike-2026-09-28.md. One heavy job at a time on the 8 GB Mac.
# Nothing to take from tools/lib/sources.manifest: the spike compiles no Core/ file; it reads the shipped package.
# SPIKE_MODE=fallback reruns only the on-disk patched-package check against the last run's out dir.
set -euo pipefail
cd "$(dirname "$0")"; REPO="$(cd ../.. && pwd)"
OUT="${1:?usage: run.sh <scratch dir> [steps]}"; STEPS="${2:-500}"; mkdir -p "$OUT"
R="$REPO/References/training_runs/disk-detector-2026-09-08"
DET="${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}"
BIN="$OUT/dd/Build/Products/Release/mlx-spike"; REUSE=0
[[ "${SPIKE_REUSE:-0}" == 1 && -f "$OUT/data.json" && -x "$BIN" ]] && REUSE=1
if [[ $REUSE == 0 ]]; then
( cd "$REPO/tools/disk-detector" && "$DET" - "$OUT" "$R" <<'PY'
import sys, json, numpy as np, simulate as sm, train as tr
out, R = sys.argv[1], sys.argv[2]
cfg = sm.SimConfig(**json.load(open(f"{R}/run/config.json"))["config"]); meta = {}
def dump(n, a): a = np.ascontiguousarray(a, np.float32); a.tofile(f"{out}/{n}.f32"); return list(a.shape)
x, y, _ = tr.fixed_set(f"{R}/ingredients-256.npz", cfg, 20260928, 128); meta["train_x"], meta["train_y"] = dump("train_x", x.numpy()), dump("train_y", y.numpy())
x, y, _ = tr.fixed_set(f"{R}/ingredients-256.npz", cfg, 999, 32); meta["val_x"], meta["val_y"] = dump("val_x", x.numpy()), dump("val_y", y.numpy())
z = np.load("fixture/fixture.npz"); e = json.load(open("fixture/expected.json")); xs = []
for p in z["patterns"]:
    pf, probef, cf = sm.fit_fixture_to(p.astype(np.float64), z["probe"].astype(np.float64), tuple(e["probe_centre"]), cfg.size)
    xs.append(sm.model_inputs(pf, probef, sm.cross_correlation(pf, sm.flat_kernel(probef, cf))))
meta["fixture_x"] = dump("fixture_x", np.stack(xs)); json.dump(meta, open(f"{out}/data.json", "w"))
PY
)
xcodebuild build -scheme mlx-training-spike -destination 'platform=macOS,arch=arm64' -configuration Release \
  -derivedDataPath "$OUT/dd" -skipPackagePluginValidation > "$OUT/build.log" 2>&1
fi
"$BIN" "$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage" "$OUT" "$OUT/out" "$STEPS"
