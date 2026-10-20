#!/bin/zsh
# Stage L4 (docs/load-pipeline-plan.md): binning on read must reproduce
# py4DSTEM's bin_data_diffraction exactly — the sum, the edge-remainder crop and
# the Q_pixel_size rescale — with only the deviations that are written down.
# The arbiter is py4DSTEM itself, from References/py4DSTEM-dev. See the header of
# main.swift for why, and for why the comparison is `==` rather than a tolerance.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-preprocess-crop-bin-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# libhdf5 is FormatoKit's framework (already ad-hoc signed), loaded in place: nothing is copied or re-signed.
HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader and writer read MAC4DSTEM_HDF5_PATH

PYTHONPATH="$REPO/References/py4DSTEM-dev" "$PYTHON_BIN" reference.py "$WORK"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers calibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate

codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader finds libhdf5 through MAC4DSTEM_HDF5_PATH (FormatoKit's framework, see tools/lib/hdf5-dir.sh).
export MAC4DSTEM_HDF5_PATH="$HDF5_LIB"
cd "$WORK"
./harness "$WORK"
