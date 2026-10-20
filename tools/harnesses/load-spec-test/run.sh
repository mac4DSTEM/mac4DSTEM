#!/bin/zsh
# Stage L3 (docs/load-pipeline-plan.md): a cropped read must equal the
# corresponding slice of a full read, EXACTLY, on every reader. See the header
# of main.swift for why the comparison is `==` and why the expected values are
# computed here rather than asked of the reader a second time.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-load-spec-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# libhdf5 is FormatoKit's framework (already ad-hoc signed), loaded in place: nothing is copied or re-signed.
# (Same reason as tools/harnesses/calibration-test.)
HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader and writer read MAC4DSTEM_HDF5_PATH

"$PYTHON_BIN" reference.py "$WORK"

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main, and
# FourDArray's resident path allocates through it. Build the app's real shader
# sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers cube
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader finds libhdf5 through MAC4DSTEM_HDF5_PATH (FormatoKit's framework, see tools/lib/hdf5-dir.sh).
export MAC4DSTEM_HDF5_PATH="$HDF5_LIB"
cd "$WORK"
./harness "$WORK"
