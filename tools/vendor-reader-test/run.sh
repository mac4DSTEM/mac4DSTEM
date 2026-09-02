#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tools/vendor-reader-test/reference.py" "$WORK"
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "$ROOT/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$ROOT/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$ROOT/mac4DSTEM/Core/Data/VendorRawReaders.swift" \
  "$ROOT/tools/vendor-reader-test/main.swift" \
  -o "$WORK/vendor-reader-test"
"$WORK/vendor-reader-test" "$WORK"
