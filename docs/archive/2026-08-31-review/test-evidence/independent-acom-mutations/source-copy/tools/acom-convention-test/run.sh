#!/bin/zsh
# Independent orientation truth. CPU-only; no Metal device or data downloads.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-acom-convention.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" acom
xcrun swiftc -O -module-cache-path "$WORK/module-cache" -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/acom-convention-test/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null
"$WORK/harness" "$ROOT/tools/acom-convention-test/reference.json"
