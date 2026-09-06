#!/bin/zsh
# tools/disk-detector/scan-bench/run.sh — DIAGNOSTIC (owner-local data, macOS 27, Xcode-beta):
#   run.sh dump  --bullseye <h5> --ingredients <npz> --out <dir> [--stride 2]
#   run.sh bench <dump dir> [<asset.aimodel> <function>]
# Compiles main.swift against the production Core sources (the same list as tools/disk-detection-test)
# plus the CoreAI framework, then times the app's classical scan path and the asset on the same patterns.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
mode="${1:-}"; shift || true
case "$mode" in
  dump) exec "${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}" dump.py "$@" ;;
  bench)
    . "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    xcrun swiftc -package-name mac4DSTEM -O -target arm64-apple-macos27.0 -o "$WORK/scan-bench" \
      main.swift \
      "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
      "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
      "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
      "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
      "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
      "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
      "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
      "$REPO/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
      "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
      "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
      -framework Accelerate -framework Metal -framework CoreAI
    exec "$WORK/scan-bench" "$@" ;;
  *) echo "usage: $0 dump|bench ..." >&2; exit 64 ;;
esac
