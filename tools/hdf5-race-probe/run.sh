#!/bin/zsh
# tools/hdf5-race-probe/run.sh
#
# Reproduction harness for docs/open-items.md, "HDF5 is entered from two
# unserialised paths, and a second window is not the worst of it": the
# bundled libhdf5 is Threadsafety OFF, `H5Reader` (Core/Data/H5Reader.swift)
# only serialises calls made through one actor instance, and
# `BraggVectorEMDWriter` (Core/Data/BraggVectorEMDWriter.swift) is a
# `nonisolated enum` with its own `dlopen` of the same library
# (`HDF5WriteLibrary.load()`) guarded by nothing. A 2026-08-19 lldb session
# reproduced EXC_BAD_ACCESS in H5SL_search within a few dozen iterations of
# concurrent use, but nothing runnable was checked in. This is that
# reproduction, built new because no existing tools/ runner drives both HDF5
# entry points at once (the reader tests exercise H5Reader against fakes).
#
# `diagnostic` deliberately, and it MAY CRASH THE PROBE PROCESS BY DESIGN: it
# measures whether concurrent use of the two paths crashes, and asserts
# nothing. The refactor this exists to give something to fail against is
# named twice in the app ("the real fix is one actor owning the library
# handle": App/mac4DSTEMApp.swift:64,
# mac4DSTEMTests/DatasetLoadCancellationTests.swift:141) and recorded in
# docs/decisions.md 2026-09-15.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-hdf5-race-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

# The smallest manifest group that links both `H5Reader` and
# `BraggVectorEMDWriter`: `readers` alone does not carry
# BraggVectorEMDWriter.swift (only H5Reader/DM4Reader/VendorRawReaders/
# DemoFourDDataSource), so linking against it alone leaves the writer-path
# symbols undefined. `export` is the one group in tools/lib/sources.manifest
# that names BraggVectorEMDWriter.swift explicitly, and it already carries
# H5Reader.swift and HDF5Types.swift alongside it — nothing wider is needed.
mac4dstem_sources "$REPO" export

CUBE="${1:-$REPO/References/demo-dataset/AlMgSi_demo.h5}"
SIDECAR_SRC="${2:-$REPO/References/training_dataset/downsample_Si_SiGe_exp.mac4dstem.h5}"
ITERATIONS="${3:-200}"

if [[ ! -f "$CUBE" ]]; then
  echo "hdf5-race-probe: no cube at $CUBE" >&2
  exit 1
fi
if [[ ! -f "$SIDECAR_SRC" ]]; then
  echo "hdf5-race-probe: no sidecar at $SIDECAR_SRC" >&2
  exit 1
fi

# Never touch References/: the sidecar is copied into the scratch work dir
# before the probe (which opens it read-only, but the rule is "copy it
# first", not "prove it stays read-only") ever sees a path under it.
SIDECAR="$WORK/sidecar.mac4dstem.h5"
cp "$SIDECAR_SRC" "$SIDECAR"

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done

# No metallib build: the `export` group's only Metal-touching file is
# DiskDetection.swift, which references `MTLBuffer` in one unused function
# signature (`detectAll`) and never loads a device or a default library.
# `MetalEngine.swift` — the file that actually opens a device and a
# metallib — is not part of this group. `-framework Metal` alone satisfies
# the `import Metal` and the type reference; nothing here dispatches a
# kernel.
xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal \
  -Xcc -DACCELERATE_NEW_LAPACK
codesign -f -s - "$WORK/probe" 2>/dev/null

cd "$WORK"
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"

echo "== serial (control) =="
set +e
./probe --serial "$CUBE" "$SIDECAR" "$ITERATIONS"
serial_status=$?
set -e
echo ""
echo "serial: exit $serial_status"

echo ""
echo "== concurrent (up to 3 runs; the race is probabilistic) =="
for attempt in 1 2 3; do
  echo "-- concurrent attempt $attempt --"
  set +e
  ./probe "$CUBE" "$SIDECAR" "$ITERATIONS"
  concurrent_status=$?
  set -e
  echo ""
  echo "concurrent: exit $concurrent_status"
  if [[ $concurrent_status -ne 0 ]]; then
    break
  fi
done
