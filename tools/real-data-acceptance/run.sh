#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

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
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" "$SRC/Data/Calibration.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT2D.swift" \
  "$SRC/Compute/MatrixDFTCorrelation.swift" "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/DiskDetection.swift" \
  "$SRC/Analysis/TiledDiskDetection.swift" "$SRC/Analysis/VirtualDetector.swift" \
  "$ROOT/tools/real-data-acceptance/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

files=("$ROOT"/References/training_dataset/*.h5(N))
if (( ${#files} == 0 )); then
  echo "SKIP: no checked-in real-data acceptance files"; exit 0
fi
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "${files[@]}" > report.json
if [[ -n "${MAC4DSTEM_REAL_REPORT_OUTPUT:-}" ]]; then
  cp report.json "$MAC4DSTEM_REAL_REPORT_OUTPUT"
fi
python3 "$ROOT/tools/real-data-acceptance/compare.py" \
  "$ROOT/tools/real-data-acceptance/expected.json" report.json
