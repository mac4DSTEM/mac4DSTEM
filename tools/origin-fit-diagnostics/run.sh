#!/bin/zsh
#
# origin-fit-diagnostics — S12's evidence, re-runnable.
#
# Two diagnostics, neither of which gates. They answer the two measurement
# questions S12 owed (docs/q-calibration-design.md):
#
#   residuals <file.h5>...   Per-position origin-fit residual DISTRIBUTION, not
#                            just its RMS. Answers #29: does a large
#                            `OriginMaps.rmsResidual` mean the fit is too rigid
#                            to follow real descan, or that the per-position
#                            measurement failed? Reports percentiles, the
#                            median/RMS ratio, the fraction beyond the probe
#                            radius, and what an iteratively trimmed plane refit
#                            would do to the gate.
#
#   coarse-cost              Cost of making `measureOrigin`'s coarse step
#                            translation-equivariant, by the two-token stride
#                            change S2 validated for ACCURACY on 2026-08-19
#                            (OriginMeasure.metal:47,49). Both kernels are
#                            derived from the SHIPPED shader at run time — there
#                            is no copy here to drift. Needs no dataset.
#
# NOT in tools/run-tests.sh, deliberately: `residuals` needs the gitignored
# training datasets, and neither has a pass/fail criterion — they measure, they
# do not assert. Numbers quoted in docs/q-calibration-design.md came from here.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"; shift 2>/dev/null || true
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir

case "$MODE" in
residuals)
  if (( $# == 0 )); then
    # Exclude session sidecars — they sit beside the cubes and are not datacubes.
    files=("$ROOT"/References/training_dataset/*.h5(N))
    files=(${files:#*.mac4dstem.h5})
  else
    files=("$@")
  fi
  if (( ${#files} == 0 )); then echo "SKIP: no datasets"; exit 0; fi
  for lib in libhdf5 libsz.2 libaec.0; do
    cp "$ROOT/$lib.dylib" "$WORK/"; codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
  done
  for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
    xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
  done
  xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"
  SRC="$ROOT/mac4DSTEM/Core"
  xcrun swiftc -O -parse-as-library -o "$WORK/probe" \
    "$SRC/Data/HDF5Types.swift" "$SRC/Data/H5Reader.swift" "$SRC/Data/DatasetDescriptor.swift" \
    "$SRC/Data/DiffractionPattern.swift" "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" \
    "$SRC/Data/ResidentCube.swift" "$SRC/Data/LoadSpecification.swift" \
    "$SRC/Data/Calibration.swift" "$SRC/Data/DisplayedProduct.swift" \
    "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT1D.swift" "$SRC/Compute/FFT2D.swift" \
    "$SRC/Compute/MatrixDFTCorrelation.swift" "$SRC/Compute/MetalEngine.swift" \
    "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/VirtualDetector.swift" \
    "$SRC/Analysis/OriginCalibration.swift" \
    "$HERE/residuals.swift" -framework Accelerate -framework Metal -framework MetalKit
  codesign -f -s - "$WORK/probe" 2>/dev/null
  absolute=(); for f in "${files[@]}"; do absolute+=("${f:A}"); done
  cd "$WORK"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./probe "${absolute[@]}" 2>&1 | sed '/^\[MetalEngine\]/d'
  ;;
coarse-cost)
  # Derive both kernels from the shipped shader so neither can drift from it.
  # V1 is exactly S2's two-token change: block stride bin -> 1.
  SHADER="$ROOT/mac4DSTEM/Shaders/OriginMeasure.metal"
  cp "$SHADER" "$WORK/v0.metal"
  sed -e 's/kernel void measureOrigin(/kernel void measureOriginStride1(/' \
      -e 's/struct OriginParams {/struct OriginParamsV1 {/' \
      -e 's/constant OriginParams &p/constant OriginParamsV1 \&p/' \
      -e 's/by += bin/by += 1/' -e 's/bx += bin/bx += 1/' \
      "$WORK/v0.metal" > "$WORK/v1.metal"
  for expected in measureOriginStride1 'by += 1' 'bx += 1'; do
    grep -q -- "$expected" "$WORK/v1.metal" || {
      echo "FAIL: the shipped shader no longer matches this tool's stride rewrite ('$expected' absent)." >&2
      echo "      Re-derive the variant against $SHADER before trusting any timing." >&2
      exit 1
    }
  done
  xcrun -sdk macosx metal -c "$WORK/v0.metal" -o "$WORK/v0.air"
  xcrun -sdk macosx metal -c "$WORK/v1.metal" -o "$WORK/v1.air"
  xcrun -sdk macosx metallib "$WORK/v0.air" "$WORK/v1.air" -o "$WORK/default.metallib"
  xcrun swiftc -O -parse-as-library -o "$WORK/bench" "$HERE/coarse-cost.swift" -framework Metal
  codesign -f -s - "$WORK/bench" 2>/dev/null
  cd "$WORK" && ./bench
  ;;
*)
  echo "Usage: tools/origin-fit-diagnostics/run.sh [residuals [file.h5...] | coarse-cost]" >&2
  exit 64
  ;;
esac
