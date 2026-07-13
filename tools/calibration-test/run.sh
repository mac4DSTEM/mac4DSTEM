#!/bin/zsh
# Standalone regression test for H5Reader.pixelCalibration().
# Not part of the Xcode target. Builds attribute- and dataset-form EMD fixtures
# with the repo's bundled libhdf5, then also checks two committed files written
# by py4DSTEM 0.14.19 (mean calibration and non-square fitted/measured origin
# maps). All four are read through production H5Reader code.
set -e
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
SRC="$REPO/mac4DSTEM/Core/Data"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The bundled dylibs' signatures don't validate for ad-hoc-built tools; use
# ad-hoc-signed copies in the temp dir instead of touching the repo files.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

cc make_fixture.c "$WORK/libhdf5.dylib" -Wl,-rpath,"$WORK" -o "$WORK/make_fixture"
codesign -f -s - "$WORK/make_fixture" 2>/dev/null
"$WORK/make_fixture" "$WORK/attrs.h5" "$WORK/datasets.h5"

xcrun swiftc -o "$WORK/harness" main.swift \
  "$SRC/HDF5Types.swift" "$SRC/H5Reader.swift" "$SRC/FourDDataSource.swift" "$SRC/DatasetDescriptor.swift" \
  "$SRC/Calibration.swift"
codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader's last dlopen fallback is the plain name "libhdf5.dylib"; run from
# the temp dir so it resolves to the signed copy. 2>/dev/null hides HDF5's
# expected error-stack chatter from the dataset-form probes on attrs.h5.
cp real_py4dstem.h5 "$WORK/"
cp real_py4dstem_origin_maps.h5 "$WORK/"

cd "$WORK"
./harness attrs.h5 2>/dev/null
./harness datasets.h5 2>/dev/null
# Ground truth: written by py4DSTEM 0.14.19 itself (make_real_fixture.py).
./harness real_py4dstem.h5 /datacube_root/datacube/data 2>/dev/null
# Ground truth: non-square fitted + measured origin maps written by the
# checked-in py4DSTEM 0.14.19 source (make_origin_maps_fixture.py).
./harness real_py4dstem_origin_maps.h5 /datacube_root/datacube/data origin-maps 2>/dev/null
echo "calibration-test: all passed"
