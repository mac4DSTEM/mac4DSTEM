#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-training-dataset-campaign.XXXXXX")"
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

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" core
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/training-dataset-campaign/main.swift" \
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
