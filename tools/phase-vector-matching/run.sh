#!/bin/zsh
# Vector-matched phase mapping: the reference library against arithmetic, and
# the matcher against planted truth. See main.swift's header for what stands in
# for ground truth here, and for the pre-registered pass criteria.
#
# `scientific` deliberately: unlike the one-off per-position template-matching
# probe that decided whether that route was viable at all (retired; answer in
# docs/archive/v4/tools-retired-2026-09-23.md), everything gated here is an
# invariant of shipped Core code.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-phase-vector.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" phasevectors

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main at
# init; without it the harness dies before main().
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
cd "$WORK" && "$WORK/harness"
