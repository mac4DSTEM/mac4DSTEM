#!/bin/zsh
# Gated parity harness for Core/Analysis/RotationCalibration.swift — see
# main.swift for the four legs and reference.py's module docstring for why
# leg (b)'s numeric comparison is informational only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-rotation-parity-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" rotation

"$PYTHON_BIN" "$ROOT/tools/rotation-parity-test/reference.py" > "$WORK/fixture.json"
xcrun swiftc -package-name mac4DSTEM -module-cache-path "$WORK/module-cache" -O -o "$WORK/rotation-parity-test" \
  "$ROOT/tools/rotation-parity-test/main.swift" "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/rotation-parity-test" "$WORK/fixture.json"
