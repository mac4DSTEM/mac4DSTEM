#!/bin/zsh
# Stage L4 (docs/load-pipeline-plan.md): binning on read must reproduce
# py4DSTEM's bin_data_diffraction exactly — the sum, the edge-remainder crop and
# the Q_pixel_size rescale — with only the deviations that are written down.
# The arbiter is py4DSTEM itself, from References/py4DSTEM-dev. See the header of
# main.swift for why, and for why the comparison is `==` rather than a tolerance.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
SRC="$REPO/mac4DSTEM/Core/Data"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# The bundled dylibs' signatures don't validate for ad-hoc-built tools; use
# ad-hoc-signed copies in the temp dir instead of touching the repo files.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

PYTHONPATH="$REPO/References/py4DSTEM-dev" "$PYTHON_BIN" reference.py "$WORK"

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "$SRC/DatasetDescriptor.swift" \
  "$SRC/FourDDataSource.swift" \
  "$SRC/LoadSpecification.swift" \
  "$SRC/HDF5Types.swift" \
  "$SRC/H5Reader.swift" \
  "$SRC/Calibration.swift" \
  "$SRC/CalibrationReReference.swift" \
  main.swift

codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader's last dlopen fallback is the plain name "libhdf5.dylib"; run from
# the temp dir so it resolves to the signed copy.
cd "$WORK"
./harness "$WORK"
