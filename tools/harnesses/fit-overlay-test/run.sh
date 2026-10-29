#!/bin/zsh
# Fit-verification overlay geometry: inverse calibration mapping, strain
# lattice overlay, matched-ACOM-template overlay, origin/ellipse conventions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-fit-overlay-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" fitoverlays
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" "$ROOT/tools/harnesses/fit-overlay-test/main.swift" \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit

mac4dstem_copy_bundles "$WORK"   # MacEMUI_ShellMetal.bundle: MetalEngine's Metal library
cd "$WORK"
./harness
