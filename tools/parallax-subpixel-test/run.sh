#!/bin/zsh
set -euo pipefail

# reference.py source-locks py4DSTEM's bilinear kernel-density-estimate
# subpixel reconstruction in process/phase/parallax.py and
# process/phase/utils.py; the Swift harness runs
# Core/Analysis/ParallaxSubpixelReconstruction.swift's
# ParallaxSubpixelReconstructor.reconstruct across auto/filtered/lanczos/
# position/checkerboard cases, plus option validation, a memory bound, and
# cancellation. Run with no arguments: tools/parallax-subpixel-test/run.sh.
# Listed in both the `scientific` and `campaign` arrays of tools/run-tests.sh
# (and `all`). Pass condition: final "parallax-subpixel-test: all passed".

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-parallax-subpixel-test.XXXXXX")"
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
