#!/bin/zsh
# Row 1 (2026-09-30 review): mirror-zone orientation recovery, CPU time per
# pattern and CPU/Metal parity of the conjugated pass. Production sources only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-acom-mirror-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" acom
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" "$ROOT/tools/acom-mirror-test/main.swift" \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit

cd "$WORK"
./harness
