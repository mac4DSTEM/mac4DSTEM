#!/bin/zsh
set -euo pipefail
# The Swift harness writes a strain+orientation ScalarResultMap bundle through
# Core/Data/BraggVectorEMDWriter.swift's BraggVectorEMDWriter.writeScientificBundle, checking the
# write is atomic and a cancelled write leaves no destination file; verify.py then reopens the bundle
# with py4DSTEM's own py4DSTEM.read()/h5py to confirm the EMD structure, calibration, and per-map
# metadata round-trip. Run with no arguments: tools/scientific-bundle-test/run.sh. Listed in the
# scientific array of tools/run-tests.sh, so it runs under tools/run-tests.sh scientific (and all).
# Pass condition: main.swift throws (non-zero exit) on any unmet require(); verify.py's bare assert
# statements raise on mismatch; success prints PASS: atomic coherent bundle and cancellation recovery.
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-scientific-bundle-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
for library in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$library.dylib" "$WORK/"
  codesign -f -s - "$WORK/$library.dylib" 2>/dev/null
done
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" export
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
"$WORK/harness" "$WORK/bundle.h5" "$WORK/cancelled.h5"
PYTHONPATH="$REPO/References/py4DSTEM-dev" "$PYTHON_BIN" verify.py "$WORK/bundle.h5"
