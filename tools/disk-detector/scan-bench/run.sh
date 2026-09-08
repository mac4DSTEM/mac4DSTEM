#!/bin/zsh
# tools/disk-detector/scan-bench/run.sh — DIAGNOSTIC (owner-local data, never gated): the ceiling of
# docs/v3-plan.md §3a measured from Swift on the runtime that ships — Core ML at 256 px (C7 session 3,
# 2026-09-08; the Core AI version of this bench stays on `ml/disk-detector`).
#   run.sh dump  --bullseye <h5> --ingredients <npz> --out <dir> [--stride 4]
#   run.sh bench <dump dir> [<asset.mlpackage>]     default asset: the shipped Models/DiskDetector package
# `bench` compiles main.swift against the production detection sources (tools/lib/sources.manifest's
# `detection` list, the same one tools/disk-detection-test uses) plus Core/ML/LearnedDiskDetector.swift,
# then times the app's classical scan path and the learned path end to end on the same patterns.
# Each run appends scan-bench-<timestamp>.json to the dump dir (never overwritten).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
mode="${1:-}"; shift || true
case "$mode" in
  dump) exec "${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}" dump.py "$@" ;;
  bench)
    [[ $# -ge 1 ]] || { echo "usage: $0 bench <dump dir> [<asset.mlpackage>]" >&2; exit 64; }
    . "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
    . "$REPO/tools/lib/sources.manifest"; mac4dstem_sources "$REPO" detection
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/scan-bench" main.swift \
      "${MAC4DSTEM_SOURCES[@]}" \
      "$REPO/mac4DSTEM/Core/ML/LearnedDiskDetector.swift" \
      -framework Accelerate -framework Metal -framework CoreML
    exec "$WORK/scan-bench" "$1" "${2:-$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage}" ;;
  *) echo "usage: $0 dump|bench ..." >&2; exit 64 ;;
esac
