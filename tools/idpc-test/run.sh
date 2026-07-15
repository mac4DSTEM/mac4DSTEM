#!/bin/zsh
# Non-square quantitative iDPC parity and calibration/boundary harness.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
. "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"

"$PYTHON_BIN" "$ROOT/tools/idpc-test/reference.py" > "$WORK/fixture.json"
xcrun swiftc -O -o "$WORK/idpc-test" \
  "$ROOT/tools/idpc-test/main.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$ROOT/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$ROOT/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$ROOT/mac4DSTEM/Core/Data/Calibration.swift" \
  "$ROOT/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$ROOT/mac4DSTEM/Core/Analysis/DPC.swift" \
  -framework Accelerate
"$WORK/idpc-test" "$WORK/fixture.json"
