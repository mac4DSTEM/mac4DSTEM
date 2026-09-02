#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "$ROOT/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$ROOT/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DM4Reader.swift" \
  "$ROOT/tools/dm4-robustness-test/main.swift" \
  -o "$WORK/dm4-robustness-test"
"$WORK/dm4-robustness-test" "$WORK"
