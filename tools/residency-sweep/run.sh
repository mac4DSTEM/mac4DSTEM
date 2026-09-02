#!/bin/zsh
# Measures the residency knee (docs/load-pipeline-plan.md L2.3). NOT a gate and
# never will be: it needs a real multi-gigabyte datacube, which is gitignored.
# Same standing as tools/bragg-spacing-probe — a diagnostic you run deliberately.
#
#   tools/residency-sweep/run.sh /path/to/cube.h5 [repeats]
#
# Copy the dataset to local storage first. #30 measured ~3.3 MB/s over a NAS, so
# a sweep over a network mount measures the link rather than residency; the
# output prints preload MB/s so that is visible instead of silent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <cube.h5> [repeats]" >&2
  exit 64
fi
# Absolute before anything cds. This script runs the harness from $WORK (the
# metallib has to be beside the binary), so a relative dataset path would resolve
# against the wrong directory — the same defect open-items.md records for the
# 22 harnesses that sourced a helper by a $0-relative path after a cd.
DATASET="${1:A}"; shift

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$ROOT/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

SRC="$ROOT/mac4DSTEM/Core"
# No -parse-as-library: main.swift is top-level code with top-level `await`,
# which that flag forbids (it wants a @main type instead).
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" \
  "$SRC/Data/HDF5Types.swift" "$SRC/Data/H5Reader.swift" \
  "$SRC/Data/DatasetDescriptor.swift" "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" \
  "$SRC/Data/ResidentCube.swift" "$SRC/Data/LoadSpecification.swift" "$SRC/Data/Calibration.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/VirtualDetector.swift" \
  "$ROOT/tools/residency-sweep/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "$DATASET" "$@"
