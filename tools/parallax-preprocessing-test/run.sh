#!/bin/zsh
set -euo pipefail

# reference.py source-locks py4DSTEM's Parallax.preprocess default path (BF
# mask, k-vectors, probe angles, edge window) in process/phase/parallax.py
# and the electron-wavelength formula in process/utils/utils.py; the Swift
# harness runs Core/Analysis/ParallaxPreprocessing.swift's
# ParallaxPreprocessor.run against a synthetic FourDDataSource, checking
# rejection on missing calibration, a stack memory ceiling, and cancellation.
# Run with no arguments: tools/parallax-preprocessing-test/run.sh. Listed in
# both the `scientific` and `campaign` arrays of tools/run-tests.sh (and `all`).
# Pass condition: final line "parallax-preprocessing-test: all passed".

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-parallax-preprocessing-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" parallax
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json"
