#!/bin/zsh
# tools/disk-detector/scan-bench/run.sh — DIAGNOSTIC (owner-local data, never gated): the ceiling of
# docs/archive/v3/learned-detector-preregistration-2026-09-07.md (was docs/v3-plan.md §3a) measured from Swift on the runtime that ships — Core ML at 256 px (C7 session 3,
# 2026-09-08; the Core AI version of this bench stays on `ml/disk-detector`).
#   run.sh dump  --bullseye <h5> --ingredients <npz> --out <dir> [--stride 4]
#   run.sh dump  --h5 <h5> --dataset <path> --out <dir> [--stride N] [--max-positions N]   any cube, probe built from the data (see dump.py)
#   run.sh bench <dump dir> [<asset.mlpackage>] [--units ane|all|gpu|cpu] [--peaks <file.json>]
#                default asset: the shipped Models/DiskDetector package; default units ane (.cpuAndNeuralEngine);
#                an asset argument is the 2nd positional, so flags alone may also follow the dump dir
# `bench` compiles main.swift against the production detection sources (tools/lib/sources.manifest's
# `detection` list, the same one tools/disk-detection-test uses) plus Core/ML/LearnedDiskDetector.swift,
# then times the app's classical scan path and the learned path end to end on the same patterns.
# Each run appends scan-bench-<timestamp>.json to the dump dir (never overwritten); --peaks also writes the accepted peaks
# of every position. SCAN_BENCH_KEEP=<path> keeps the compiled binary, SCAN_BENCH_BIN=<path> reuses it (skips the compile;
# for a series of timed runs). (compare_peaks.py A.json B.json compares two such files).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
mode="${1:-}"; shift || true
case "$mode" in
  dump) exec "${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}" dump.py "$@" ;;
  bench)
    [[ $# -ge 1 ]] || { echo "usage: $0 bench <dump dir> [<asset.mlpackage>] [--units ane|all|gpu|cpu] [--peaks <file.json>]" >&2; exit 64; }
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    BIN="$WORK/scan-bench"
    if [[ -n "${SCAN_BENCH_BIN:-}" ]]; then BIN="$SCAN_BENCH_BIN"   # a binary kept by SCAN_BENCH_KEEP earlier
    else
      . "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
      . "$REPO/tools/lib/sources.manifest"; mac4dstem_sources "$REPO" detection
      xcrun swiftc -package-name mac4DSTEM -O -o "$BIN" main.swift \
        "${MAC4DSTEM_SOURCES[@]}" \
        "$REPO/mac4DSTEM/Core/ML/LearnedDiskDetector.swift" \
        -framework Accelerate -framework Metal -framework CoreML
      if [[ -n "${SCAN_BENCH_KEEP:-}" ]]; then cp "$BIN" "$SCAN_BENCH_KEEP"; fi   # keep the binary for SCAN_BENCH_BIN reuse
    fi
    DIR="$1"; shift
    ASSET="$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage"
    if [[ $# -ge 1 && "$1" != --* ]]; then ASSET="$1"; shift; fi
    "$BIN" "$DIR" "$ASSET" "$@" ;;
  *) echo "usage: $0 dump|bench ..." >&2; exit 64 ;;
esac
