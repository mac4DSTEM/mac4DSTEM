#!/bin/zsh
# v2 S10 — the reduced-file export: a cropped/binned/scan-cropped view exports
# to a standalone py4DSTEM DataCube whose calibration is in the FILE'S OWN
# frame (the origin lands on the measured beam), with derivation + recipe
# provenance stamped. Sources come from tools/lib/sources.manifest (`export`
# group) — never a hand list (the 2026-08-17 / 2026-08-25 breakage class).
#
# NEGATIVE CONTROLS, each verified live during S10 (2026-08-26) and reverted —
# each names the line it breaks and why the failure follows:
#   NC1  CalibrationReReference.swift `shifted(origin, byX: -detectorCrop…)`
#        (apply's detector-crop translation): dropping the shift leaves the
#        origin in source coordinates → the centroid check fails on `crop`
#        by ~the 8/4 px offsets.
#   NC2  CalibrationReReference.binnedCoordinate → naive `x / b`: every
#        origin biased by (b−1)/2b px → the centroid check fails on
#        `cropbin` by 0.25 px against the 0.02 px gate.
#   NC3  BraggVectorEMDWriter.transformedCalibration `qSize * bin` dropped:
#        Q_pixel_size check fails on every export-binned case.
#   NC4  transformedCalibration ellipse rescale dropped: the ellipse check
#        fails on the binned cases (the pre-S10 defect this fixture pins).
#   NC5  transformedCalibration bounds-net `inside` inverted: R2's asserted
#        refusal never throws → the harness fails "R2 … must refuse".
#   NC6  DataCubeDerivation.compose scan-offset addition dropped: the
#        `scancrop` derivation-attribute comparison fails.
#   NC7  DataCubeDerivation.compose scan offsets y↔x swapped: `scancrop`'s
#        composed offsets are (3, 2), so the swap fails the same comparison
#        (survived the symmetric first version — Gate B finding 4).
#
# STATED LIMIT (Gate B finding 5): every detector here is SQUARE, so an axis
# swap inside the writer's bounds NET is invisible to this harness — it is
# caught by tools/preprocessing-export-test's 5×7 detector, which runs in the
# same `scientific` aggregate. The centroid arbiter itself IS swap-sensitive
# (the beam sits off both axes).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" export

for library in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$library.dylib" "$WORK/"
  codesign -f -s - "$WORK/$library.dylib" 2>/dev/null
done

xcrun swiftc -parse-as-library -o "$WORK/harness" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
# stderr stays OPEN, unlike the sibling runner: a refusal's text is the
# diagnostic (the S1 lesson), and NC5's first live run proved a discarded
# stderr turns a named refusal into a bare exit 133.
"$WORK/harness" "$WORK"

PYTHONPATH="$REPO/References/py4DSTEM-dev" \
  "$PYTHON_BIN" \
  verify_py4dstem.py "$WORK"
