#!/bin/zsh
# tools/thronsen-dataset — step 3 of docs/v3-vector-matching-plan.md: fetch a
# stride-3 subsample of Thronsen et al.'s datasetA and its ground truth from
# Zenodo (CC BY 4.0) into References/thronsen-datasetA/, then run the
# shipped matcher on it through tools/phase-map-probe --thronsen and score by
# their metric. DIAGNOSTIC: needs the network (7.4 GB streamed, ~50 min at
# 5 MB/s), a Python with h5py + numpy + requests, and answers a question
# about a dataset, not an invariant of the code. WHY A NEW DIRECTORY: like
# tools/demo-dataset, this WRITES a datacube; no existing runner fetches one.
# Sources: NOT through tools/lib/sources.manifest — this runner compiles no
# Swift itself; the matcher it drives is built by tools/phase-map-probe/run.sh,
# which does source the manifest (phasevectors readers).
#
# usage: run.sh [fetch|probe|all]   (default all; probe needs the fetch)
set -euo pipefail
cd "$(dirname "$0")"; REPO="$(cd ../.. && pwd)"
OUT="$REPO/References/thronsen-datasetA"; mkdir -p "$OUT"
. "$REPO/tools/lib/python.sh"; resolve_mac4dstem_python "$REPO"
MODE="${1:-all}"
if [[ "$MODE" == fetch || "$MODE" == all ]]; then
  "$PYTHON_BIN" make_truth.py "$OUT/truth_stride3.json" 3
  "$PYTHON_BIN" subsample.py "$OUT/datasetA_stride3.h5" 3
fi
if [[ "$MODE" == probe || "$MODE" == all ]]; then
  # Probe radius 2 px (their patterns are 2x2-rebinned to 0.01904 Å⁻¹/px), the
  # data's own mask radius as the reach, and the shipped detection threshold
  # unless one is given: run.sh probe --min-relative 0.02
  shift $(( $# > 0 ? 1 : 0 )) || true
  "$REPO/tools/phase-map-probe/run.sh" "$OUT/datasetA_stride3.h5" 2 0.01904 \
    --thronsen "$OUT/truth_stride3.json" --reach 0.68 "$@"
fi
