#!/bin/zsh
# v2 S2 (docs/v2-release.md §8): the two-spec analysis fixture — the evidence
# for the release claim's word "unchanged". An analysis run on a reduced view
# must reproduce the full-extent run restricted to the overlap. See the header
# of main.swift for the four invariances and for why the comparison is `==`.
#
# Two firsts, both deliberate:
#   - the source list comes from tools/lib/sources.manifest, not from a
#     hand-written list in this file (../_archive/mac4DSTEM/docs/archive/development-process-2026-08-31.md §1);
#   - the harness compiles with the APP's actor-isolation flags, closing the
#     blind spot recorded on 2026-08-18 where every tools/ harness validated
#     different isolation semantics from the app.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-two-spec-analysis-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

# libhdf5 is FormatoKit's framework (already ad-hoc signed), loaded in place: nothing is copied or re-signed.
HDF5_FRAMEWORKS="$("$REPO/tools/lib/hdf5-dir.sh")"   # FormatoKit's three frameworks, side by side
HDF5_LIB="$HDF5_FRAMEWORKS/FormatoLibHDF5.framework/FormatoLibHDF5"
export FORMATO_HDF5_PATH="$HDF5_LIB"   # FormatoKit's own loaders (Velox reader, FormatoHDF5) read this; the app's H5Reader, writer and shims read it too (FormatoKit's lookup order)

"$PYTHON_BIN" reference.py "$WORK"

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main, and
# both the virtual detector and the resident cube allocate through it. Build the
# app's real shader sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

mac4dstem_sources "$REPO" readers calibration analysis

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  "${MAC4DSTEM_SOURCES[@]}" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader finds libhdf5 through FORMATO_HDF5_PATH above (FormatoKit's framework, see tools/lib/hdf5-dir.sh); MAC4DSTEM_HDF5_PATH is no longer read by the app.
export MAC4DSTEM_HDF5_PATH="$HDF5_LIB"
cd "$WORK"
./harness "$WORK"
