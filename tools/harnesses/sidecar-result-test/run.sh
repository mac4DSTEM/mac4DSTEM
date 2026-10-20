#!/bin/zsh
# Atomic BraggVectors + RealSlice merge, native reopen, and py4DSTEM round trip.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-sidecar-result-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" export

HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader and writer read MAC4DSTEM_HDF5_PATH

xcrun swiftc -package-name mac4DSTEM -module-cache-path "$WORK/module-cache" -o "$WORK/harness" \
  main.swift "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null

cp "$REPO/tools/harnesses/calibration-test/real_py4dstem.h5" "$WORK/source.h5"
export MAC4DSTEM_HDF5_PATH="$HDF5_LIB"
"$WORK/harness" "$WORK/session.mac4dstem.h5" "$WORK/source.h5"

PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  "$PYTHON_BIN" \
  inject_unknown.py "$WORK/session.mac4dstem.h5"

xcrun swiftc -package-name mac4DSTEM -module-cache-path "$WORK/module-cache" -parse-as-library \
  -o "$WORK/preserve-unknown" preserve_unknown.swift "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/preserve-unknown" 2>/dev/null
"$WORK/preserve-unknown" "$WORK/session.mac4dstem.h5"

PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  "$PYTHON_BIN" \
  verify_py4dstem.py "$WORK/session.mac4dstem.h5"
