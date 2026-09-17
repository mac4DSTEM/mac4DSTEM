#!/bin/zsh
set -euo pipefail
# Checks Core/Data/DM4Reader.swift against hand-built malformed and edge-case
# DM4 files: unlabeled detector-major axes, contradictory or partially missing
# axis calibration, a truncated pixel payload, overflowing dimensions, and 200
# nested tag groups. Each case checks the reader degrades safely (a specific
# DM4Error, never a silent zero-filled read or a crash) rather than comparing
# against py4DSTEM. Run with no arguments: tools/dm4-robustness-test/run.sh.
# Listed in the `scientific` array of tools/run-tests.sh, so it runs under
# `tools/run-tests.sh scientific` (and `all`). Pass condition: each case
# prints "PASS: ..."; any mismatch calls fail(), printing "FAIL: ..." to
# stderr and exiting 1; the final line is "dm4-robustness-test: all passed".
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-dm4-robustness-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" readers
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/dm4-robustness-test/main.swift" \
  -o "$WORK/dm4-robustness-test" -framework Accelerate
"$WORK/dm4-robustness-test" "$WORK"
