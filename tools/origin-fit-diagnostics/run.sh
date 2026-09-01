#!/bin/zsh
#
# origin-fit-diagnostics — S12's evidence, re-runnable.
#
# Four diagnostics, none of which gates. Two answer the measurement questions
# S12 owed and two the ones S13 owed (docs/q-calibration-design.md):
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
#   shell-check <f.h5> <id>  S13 E1: the estimator's own MAD/observed statistic
#                            at DELIBERATELY DISPLACED origins, in two arms
#                            (constant offset; per-position jitter), so §3.1's
#                            threshold is measured instead of invented. <id> is
#                            a CrystalModelLibrary model id.
#
#   trim-sweep <file.h5>...  S13 E2: kept fraction, bootstrap SD of the fitted
#                            origin, and the kept set's spatial support across a
#                            sweep of trim aggressiveness — the evidence for
#                            whether a hard ceiling on the excluded fraction
#                            (design §6b) has anywhere defensible to go.
#
# NOT in tools/run-tests.sh, deliberately: three of the four need the gitignored
# training datasets, and none has a pass/fail criterion — they measure, they do
# not assert. Numbers quoted in docs/q-calibration-design.md and in
# docs/archive/v2-session-records/s13.md came from here.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"; shift 2>/dev/null || true
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir

# Shared build: the HDF5 dylibs, the shipped shaders, and one Swift binary from
# the source manifest. Migrated off a hand-written source list on 2026-08-28
# (development-process.md §1: when next touched) — this runner was one of the
# hand-listing ones the 2026-08-17 breakage was about.
build_probe() {
  local entry=$1 out=$2; shift 2
  for lib in libhdf5 libsz.2 libaec.0; do
    cp "$ROOT/$lib.dylib" "$WORK/"; codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
  done
  for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
    xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
  done
  xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"
  . "$ROOT/tools/lib/sources.manifest"
  mac4dstem_sources "$ROOT" qcalibration
  xcrun swiftc -O -parse-as-library -o "$WORK/$out" \
    "${MAC4DSTEM_SOURCES[@]}" "$ROOT/mac4DSTEM/Core/Data/DisplayedProduct.swift" \
    "$HERE/$entry" -framework Accelerate -framework Metal -framework MetalKit
  codesign -f -s - "$WORK/$out" 2>/dev/null
}

# The training cubes, minus the session sidecars that sit beside them and are
# not datacubes (backlog #43).
default_files() {
  files=("$ROOT"/References/training_dataset/*.h5(N))
  files=(${files:#*.mac4dstem.h5})
}

case "$MODE" in
residuals)
  if (( $# == 0 )); then default_files; else files=("$@"); fi
  if (( ${#files} == 0 )); then echo "SKIP: no datasets"; exit 0; fi
  build_probe residuals.swift probe
  absolute=(); for f in "${files[@]}"; do absolute+=("${f:A}"); done
  cd "$WORK"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./probe "${absolute[@]}" 2>&1 | sed '/^\[MetalEngine\]/d'
  ;;
shell-check)
  if (( $# < 2 )); then
    echo "Usage: run.sh shell-check <file.h5> <crystalModelID>" >&2; exit 64
  fi
  target="${1:A}"; model="$2"
  build_probe shell-check.swift shellcheck
  cd "$WORK"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./shellcheck "$target" "$model" 2>&1 | sed '/^\[MetalEngine\]/d'
  ;;
probe-size)
  # The probeSize discriminator on real data — maxDP vs meanDP vs the two
  # lowest-sum single patterns, all through the real pipeline. 2026-09-01.
  if (( $# == 0 )); then default_files; else files=("$@"); fi
  if (( ${#files} == 0 )); then echo "SKIP: no datasets"; exit 0; fi
  build_probe probe-size.swift probesize
  absolute=(); for f in "${files[@]}"; do absolute+=("${f:A}"); done
  cd "$WORK"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./probesize "${absolute[@]}" 2>&1 | sed '/^\[MetalEngine\]/d'
  ;;
trim-sweep)
  if (( $# == 0 )); then default_files; else files=("$@"); fi
  if (( ${#files} == 0 )); then echo "SKIP: no datasets"; exit 0; fi
  build_probe trim-sweep.swift trimsweep
  absolute=(); for f in "${files[@]}"; do absolute+=("${f:A}"); done
  cd "$WORK"
  MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" ./trimsweep "${absolute[@]}" 2>&1 | sed '/^\[MetalEngine\]/d'
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
  echo "Usage: tools/origin-fit-diagnostics/run.sh [residuals [file.h5...] | coarse-cost | shell-check <file.h5> <crystalModelID> | trim-sweep [file.h5...]]" >&2
  exit 64
  ;;
esac
