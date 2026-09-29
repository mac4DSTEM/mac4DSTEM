#!/bin/zsh
# tools/mpsgraph-training-spike — ADR 048 phase C (2026-09-30), a DIAGNOSTIC: never gates. An MPSGraph mirror of the learned
# disk detector's training step, run against the shipped Core ML package. System frameworks only: no package, no xcodebuild,
# one `xcrun swiftc -O` into a temp dir that is removed on exit. It does not use tools/lib/sources.manifest: it compiles
# no Core/ source (the graph and the weight reader are its own), so there is no group to name.
#   run.sh <scratch dir> [steps=50]     env: SPIKE_MODE (forward|train; unset = forward, then train, as two processes)
#                                       SPIKE_DTYPE (f32|f16|bf16) SPIKE_BATCH (2) SPIKE_ACCUM (4) SPIKE_LR (1e-4)
# Exports the fixed training/held-out/fixture inputs once from tools/disk-detector (the detector env) into <scratch dir>,
# the same export as tools/mlx-training-spike/run.sh (seeds 20260928 / 999); reuses them when <scratch dir>/data.json exists.
# Needs References/training_runs/disk-detector-2026-09-08 (owner-local). Criterion 1 loads Core ML, so it runs in its own
# process: the memory numbers of the train process never include a Core ML model. One heavy job at a time on the 8 GB Mac.
set -euo pipefail
cd "$(dirname "$0")"; REPO="$(cd ../.. && pwd)"
OUT="${1:?usage: run.sh <scratch dir> [steps]}"; STEPS="${2:-50}"; mkdir -p "$OUT"
R="$REPO/References/training_runs/disk-detector-2026-09-08"
DET="${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}"
PKG="$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage"

# preflight: >= 1.5 GB free and no compiler / xcodebuild running (exact process names: MCP helpers named xcodebuildmcp do not count)
free_mb=$(df -m / | awk 'NR==2{print $4}')
(( free_mb >= 1536 )) || { echo "run.sh: only ${free_mb} MB free on /; need 1536 (tools/free-space.sh)" >&2; exit 69; }
for _ in {1..6}; do pgrep -x "xcodebuild|swift-frontend|swiftc" >/dev/null || break; sleep 10; done
! pgrep -x "xcodebuild|swift-frontend|swiftc" >/dev/null || { echo "run.sh: a build is running; retry later" >&2; exit 75; }

if [[ ! -f "$OUT/data.json" ]]; then
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
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/mps-spike.XXXXXX")"; trap 'rm -rf "$T"' EXIT
xcrun swiftc -O -swift-version 5 Sources/main.swift -o "$T/mps-spike" -framework CoreML -framework Metal -framework MetalPerformanceShadersGraph
if [[ -n "${SPIKE_MODE:-}" ]]; then "$T/mps-spike" "$PKG" "$OUT" "$STEPS"
else SPIKE_MODE=forward "$T/mps-spike" "$PKG" "$OUT"; SPIKE_MODE=train "$T/mps-spike" "$PKG" "$OUT" "$STEPS"; fi
