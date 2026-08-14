#!/bin/zsh
# Compile and run the acom-groundtruth harness (see main.swift). Modeled on
# tools/training-dataset-campaign/run.sh, but with the minimal Core/ source
# set needed to link OrientationMatcher (no HDF5 reading, no metallib build:
# the CPU matcher never touches MetalEngine.shared, only its type).
#
# Usage: tools/acom-groundtruth/run.sh input.json > output.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

if (( $# < 1 )); then
  echo "usage: tools/acom-groundtruth/run.sh input.json > output.json" >&2
  exit 64
fi
INPUT="${1:A}"

SRC="$ROOT/mac4DSTEM/Core"
xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "$SRC/Data/DatasetDescriptor.swift" "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT1D.swift" \
  "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/OrientationResult.swift" \
  "$SRC/Crystal/ScatteringFactors.swift" "$SRC/Crystal/Crystal.swift" \
  "$SRC/Crystal/OrientationPlan.swift" "$SRC/Crystal/OrientationMatcher.swift" \
  "$ROOT/tools/acom-groundtruth/BraggTypes.swift" \
  "$ROOT/tools/acom-groundtruth/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

"$WORK/harness" "$INPUT"
