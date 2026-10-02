#!/bin/zsh
# tools/hdf5-exit-race-test/run.sh [runs=200]
#
# Quitting while HDF5 is busy must not crash (Slot 4¾ review, 2026-10-02).
# The bundled libhdf5 is Threadsafety OFF; exit() runs HDF5's own atexit
# teardown (H5_term_library), which `HDF5Serial` used to leave unguarded, so a
# Task still inside H5Dread raced it and the process died at quit. The fix is
# the quit barrier in `HDF5Serial` (Core/Data/HDF5Types.swift); main.swift says
# how it works.
#
# Two checks, both gated:
#   order  deterministic — HDF5Serial is held when H5_term_library starts
#          (H5atclose callback). Red when the barrier is missing or is
#          registered before HDF5's own handler.
#   race   RUNS processes, each: a detached Task loops H5Reader.readPattern
#          on a synthetic cube while main calls exit(0) after 30–129 ms.
#          ANY abnormal end (signal, hang > 20 s, nonzero exit) fails.
#          On the code before the barrier this probe crashed 198 of 200 runs
#          (2026-10-02; the Gate D harness, -Onone on a larger uint16 cube,
#          about 6 %). Even at 6 %, 200 clean runs by chance are below 1e-5.
# Crashes it provokes on old code leave .ips reports in
# ~/Library/Logs/DiagnosticReports (probe-*), as any crash does.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
RUNS="${1:-200}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-hdf5-exit-race.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
# `export` carries H5Reader, BraggVectorEMDWriter (the cube writer) and
# HDF5Types (the lock); `readers` adds DemoFourDDataSource, the cube's source.
mac4dstem_sources "$REPO" readers export

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done

xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal \
  -Xcc -DACCELERATE_NEW_LAPACK
codesign -f -s - "$WORK/probe" 2>/dev/null

export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
CUBE="$WORK/cube.h5"
"$WORK/probe" make "$CUBE"

# `perl -e 'alarm …; exec'` is the stock-macOS timeout: a hang ends in SIGALRM (142).
bounded() { perl -e 'alarm shift; exec @ARGV' 20 "$@"; }

failed=0

set +e
order_out="$(bounded "$WORK/probe" order "$CUBE" 2>&1)"
order_status=$?
set -e
echo "$order_out"
if (( order_status != 0 )) || [[ "$order_out" != *"held when HDF5 tears down = yes"* ]]; then
  echo "FAIL order: HDF5Serial is not held when HDF5 tears down (exit $order_status)"
  failed=1
else
  echo "PASS order: the quit barrier runs before H5_term_library"
fi

abnormal=0
for (( i = 1; i <= RUNS; i++ )); do
  delay=$(( 30 + (i * 37) % 100 ))
  set +e
  bounded "$WORK/probe" race "$CUBE" "$delay" > /dev/null 2>&1
  run_status=$?
  set -e
  if (( run_status != 0 )); then
    abnormal=$(( abnormal + 1 ))
    echo "  race run $i (exit after $delay ms): status $run_status"
  fi
done
if (( abnormal > 0 )); then
  echo "FAIL race: $abnormal of $RUNS runs ended abnormally when exit() met a busy reader"
  failed=1
else
  echo "PASS race: $RUNS of $RUNS runs exited cleanly while a reader was busy"
fi

exit $failed
