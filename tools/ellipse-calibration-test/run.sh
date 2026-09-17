#!/bin/zsh
set -euo pipefail
# reference.py source-locks py4DSTEM's ellipse/profile fit conventions in
# process/calibration/ellipse.py and process/utils/elliptical_coords.py and
# emits synthetic ring, profile, overlap, and spotty-ring fixtures; the Swift
# harness runs Core/Analysis/EllipseCalibration.swift's fit1D/fitBestAvailable
# against them, checking fitted parameters, insufficient-signal/coverage
# refusals, and the sparse-coverage "fit anyway" path. Run with no arguments:
# tools/ellipse-calibration-test/run.sh. Listed in the `scientific` array of
# tools/run-tests.sh, so it runs under `tools/run-tests.sh scientific` (and
# `all`). Pass condition: each case prints "PASS: ..."; fail() prints
# "FAIL: ..." and exits 1; the final line is "ellipse-calibration-test: all passed".
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-ellipse-calibration-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json"
