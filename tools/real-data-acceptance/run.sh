#!/bin/zsh
set -euo pipefail
# Runs Core/Analysis/DiskDetection.swift's DiskDetector and Core/Analysis/VirtualDetector.swift's
# VirtualDetector.tiledImage (via Core/Data/H5Reader.swift) on the checked-in real training datasets;
# compare.py checks disk counts, probe radius, virtual-image min/max/mean/checksum, and elapsed time
# against golden values pinned in expected.json - mac4DSTEM's own prior measurements, not a py4DSTEM
# comparison. Run with no arguments: tools/real-data-acceptance/run.sh (SKIPs, exit 0, with no .h5
# files present). Not in the scientific/campaign/diagnostic/owner_only/retired/support arrays; runs
# only under tools/run-tests.sh all. Pass condition: compare.py exits non-zero on any field outside
# tolerance or over the 15 s budget; otherwise prints PASS per dataset.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Check the comparator before the app. compare.py is what turns this harness's
# measurements into a verdict, so a comparator that has quietly stopped checking
# is indistinguishable from a passing gate. Runs first, before the ~1 min build,
# so a broken comparator fails in under a second. Needs no data and no toolchain.
# It is also its own harness in run-tests.sh's `scientific` array, so CI runs it;
# this call is the fail-fast for the `all` path, which is the only one that
# reaches this harness at all.
"$ROOT/tools/comparator-test/run.sh"

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

files=("$ROOT"/References/training_dataset/*.h5(N))
if (( ${#files} == 0 )); then
  echo "SKIP: no checked-in real-data acceptance files"; exit 0
fi
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./harness "${files[@]}" > report.json
if [[ -n "${MAC4DSTEM_REAL_REPORT_OUTPUT:-}" ]]; then
  cp report.json "$MAC4DSTEM_REAL_REPORT_OUTPUT"
fi
python3 "$ROOT/tools/real-data-acceptance/compare.py" \
  "$ROOT/tools/real-data-acceptance/expected.json" report.json
