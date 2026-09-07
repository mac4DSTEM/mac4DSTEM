#!/bin/zsh
# Compiles one UI/ file and no Core/ source; tools/lib/sources.manifest (Core only) has nothing to supply.
# Pure geometry checks for the non-square Bragg-peak overlay.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-peak-overlay-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/UI/PeakOverlayGeometry.swift"

"$WORK/harness"
