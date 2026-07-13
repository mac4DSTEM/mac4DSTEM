#!/bin/zsh
# Non-gating CPU baseline. Record trends; never fail a build on wall-clock time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

xcrun swiftc -O -parse-as-library -o "$WORK/baseline" \
  "$ROOT/tools/performance-baseline/main.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/SingleslicePtychography.swift" \
  -framework Accelerate
"$WORK/baseline"
