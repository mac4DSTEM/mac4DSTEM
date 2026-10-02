#!/bin/zsh
# Memory-growth gate for the app's own tiled disk-detection paths: classical
# DiskDetection.detectAll(data:) and learned LearnedDiskDetector.detectAll(data:)
# (the shipped Core ML package): phys_footprint must stay flat across tiles.
# Gate D 2026-09-29: without an autorelease pool per tile, GPU memory grew by
# about one tile per tile (docs/archive/v4/tiled-detection-memory-gateD-2026-09-29.md).
# Built at -O, as DSTEMCore is in both app configurations: the learned mode at
# -Onone takes over ten minutes, and both A1 mutations (no pool: 321 MB; no
# exact-size copy: 153 MB) fail identically at -O and -Onone (S11, 2026-09-29).
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
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "$REPO/mac4DSTEM/Core/ML/LearnedDiskDetector.swift" \
  "$REPO/mac4DSTEM/Core/ML/LearnedDiskDetection.swift" \
  -framework Accelerate -framework Metal -framework MetalKit -framework CoreML

cd "$WORK"
./harness classical
# The CI runner is a VM with no Neural Engine, and the app refuses the learned detector
# without one (owner, 2026-09-30) — so on CI only the learned half is skipped, loudly; the
# classical half above still gates there. Locally both halves run before every release.
if [[ -n "${CI:-}" ]]; then
  echo "    learned half: SKIPPED on CI (no Neural Engine on the runner; the app refuses the learned detector without one — runs locally before every release)"
else
  ./harness learned "$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage"
fi
