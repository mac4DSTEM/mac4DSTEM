#!/bin/zsh
# tools/q-shell-probe — Lane Q (v4.1 Slot 1). What does the app's known-crystal
# Q calibration actually read on a real cube: which ring it takes as the
# innermost allowed reflection, and what its own shell-ratio check says.
# `diagnostic`, not gated: it needs machine-local datacubes and measures
# DATASETS, not an invariant of the code. Nothing here changes an app number.
#
# usage: run.sh <cube.h5> --crystal al|au|ws2 [--truth-q Q] [--label NAME]
#               [--ellipse A B THETA_DEG] [--demo-truth truth.json]
#               [--tile-rows N] [--min-relative F]
# Build reuse for batch runs: Q_SHELL_PROBE_DIR=<dir> keeps the compiled
# harness there and skips the build while it is newer than main.swift;
# Q_SHELL_REBUILD=1 forces it (sources are not watched).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
KEEP="${Q_SHELL_PROBE_DIR:-}"
if [[ -n "$KEEP" ]]; then mkdir -p "$KEEP"; WORK="${KEEP:A}"
else WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-q-shell-probe.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT; fi
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

if [[ ! -x "$WORK/harness" || main.swift -nt "$WORK/harness" || -n "${Q_SHELL_REBUILD:-}" ]]; then
  . "$REPO/tools/lib/sources.manifest"
  mac4dstem_sources "$REPO" qcalibration acom
  for lib in libhdf5 libsz.2 libaec.0; do
    cp "$REPO/$lib.dylib" "$WORK/"
    codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
  done
  for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
    xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
  done
  xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"
  xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
    "${MAC4DSTEM_SOURCES[@]}" main.swift \
    -framework Accelerate -framework Metal -framework MetalKit
  codesign -f -s - "$WORK/harness" 2>/dev/null
fi

# Absolute paths: the script cd-s to its own directory first.
cube="${1:A}"; shift
args=()
while (( $# )); do
  case "$1" in
    --demo-truth) args+=("$1" "${2:A}"); shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
if [[ ! -f "$cube" ]]; then echo "SKIP: dataset is absent: $cube"; exit 0; fi
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "$cube" "${args[@]}" | grep -v '^\[MetalEngine\]'
