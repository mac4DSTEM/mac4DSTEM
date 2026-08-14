#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
xcrun swiftc -parse-as-library -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift"
"$WORK/harness" "$WORK/expected.json"
