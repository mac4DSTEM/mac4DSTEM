#!/bin/zsh
# Stage L2 (docs/load-pipeline-plan.md): a resident cube must be BIT-IDENTICAL
# to the tiled path. No Python reference is involved — the tiled path IS the
# reference, and the assertion is exact `==`, never a tolerance. See the header
# of main.swift for why that is derived rather than hoped for, and for the two
# comparisons that would become tolerance comparisons if the tiling ever
# diverged between the resident and streaming paths.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-virtual-detector-residency.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
# Build the app's real shader sources, then run the harness from that directory.
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
