#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-vendor-reader-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tools/vendor-reader-test/reference.py" "$WORK"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" readers
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/vendor-reader-test/main.swift" \
  -o "$WORK/vendor-reader-test" -framework Accelerate
"$WORK/vendor-reader-test" "$WORK"
