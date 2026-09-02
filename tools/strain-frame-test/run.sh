#!/bin/zsh
# v2 S8 (docs/v2-release.md §8): the strain presentation-frame fixture.
# Pins StrainFrameRotation against three arbiters: the vendored py4DSTEM
# get_rotated_strain_map (golden.json from reference.py), a refit from
# vectors transformed the way py4DSTEM transforms calibrated vectors, and
# hand-checkable known answers. Sources come from tools/lib/sources.manifest
# and compile with the app's isolation flags (the S2 conventions).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

"$PYTHON_BIN" reference.py "$WORK"

mac4dstem_sources "$REPO" strain

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  "${MAC4DSTEM_SOURCES[@]}" \
  main.swift \
  -framework Accelerate -framework Metal

"$WORK/harness" "$WORK/golden.json"
