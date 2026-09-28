#!/bin/zsh
# Diffraction-groups timing probe (diagnostic, 2026-09-28). See main.swift.
# OPT=-O (default) or OPT=-Onone to compare optimised vs debug-like builds.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-embedding-profile.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$(basename "$source" .metal).air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" embedding
xcrun swiftc ${OPT:--O} -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -Xcc -DACCELERATE_NEW_LAPACK -framework Accelerate -framework Metal
codesign -f -s - "$WORK/probe" 2>/dev/null
shift 0
for args in "$@"; do "$WORK/probe" ${=args}; done
