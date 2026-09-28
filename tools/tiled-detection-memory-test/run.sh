#!/bin/zsh
# Memory-growth gate for the app's own tiled disk-detection path
# (DiskDetection.detectAll(data:)): phys_footprint must stay flat across tiles.
# Gate D 2026-09-29: without an autorelease pool per tile, GPU memory grew by
# about one tile per tile (docs/archive/v4/tiled-detection-memory-gateD-2026-09-29.md).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-tiled-detection-memory-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" analysis calibration
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
./harness
