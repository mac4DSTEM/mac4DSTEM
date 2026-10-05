#!/bin/zsh
# Velox EMD reader parity (v5.0 WP1, 2026-10-05). `scientific`: every public Velox file in
# rosettasciio's test data (the fei_emd_files and velox_* zips, fetched with the pinned
# rosettasciio by tools/lib/fetch-rsciio.sh, unzipped into References/velox-parity/) is read by
# rsciio (truth.py, sum_frames=True) and by Core/Data/VeloxEMDReader.swift (main.swift), and the
# dense spectrum image, the energy axis and the scan image are compared count for count.
# Pass condition: final line "velox-parity: all passed", exit 0. A FAIL line exits 1.
#
#   tools/velox-parity/run.sh            the gate
#   tools/velox-parity/run.sh owner [emd]   diagnostic on the owner's private file (P2, P3, P4):
#                                        default References/EDX/SI HAADF 1456 77000 x 20260420.emd;
#                                        needs ~6 GB of RAM for rsciio's dense cube. Never a gate.
#
# Python: VELOX_PARITY_PYTHON, else the usual resolution. It needs numpy, h5py, rsciio and sparse
# (numba is optional but makes the owner diagnostic tolerable). If the interpreter lacks rsciio
# the harness stops with the install line; it does not skip: a parity gate that skips is no gate.
#   python -m venv V && V/bin/pip install numpy h5py dask pint python-dateutil pyyaml python-box sparse numba
#   V/bin/pip install --no-deps References/rosettasciio
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-velox-parity.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
if [[ -n "${VELOX_PARITY_PYTHON:-}" ]]; then PYTHON_BIN="$VELOX_PARITY_PYTHON"; else resolve_mac4dstem_python "$REPO"; fi
if ! "$PYTHON_BIN" -c 'import rsciio, sparse, h5py, numpy' 2>/dev/null; then
  echo "velox-parity: $PYTHON_BIN has no rsciio/sparse/h5py. See the header of this script for the install line." >&2
  exit 1
fi
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

"$REPO/tools/lib/fetch-rsciio.sh"
DATA="$REPO/References/velox-parity"
ZIPS="$REPO/References/rosettasciio/rsciio/tests/data/emd"
for z in fei_emd_files velox_emd_version11 velox_emd_v11_elementSelection velox_EELS_EDS; do
  [[ -d "$DATA/$z" ]] || unzip -oq "$ZIPS/$z.zip" -d "$DATA/$z"
done

# Ad-hoc-signed copies of the bundled dylibs, as every reader harness does.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift "${MAC4DSTEM_ISOLATION_FLAGS[@]}" -framework Accelerate
codesign -f -s - "$WORK/harness" 2>/dev/null

if [[ "${1:-}" == "owner" ]]; then
  OWNER="${2:-$REPO/References/EDX/SI HAADF 1456 77000 x 20260420.emd}"
  "$PYTHON_BIN" -W ignore truth.py owner "$OWNER" "$WORK/owner-truth"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/harness" owner "$OWNER" "$WORK/owner-truth"
else
  "$PYTHON_BIN" -W ignore truth.py "$DATA" "$WORK/truth"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/harness" parity "$DATA" "$WORK/truth"
fi
