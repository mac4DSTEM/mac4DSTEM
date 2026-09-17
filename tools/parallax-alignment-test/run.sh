#!/bin/zsh
set -euo pipefail

# reference.py source-locks py4DSTEM's multi-level Parallax alignment
# (grouping, cross-correlation, subpixel shift) in process/phase/parallax.py,
# process/utils/cross_correlate.py, and process/utils/multicorr.py; the Swift
# harness runs Core/Analysis/ParallaxAlignment.swift's
# ParallaxAligner.alignOneLevel against the emitted fixture, checking shifts,
# masks, and rejection on cancellation or a memory ceiling. Run with no
# arguments: tools/parallax-alignment-test/run.sh. Listed in both the
# `scientific` and `campaign` arrays of tools/run-tests.sh, so it runs under
# `tools/run-tests.sh scientific` and `...campaign` (and `all`). Pass
# condition: "PASS: ..." per case, final "parallax-alignment-test: all passed".

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-parallax-alignment-test.XXXXXX")"
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
