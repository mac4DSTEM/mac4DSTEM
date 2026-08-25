#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
for library in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$library.dylib" "$WORK/"
  codesign -f -s - "$WORK/$library.dylib" 2>/dev/null
done
xcrun swiftc -parse-as-library -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/HDF5Types.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift" \
  "$REPO/mac4DSTEM/Core/Data/SessionReplayRecord.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
"$WORK/harness" "$WORK/bundle.h5" "$WORK/cancelled.h5"
PYTHONPATH="$REPO/References/py4DSTEM-dev" "$PYTHON_BIN" verify.py "$WORK/bundle.h5"
