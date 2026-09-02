#!/bin/zsh
# Gate B, 2026-08-28: the resident fast path on a CROPPED + BINNED view, where
# `descriptor.rx` is NOT the source scan width and a resident "scan row" is not
# a whole source scan row.
#
# WHY THIS EXISTS AS A SEPARATE HARNESS. `tools/virtual-detector-residency`
# builds every array at full extent, where `descriptor.rx == source.rx`, so it
# is structurally blind to this class: mutating `FourDArray.swift`'s pattern
# slice from `descriptor.rx` to `view.source.rx` leaves all 27 of its
# assertions GREEN. This harness goes red at view (1, 0). Demonstrated by the
# Gate B second reader, 2026-08-28, and adopted here from its probe.
#
# Ground truth is computed by explicit source-coordinate arithmetic, NOT through
# `LoadView`'s `fromFullCube` helpers, so a shared convention error between the
# reader and the view cannot cancel — the L3 self-consistency trap that
# `virtual-detector-residency` documents in its own pattern loop.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
# Build the app's real shader sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDArray.swift" \
  "$REPO/mac4DSTEM/Core/Data/ResidentCube.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/VirtualDetector.swift" \
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
./harness
