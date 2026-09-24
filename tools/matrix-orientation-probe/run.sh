#!/bin/zsh
# Gate D instrument: why the matrix loses on the real Al-Mg-Si cube
# (docs/archive/v4/almgsi-gateD-2026-09-24.md). See main.swift's header.
#
# `diagnostic` deliberately: it needs a machine-local datacube that is not in
# the repo, and it measures a DATASET, not an invariant of the code.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-matrix-orientation-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
# `core` is every Core/ source (origin fit, detection, calibration, the
# phase-vector matcher); the others are listed for what they name.
mac4dstem_sources "$REPO" phasevectors readers crystal core

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift "${MAC4DSTEM_SOURCES[@]}" "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit \
  -Xcc -DACCELERATE_NEW_LAPACK
codesign -f -s - "$WORK/probe" 2>/dev/null

# Pass absolute paths: the script cd-s to its own directory first.
cube="${1:A}"; shift
args=()
while (( $# )); do
  case "$1" in
    --csv|--overlay) args+=("$1" "${2:A}"); shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/probe" "$cube" "${args[@]}" | grep -v '^\[MetalEngine\]'
