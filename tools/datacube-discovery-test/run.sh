#!/bin/zsh
# Which node discovery returns (Gate D 2026-09-04, the rank-3 class). Fixtures
# from reference.py; the harness compiles only the reader.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-datacube-discovery-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# Ad-hoc-signed copies of the bundled dylibs, as every reader harness does.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

"$PYTHON_BIN" reference.py "$WORK/fixtures"

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers cube calibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/harness" "$WORK/fixtures"
