#!/bin/zsh
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
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ParallaxAlignment.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ParallaxAberrationCorrection.swift" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json"
