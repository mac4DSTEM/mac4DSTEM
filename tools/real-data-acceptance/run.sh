#!/bin/zsh
set -euo pipefail
# Runs Core/Analysis/DiskDetection.swift's DiskDetector and Core/Analysis/VirtualDetector.swift's
# VirtualDetector.tiledImage (via Core/Data/H5Reader.swift) on the checked-in real training datasets;
# compare.py checks disk counts, probe radius, virtual-image min/max/mean/checksum, and elapsed time
# against golden values pinned in expected.json - mac4DSTEM's own prior measurements, not a py4DSTEM
# comparison; the surviving peaks' (x, y) positions are pinned too (S19), so a peak that moves with
# its count unchanged turns the gate red. Run with no arguments: tools/real-data-acceptance/run.sh.
# NO .h5 FILES IS A FAILURE (exit 1, before anything is built), not a SKIP: a gate that reports
# green over data that vanished is not a gate (S19, 2026-09-30). Machines that never had the data
# opt out in tools/run-tests.sh (MAC4DSTEM_NO_REAL_DATA=1, or CI), not here. Not in the
# scientific/campaign/diagnostic/owner_only/retired/support arrays; reached by tools/run-tests.sh
# `scientific` (where the data exist) and `all`. Pass condition: compare.py exits non-zero on any
# field outside tolerance, any moved peak, or over the 15 s budget, naming every mismatch; otherwise
# prints PASS per dataset. `--check-data` only checks that data exist (compare-selftest.sh uses it;
# MAC4DSTEM_TRAINING_DATASET_DIR points it at another directory).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DATA_DIR="${MAC4DSTEM_TRAINING_DATASET_DIR:-$ROOT/References/training_dataset}"
files=("$DATA_DIR"/*.h5(N))
if (( ${#files} == 0 )); then
  echo "FAIL: no .h5 files in $DATA_DIR — the real-data acceptance gate has nothing to measure." >&2
  echo "      Restore the data (References/ is gitignored), or on a machine that never had it set" >&2
  echo "      MAC4DSTEM_NO_REAL_DATA=1 for tools/run-tests.sh." >&2
  exit 1
fi
if [[ "${1:-}" == "--check-data" ]]; then
  echo "data present: ${#files} .h5 file(s) in $DATA_DIR"; exit 0
fi

# Check the comparator before the app. compare.py is what turns this harness's
# measurements into a verdict, so a comparator that has quietly stopped checking
# is indistinguishable from a passing gate. Runs first, before the ~1 min build,
# so a broken comparator fails in under a second. Needs no data and no toolchain.
# It is also its own harness in run-tests.sh's `scientific` array, so CI runs it;
# this call is the fail-fast before the build. compare-selftest.sh is the same for what
# comparator-test does not reach: every mismatch named, moved peaks, the run-tests routing.
"$ROOT/tools/comparator-test/run.sh"
"$ROOT/tools/real-data-acceptance/compare-selftest.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-real-data-acceptance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$ROOT/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" qcalibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/real-data-acceptance/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "${files[@]}" > report.json
if [[ -n "${MAC4DSTEM_REAL_REPORT_OUTPUT:-}" ]]; then
  cp report.json "$MAC4DSTEM_REAL_REPORT_OUTPUT"
fi
python3 "$ROOT/tools/real-data-acceptance/compare.py" \
  "$ROOT/tools/real-data-acceptance/expected.json" report.json
