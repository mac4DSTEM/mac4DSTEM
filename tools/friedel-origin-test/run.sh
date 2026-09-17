#!/bin/zsh
# Gated parity harness for Core/Analysis/FriedelOrigin.swift (the port of
# py4DSTEM's get_origin_friedel) — see main.swift for the recovery/parity legs
# and reference.py's module docstring for the source contract that gates first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-friedel-origin-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" friedel

"$PYTHON_BIN" "$ROOT/tools/friedel-origin-test/reference.py" > "$WORK/fixture.json"
xcrun swiftc -package-name mac4DSTEM -module-cache-path "$WORK/module-cache" -O -o "$WORK/friedel-origin-test" \
  "$ROOT/tools/friedel-origin-test/main.swift" "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/friedel-origin-test" "$WORK/fixture.json"
