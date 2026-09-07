#!/bin/zsh
# Standalone numeric parity harness for the production synthetic probe kernel
# and single-pattern Bragg-disk detector. The standard-library reference is
# source-locked to checked-in py4DSTEM 0.14.19 formulas.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-disk-detection-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" detection
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal

"$WORK/harness" "$WORK/expected.json"
