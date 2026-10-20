#!/bin/zsh
# Which node discovery returns (Gate D 2026-09-04, the rank-3 class). Fixtures
# from reference.py; the harness compiles only the reader.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-datacube-discovery-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# libhdf5 is FormatoKit's framework (already ad-hoc signed), loaded in place, as in every reader harness.
HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader, writer and shims read it too (FormatoKit's lookup order)

"$PYTHON_BIN" reference.py "$WORK/fixtures"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers cube calibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

MAC4DSTEM_HDF5_PATH="$HDF5_LIB" "$WORK/harness" "$WORK/fixtures"
