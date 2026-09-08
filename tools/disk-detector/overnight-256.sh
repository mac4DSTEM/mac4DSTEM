#!/bin/zsh
# tools/disk-detector/overnight-256.sh — the unattended 256-px retrain chain (C7 2026-09-07):
#   ingredients --size 256 -> train --size 256 -> export -> check -> evaluate --asset --labels
# each step's stdout+stderr logged to <outdir>, the chain stopping at the FIRST non-zero exit (the
# committed 128-px fixture and its `run.sh fixture` gate are untouched by any of this). The owner's
# frozen hand-labelled bullseye set (C6, tools/disk-detector/labels/, gitignored) is used if
# present; otherwise evaluate runs without --labels and every other number still comes out.
#
#   tools/disk-detector/overnight-256.sh <outdir>
#
# <outdir> holds: ingredients-256.npz, run/ (train.py's --out, so run/config.json, run/best.pt,
# run/export/*.aimodel), evaluate/ (evaluate.json + PNGs), and 01-*.log .. 05-*.log, one per step.
# ~90 minutes of training dominate the wall clock (--max-minutes 90); a training-only rerun after a
# mid-run failure can pass run.sh train --resume run/last.pt instead of starting over.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:?usage: overnight-256.sh <outdir>}"
mkdir -p "$OUT"
REPO="$(cd ../.. && pwd)"
BULLSEYE="$REPO/References/training_dataset/calibrationData_bullseyeProbe.h5"
WS2="$REPO/References/training_dataset/polycrystal_2D_WS2.h5"
LABELS="labels/bullseye-2026-09-08.json"   # the owner's frozen hand-labelled set (C6), if it exists
RUN="$OUT/run"
INGREDIENTS="$OUT/ingredients-256.npz"

step_soft() {
  local n="$1" name="$2" log="$OUT/$1-$2.log"
  shift 2
  echo "=== step $n: $name -> $log ===" | tee -a "$OUT/overnight.log"
  "$@" > "$log" 2>&1
}

step() {
  local n="$1" name="$2" log="$OUT/$1-$2.log"
  shift 2
  echo "=== step $n: $name -> $log ===" | tee -a "$OUT/overnight.log"
  if ! "$@" > "$log" 2>&1; then
    echo "overnight-256: step $n ($name) FAILED — see $log" | tee -a "$OUT/overnight.log" >&2
    tail -n 40 "$log" >&2
    exit 1
  fi
}

step 01 ingredients ./run.sh ingredients --size 256 --bullseye "$BULLSEYE" --ws2 "$WS2" --out "$INGREDIENTS"
step 02 train        ./run.sh train --size 256 --width 12 --max-minutes 90 --ingredients "$INGREDIENTS" --out "$RUN"
step 03 export       ./run.sh export --run "$RUN"
# The check is recorded, not fatal: the export writes every variant, and the GPU top-k delegate
# and the stateful asset are known to segfault (README), which would stop the chain before the
# evaluation everything else exists for. Read 04-check.log and run/export/check.json in the morning.
if ! step_soft 04 check ./run.sh check --run "$RUN"; then
  echo "overnight-256: check exited non-zero (see $OUT/04-check.log) — continuing to evaluate" | tee -a "$OUT/overnight.log" >&2
fi

EVAL_ARGS=(--run "$RUN" --out "$OUT/evaluate" --ingredients "$INGREDIENTS" --bullseye "$BULLSEYE" --ws2 "$WS2"
           --asset "$RUN/export/disk-detector-heatmap-b32.aimodel" --threshold 0.9)
if [[ -f "$LABELS" ]]; then
  EVAL_ARGS+=(--labels "$LABELS")
else
  echo "overnight-256: $LABELS not found — evaluating without --labels (the frozen hand-labelled row will be missing)" | tee -a "$OUT/overnight.log" >&2
fi
step 05 evaluate ./run.sh evaluate "${EVAL_ARGS[@]}"

echo "overnight-256: done. evaluate JSON: $OUT/evaluate/evaluate.json" | tee -a "$OUT/overnight.log"
