#!/bin/zsh
# Stage L3 (docs/load-pipeline-plan.md): a cropped read must equal the
# corresponding slice of a full read, EXACTLY, on every reader. See the header
# of main.swift for why the comparison is `==` and why the expected values are
# computed here rather than asked of the reader a second time.
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
# (Same reason as tools/calibration-test.)
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

"$PYTHON_BIN" reference.py "$WORK"

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main, and
# FourDArray's resident path allocates through it. Build the app's real shader
# sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "$SRC/DatasetDescriptor.swift" \
  "$SRC/DiffractionPattern.swift" \
  "$SRC/FourDDataSource.swift" \
  "$SRC/LoadSpecification.swift" \
  "$SRC/HDF5Types.swift" \
  "$SRC/H5Reader.swift" \
  "$SRC/DM4Reader.swift" \
  "$SRC/VendorRawReaders.swift" \
  "$SRC/DemoFourDDataSource.swift" \
  "$SRC/FourDArray.swift" \
  "$SRC/ResidentCube.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader's last dlopen fallback is the plain name "libhdf5.dylib"; run from
# the temp dir so it resolves to the signed copy.
cd "$WORK"
./harness "$WORK"
