#!/bin/zsh
# Step 4: vector-matched phase mapping on a real Al-Mg-Si cube, through the
# app's own detector, library and matcher. See main.swift's header for the
# resolution question it asks before drawing anything, and for the
# pre-registered prediction.
#
# `diagnostic` deliberately: it needs a machine-local datacube that is not in
# the repo, and what it produces is a measurement about a DATASET, not an
# invariant of the code. The invariants are in tools/phase-vector-matching.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-phase-map-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" phasevectors readers

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift thronsen.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit \
  -Xcc -DACCELERATE_NEW_LAPACK
codesign -f -s - "$WORK/probe" 2>/dev/null
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/probe" "$@" | grep -v '^\[MetalEngine\]'
