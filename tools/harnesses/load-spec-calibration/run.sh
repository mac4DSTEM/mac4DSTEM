#!/bin/zsh
# Stage L3 step 2 (docs/load-pipeline-plan.md): a re-referenced origin must land
# on the same physical feature as an origin measured on the cropped data, and a
# value that cannot be re-referenced must be invalidated rather than carried.
# See the header of main.swift for why this is not a self-consistency check.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-load-spec-calibration.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" analysis calibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

mac4dstem_copy_bundles "$WORK"   # MacEMUI_ShellMetal.bundle: MetalEngine's Metal library
cd "$WORK"
./harness
