#!/bin/zsh
# Production strain solver: whole-scan versus user-selected reference region.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

xcrun swiftc -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DPC.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/QCalibration.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/StrainMapping.swift" \
  -framework Accelerate -framework Metal

"$WORK/harness"
