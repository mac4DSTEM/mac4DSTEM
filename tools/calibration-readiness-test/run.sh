#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

xcrun swiftc -parse-as-library -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift"
"$WORK/harness"
