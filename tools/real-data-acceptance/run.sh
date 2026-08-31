#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Check the comparator before the app. compare.py is what turns this harness's
# measurements into a verdict, so a comparator that has quietly stopped checking
# is indistinguishable from a passing gate. Runs first, before the ~1 min build,
# so a broken comparator fails in under a second. Needs no data and no toolchain.
# It is also its own harness in run-tests.sh's `scientific` array, so CI runs it;
# this call is the fail-fast for the `all` path, which is the only one that
# reaches this harness at all.
"$ROOT/tools/comparator-test/run.sh"

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
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" "$SRC/Data/ResidentCube.swift" "$SRC/Data/LoadSpecification.swift" "$SRC/Data/Calibration.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT2D.swift" \
  "$SRC/Compute/MatrixDFTCorrelation.swift" "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/DiskDetection.swift" \
  "$SRC/Analysis/TiledDiskDetection.swift" "$SRC/Analysis/VirtualDetector.swift" \
  "$SRC/Analysis/OriginCalibration.swift" \
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
