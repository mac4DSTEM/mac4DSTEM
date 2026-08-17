#!/bin/zsh
# Measure the real nearest-neighbour Bragg spacing in a dataset, and isolate
# which disk-detection parameter changes the peak yield.
#
# NOT in tools/run-tests.sh — it needs a real multi-GB datacube from
# References/training_dataset (gitignored), like the campaign. This is a
# diagnostic you point at a file:
#
#   tools/bragg-spacing-probe/run.sh References/training_dataset/downsample_Si_SiGe_exp.h5
#
# Why it exists: `DiskDetectionParams.detectorAdapted` sets
# `minPeakSpacing = qMin/8`, a faithful rescaling of py4DSTEM's 60 px default
# for ~512 px patterns. But Bragg spacing is set by camera length, accelerating
# voltage and d-spacing — not by detector size. On downsample_Si_SiGe_exp
# (128x128) the gate lands at 16 px while the true lattice spacing is ~14.9 px,
# so it suppresses the shortest g-vectors — exactly the ones that define the
# basis — halving the yield to a median 12 peaks/pattern and making the strain
# basis fit unsolvable. Detected by hand first; this makes it measurable.
#
# Reports, per one-parameter-at-a-time variant: median peaks/pattern and the
# nearest-neighbour spacing distribution, plus the fraction of accepted peaks
# whose nearest neighbour falls below the shipped gate.
set -euo pipefail

if (( $# < 2 )); then
  echo "usage: $0 <path-to-datacube.h5> <probe-radius-px>" >&2
  exit 2
fi

# Resolve the dataset against the caller's cwd BEFORE cd'ing into the harness.
DATASET="${1:A}"
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

SRC="$REPO/mac4DSTEM/Core"
xcrun swiftc -O -parse-as-library -o "$WORK/probe" \
  "$SRC/Data/HDF5Types.swift" "$SRC/Data/H5Reader.swift" \
  "$SRC/Data/DatasetDescriptor.swift" "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" "$SRC/Data/ResidentCube.swift" \
  "$SRC/Data/Calibration.swift" "$SRC/Data/DisplayedProduct.swift" \
  "$SRC/Data/BraggVectorEMDWriter.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT1D.swift" \
  "$SRC/Compute/FFT2D.swift" "$SRC/Compute/MatrixDFTCorrelation.swift" \
  "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/DiskDetection.swift" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/probe" 2>/dev/null

cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./probe "$DATASET" "$2" \
  | grep -v '^\[MetalEngine\]'
