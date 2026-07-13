#!/bin/zsh
# Source-locked py4DSTEM orientation matrix ↔ Euler convention checks.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

python3 reference.py > "$WORK/expected.json"
xcrun swiftc -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/OrientationResult.swift"

"$WORK/harness" "$WORK/expected.json"
