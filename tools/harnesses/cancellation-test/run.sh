#!/bin/zsh
# Cooperative cancellation primitive + production multi-row disk path.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-cancellation-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main (the cube reads through FourDArray).
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" analysis calibration
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal

cd "$WORK"
./harness
