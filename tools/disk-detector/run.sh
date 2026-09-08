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
#                      Extra arguments go to the script. `check` exits 1 outside its tolerance (C6).
#   run.sh ingredients --bullseye <h5> --ws2 <h5> --out <npz>   the trainer's npz (textured backgrounds)
#   run.sh label --cube <h5> --dataset <path> --ingredient bullseye|ws2 --out labels/<name>.json
#                      the click tool for the frozen hand-labelled test set (owner's data, gitignored;
#                      the JSON's sha256 and counts go into the evidence file). Both in the py4DSTEM env.
# Nothing to take from tools/lib/sources.manifest: this harness is Python only, it compiles no Swift.
# py4DSTEM is the LOCK (References/py4DSTEM-dev, fetch-py4dstem.sh), put on PYTHONPATH here;
# the conda environment's own py4DSTEM (0.14.17) is not the reference (decisions.md, 2026-09-07).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
DETECTOR_PYTHON="${DETECTOR_PYTHON:-$HOME/miniconda3/envs/disk-detector/bin/python}"

mode="${1:-fixture}"; shift || true
case "$mode" in
  fixture)
    . "$REPO/tools/lib/python.sh"
    resolve_mac4dstem_python "$REPO"          # the pinned py4DSTEM environment: the reference detector
    export PYTHONPATH="$REPO/References/py4DSTEM-dev${PYTHONPATH:+:$PYTHONPATH}"
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
  evaluate)
    # two stages: the net's heatmaps in the detector env, then py4DSTEM's refinement and the classical
    # comparison in the pinned py4DSTEM env (torch is not installed there, py4DSTEM not here).
    . "$REPO/tools/lib/python.sh"; resolve_mac4dstem_python "$REPO"
    "$DETECTOR_PYTHON" evaluate.py --stage net "$@"
    export PYTHONPATH="$REPO/References/py4DSTEM-dev${PYTHONPATH:+:$PYTHONPATH}"
    exec "$PYTHON_BIN" evaluate.py --stage compare "$@" ;;
  ingredients)
    . "$REPO/tools/lib/python.sh"; resolve_mac4dstem_python "$REPO"
    exec "$PYTHON_BIN" simulate.py ingredients "$@" ;;
  label)
    . "$REPO/tools/lib/python.sh"; resolve_mac4dstem_python "$REPO"
    exec "$PYTHON_BIN" label_centres.py "$@" ;;
  *) echo "usage: $0 [fixture|train|export|check|evaluate|ingredients|label] [args]" >&2; exit 64 ;;
esac
