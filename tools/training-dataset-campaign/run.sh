#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$ROOT/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

SRC="$ROOT/mac4DSTEM/Core"
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "$SRC/Data/HDF5Types.swift" "$SRC/Data/H5Reader.swift" \
  "$SRC/Data/DatasetDescriptor.swift" "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Data/FourDDataSource.swift" "$SRC/Data/FourDArray.swift" "$SRC/Data/ResidentCube.swift" "$SRC/Data/LoadSpecification.swift" \
  "$SRC/Data/Calibration.swift" "$SRC/Data/DisplayedProduct.swift" \
  "$SRC/Data/BraggVectorEMDWriter.swift" \
  "$SRC/Data/SessionReplayRecord.swift" \
  "$SRC/Compute/AnalysisCancellationToken.swift" "$SRC/Compute/FFT1D.swift" \
  "$SRC/Compute/FFT2D.swift" "$SRC/Compute/MatrixDFTCorrelation.swift" \
  "$SRC/Compute/MetalEngine.swift" \
  "$SRC/Analysis/ProbeKernel.swift" "$SRC/Analysis/DiskDetection.swift" \
  "$SRC/Analysis/TiledDiskDetection.swift" "$SRC/Analysis/VirtualDetector.swift" \
  "$SRC/Analysis/OriginCalibration.swift" "$SRC/Analysis/RotationCalibration.swift" \
  "$SRC/Analysis/EllipseCalibration.swift" "$SRC/Analysis/DPC.swift" \
  "$SRC/Analysis/StrainMapping.swift" "$SRC/Analysis/QCalibration.swift" \
  "$SRC/Analysis/ParallaxPreprocessing.swift" \
  "$SRC/Analysis/OrientationResult.swift" \
  "$SRC/Crystal/ScatteringFactors.swift" "$SRC/Crystal/Crystal.swift" \
  "$SRC/Crystal/CrystalModel.swift" \
  "$SRC/Crystal/OrientationPlan.swift" "$SRC/Crystal/OrientationMatcher.swift" \
  "$ROOT/tools/training-dataset-campaign/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$WORK/harness" 2>/dev/null

if (( $# > 0 )); then
  files=("$@")
else
  files=("$ROOT"/References/training_dataset/*.h5(N))
fi
if (( ${#files} == 0 )); then
  echo "SKIP: no training datasets"; exit 0
fi
absolute_files=()
for file in "${files[@]}"; do
  absolute_files+=("${file:A}")
done

OUTPUT="$WORK/output"
mkdir -p "$OUTPUT"
cd "$WORK"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" \
  /usr/bin/time -l ./harness "$OUTPUT" \
  "$ROOT/tools/training-dataset-campaign/manifest.json" "${absolute_files[@]}" \
  2> campaign.log | sed '/^\[MetalEngine\]/d' > report.json

source "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"
"$PYTHON_BIN" "$ROOT/tools/training-dataset-campaign/verify_py4dstem.py" "$OUTPUT" \
  > py4dstem.log

if [[ -n "${MAC4DSTEM_CAMPAIGN_REPORT_OUTPUT:-}" ]]; then
  cp report.json "$MAC4DSTEM_CAMPAIGN_REPORT_OUTPUT"
fi
if [[ -n "${MAC4DSTEM_CAMPAIGN_LOG_OUTPUT:-}" ]]; then
  cp campaign.log "$MAC4DSTEM_CAMPAIGN_LOG_OUTPUT"
fi
if [[ -n "${MAC4DSTEM_CAMPAIGN_EXPORT_DIR:-}" ]]; then
  mkdir -p "$MAC4DSTEM_CAMPAIGN_EXPORT_DIR"
  cp "$OUTPUT"/*.h5 "$MAC4DSTEM_CAMPAIGN_EXPORT_DIR/"
  cp "$OUTPUT"/*.parity_input.json "$MAC4DSTEM_CAMPAIGN_EXPORT_DIR/" 2>/dev/null || true
fi

# Parity records: recompute the QC-visible products (strain, full-scan ACOM)
# with py4DSTEM from the app's own exported Bragg vectors, and publish the
# machine-readable records where the QC playthrough can cite them. Runs after
# the export copies so a parity failure never destroys the evidence needed to
# diagnose it. MAC4DSTEM_PARITY_REPORT_ONLY=1 records without gating
# (tolerance work); MAC4DSTEM_PARITY_ACOM_STRIDE trades ACOM comparison
# density for time.
RECORDS="$ROOT/References/parity_records/latest"
mkdir -p "$RECORDS"
parity_flags=()
if [[ -n "${MAC4DSTEM_PARITY_REPORT_ONLY:-}" ]]; then
  parity_flags+=(--report-only)
fi
"$PYTHON_BIN" "$ROOT/tools/training-dataset-campaign/parity_py4dstem.py" \
  "$OUTPUT" "$RECORDS" \
  --acom-stride "${MAC4DSTEM_PARITY_ACOM_STRIDE:-4}" \
  "${parity_flags[@]}" 2>&1 | tee parity.log

cat campaign.log >&2
cat py4dstem.log >&2
cat report.json
