#!/bin/zsh
# Stage L3 step 2 (docs/load-pipeline-plan.md): a re-referenced origin must land
# on the same physical feature as an origin measured on the cropped data, and a
# value that cannot be re-referenced must be invalidated rather than carried.
# See the header of main.swift for why this is not a self-consistency check.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
SRC="$REPO/mac4DSTEM/Core/Data"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main, and
# the origin measurement is a real GPU dispatch. Build the app's real shader
# sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "$SRC/DatasetDescriptor.swift" \
  "$SRC/DiffractionPattern.swift" \
  "$SRC/FourDDataSource.swift" \
  "$SRC/LoadSpecification.swift" \
  "$SRC/Calibration.swift" \
  "$SRC/CalibrationReReference.swift" \
  "$SRC/FourDArray.swift" \
  "$SRC/ResidentCube.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/VirtualDetector.swift" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
./harness
