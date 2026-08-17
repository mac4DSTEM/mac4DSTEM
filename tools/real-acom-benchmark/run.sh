#!/bin/zsh
# Real-data ACOM CPU/Metal comparison. This intentionally includes production
# origin calibration and Bragg detection so the matcher sees real peak lists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$ROOT/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

SRC="$ROOT/mac4DSTEM/Core"
xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "$SRC/Data/HDF5Types.swift" "$SRC/Data/H5Reader.swift" \
  "$SRC/Data/DatasetDescriptor.swift" "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" "$SRC/Data/ResidentCube.swift" "$SRC/Data/LoadSpecification.swift" \
  "$SRC/Data/Calibration.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT1D.swift" \
  "$SRC/Compute/FFT2D.swift" "$SRC/Compute/MatrixDFTCorrelation.swift" \
  "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/DiskDetection.swift" \
  "$SRC/Analysis/TiledDiskDetection.swift" "$SRC/Analysis/VirtualDetector.swift" \
  "$SRC/Analysis/OriginCalibration.swift" "$SRC/Analysis/QCalibration.swift" \
  "$SRC/Analysis/OrientationResult.swift" \
  "$SRC/Crystal/ScatteringFactors.swift" "$SRC/Crystal/Crystal.swift" \
  "$SRC/Crystal/OrientationPlan.swift" "$SRC/Crystal/OrientationMatcher.swift" \
  "$ROOT/tools/real-acom-benchmark/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

DATASET="${1:-$ROOT/References/training_dataset/058_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5}"
DATASET="${DATASET:A}"
if [[ ! -f "$DATASET" ]]; then
  echo "SKIP: real ACOM dataset is absent: $DATASET"
  exit 0
fi
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "$DATASET" \
  | sed '/^\[MetalEngine\]/d'
