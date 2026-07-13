#!/bin/zsh
# Bounded crop/Q-bin writer -> native and checked-in py4DSTEM validation.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

for library in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$library.dylib" "$WORK/"
  codesign -f -s - "$WORK/$library.dylib" 2>/dev/null
done

xcrun swiftc -parse-as-library -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/HDF5Types.swift" \
  "$REPO/mac4DSTEM/Core/Data/H5Reader.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
"$WORK/harness" "$WORK/calibrated.h5" "$WORK/cancelled.h5" 2>/dev/null

PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  /Users/paullobpreis/miniconda3/envs/py4dstem/bin/python \
  verify_py4dstem.py "$WORK/calibrated.h5"
