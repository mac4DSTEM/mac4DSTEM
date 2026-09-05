#!/bin/zsh
# tools/disk-detector/run.sh — the learned disk detector's tooling (docs/v3-plan.md §3a).
#
#   run.sh [fixture]   default, GATED (run-tests.sh scientific): the committed synthetic fixture only.
#                      Fast, no network, no real data. Proves (1) simulate.py's kernel/correlation port
#                      equals py4DSTEM's pixel for pixel and (2) py4DSTEM's classical detector at the
#                      2026-09-05 settings recovers the drawn centres — then BREAKS the fixture four
#                      ways and requires each break to fail. Exit 0 only if all of that holds.
#   run.sh train | export | check | evaluate   DIAGNOSTIC: machine-local data and GPU time,
#                      the detector's own PyTorch environment (DETECTOR_PYTHON overrides).
#                      Extra arguments go to the script.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
DETECTOR_PYTHON="${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}"

mode="${1:-fixture}"; shift || true
case "$mode" in
  fixture)
    . "$REPO/tools/lib/python.sh"
    resolve_mac4dstem_python "$REPO"          # the pinned py4DSTEM environment: the reference detector
    "$PYTHON_BIN" verify_fixture.py
    for b in shifted-truth swapped-axes dropped-disk wrong-probe; do
      if "$PYTHON_BIN" verify_fixture.py --break "$b" > /dev/null 2>&1; then
        echo "disk-detector: break mode '$b' PASSED the fixture — the fixture is blind to it" >&2; exit 1
      fi
      echo "break $b: fails as required"
    done
    echo "disk-detector fixture: pass, and every break fails" ;;
  train)    exec "$DETECTOR_PYTHON" train.py "$@" ;;
  export)   exec "$DETECTOR_PYTHON" export.py "$@" ;;
  check)    exec "$DETECTOR_PYTHON" check_export.py "$@" ;;
  evaluate) exec "$DETECTOR_PYTHON" evaluate.py "$@" ;;
  *) echo "usage: $0 [fixture|train|export|check|evaluate] [args]" >&2; exit 64 ;;
esac
