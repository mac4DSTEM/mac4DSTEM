#!/bin/zsh
# Fit-verification overlay geometry: inverse calibration mapping, strain
# lattice overlay, matched-ACOM-template overlay, origin/ellipse conventions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" \
  "$ROOT/tools/fit-overlay-test/main.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$ROOT/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$ROOT/mac4DSTEM/Core/Data/Calibration.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT1D.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/OrientationResult.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/StrainMapping.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/FitOverlays.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/ScatteringFactors.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/Crystal.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/OrientationPlan.swift" \
  "$ROOT/mac4DSTEM/Core/Crystal/OrientationMatcher.swift" \
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
./harness
