#!/bin/zsh
# Compile and run the acom-groundtruth harness (see main.swift). Modeled on
# tools/training-dataset-campaign/run.sh, but with the minimal Core/ source
# set needed to link OrientationMatcher (no HDF5 reading, no metallib build:
# the CPU matcher never touches MetalEngine.shared, only its type).
#
# Usage: tools/acom-groundtruth/run.sh input.json > output.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-acom-groundtruth.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

if (( $# < 1 )); then
  echo "usage: tools/acom-groundtruth/run.sh input.json > output.json" >&2
  exit 64
fi
INPUT="${1:A}"

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" acom
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/acom-groundtruth/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

"$WORK/harness" "$INPUT"
