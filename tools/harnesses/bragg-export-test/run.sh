#!/bin/zsh
# Native Swift write -> checked-in py4DSTEM 0.14.19 read/semantic validation.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-bragg-export-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader, writer and shims read it too (FormatoKit's lookup order)

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" export
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null

cp "$REPO/tools/harnesses/calibration-test/real_py4dstem.h5" "$WORK/source.h5"
export MAC4DSTEM_HDF5_PATH="$HDF5_LIB"
"$WORK/harness" "$WORK/export.h5" "$WORK/cancelled.h5" "$WORK/source.h5"

PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  "$PYTHON_BIN" \
  verify_py4dstem.py "$WORK/export.h5"
