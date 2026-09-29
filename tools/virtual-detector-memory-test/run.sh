#!/bin/zsh
# Memory-growth gate for VirtualDetector's streaming tiled passes (tiledImage,
# tiledRun, tiledDPStatistics, tiledDiffraction, tiledMeasuredOrigins,
# tiledCenterOfMass): phys_footprint must stay flat across tiles. Sibling of
# tools/tiled-detection-memory-test; one process per path. Built at -O, as
# DSTEMCore is in both app configurations.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-virtual-detector-memory-test.XXXXXX")"
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
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
# Every path runs (a leak in one must not hide another); any FAIL fails the gate.
rc=0
# Twice per path: `slow` generates each tile (the read outlasts the pass over the
# previous tile), `fast` hands back one ready array (built so the prefetch
# is finished before the loop awaits it; whether that await then suspends was not
# separately observed). Both measured flat in S16 (2026-09-30).
for path in image aperture dp diffraction origins com; do
  ./harness "$path" || rc=1
  ./harness "$path" fast || rc=1
done
exit $rc
