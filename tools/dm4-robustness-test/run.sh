#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-dm4-robustness-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" readers
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/dm4-robustness-test/main.swift" \
  -o "$WORK/dm4-robustness-test" -framework Accelerate
"$WORK/dm4-robustness-test" "$WORK"
