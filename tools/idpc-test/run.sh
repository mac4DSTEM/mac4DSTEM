#!/bin/zsh
# Non-square quantitative iDPC parity and calibration/boundary harness.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" dpc

"$PYTHON_BIN" "$ROOT/tools/idpc-test/reference.py" > "$WORK/fixture.json"
xcrun swiftc -module-cache-path "$WORK/module-cache" -O -o "$WORK/idpc-test" \
  "$ROOT/tools/idpc-test/main.swift" "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/idpc-test" "$WORK/fixture.json"
