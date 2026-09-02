#!/bin/zsh
# Source-locked py4DSTEM orientation matrix ↔ Euler convention checks.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/OrientationResult.swift"

"$WORK/harness" "$WORK/expected.json"
