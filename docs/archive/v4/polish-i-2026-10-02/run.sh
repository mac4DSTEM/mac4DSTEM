set -euo pipefail
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"   # run from the repo: bash docs/archive/v4/polish-i-2026-10-02/run.sh
cd "$(dirname "$0")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/polishI.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"; resolve_mac4dstem_python "$REPO"
for library in libhdf5 libsz.2 libaec.0; do cp "$REPO/$library.dylib" "$WORK/"; codesign -f -s - "$WORK/$library.dylib" 2>/dev/null; done
. "$REPO/tools/lib/sources.manifest"; mac4dstem_sources "$REPO" export
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
"$WORK/harness" "$WORK/one.h5"
PYTHONPATH="$REPO/References/py4DSTEM-dev" "$PYTHON_BIN" verify.py "$WORK/one.h5"
