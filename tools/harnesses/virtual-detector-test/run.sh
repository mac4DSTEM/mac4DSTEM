#!/bin/zsh
# Standalone numeric parity harness for the production virtual-detector mask
# builder and Metal kernels. Reference values are source-locked to the checked-
# in py4DSTEM make_detector implementation; no Python packages are required.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-virtual-detector-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" analysis calibration
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit

mac4dstem_copy_bundles "$WORK"   # MacEMUI_ShellMetal.bundle: MetalEngine's Metal library
cd "$WORK"
./harness expected.json
