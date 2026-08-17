#!/bin/zsh
# Non-gating CPU/Metal baseline. Record same-machine trends; never fail a build
# on wall-clock time. Set MAC4DSTEM_BENCHMARK_REPEATS/WARMUPS to tune duration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -O -parse-as-library -o "$WORK/baseline" \
  "$ROOT/tools/performance-baseline/main.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$ROOT/mac4DSTEM/Core/Data/Calibration.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDArray.swift" \
  "$ROOT/mac4DSTEM/Core/Data/ResidentCube.swift" "$ROOT/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT1D.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/VirtualDetector.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/SingleslicePtychography.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/OrientationResult.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/ScatteringFactors.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/Crystal.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/OrientationPlan.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/OrientationMatcher.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
cd "$WORK"
# Keep stdout valid JSON despite MetalEngine's one-line device diagnostic.
./baseline | sed '/^\[MetalEngine\]/d'
