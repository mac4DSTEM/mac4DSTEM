#!/bin/zsh
# Non-gating CPU/Metal baseline. Record same-machine trends; never fail a build
# on wall-clock time. Set MAC4DSTEM_BENCHMARK_REPEATS/WARMUPS to tune duration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-performance-baseline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" analysis acom ptychography
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/baseline" "$ROOT/tools/performance-baseline/main.swift" \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit
cd "$WORK"
# Keep stdout valid JSON despite MetalEngine's one-line device diagnostic.
./baseline | sed '/^\[MetalEngine\]/d'
