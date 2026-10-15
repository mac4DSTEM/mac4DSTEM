#!/bin/zsh
# tools/disk-detector/run.sh — the learned disk detector's GATED fixture check (run-tests.sh scientific).
#
# The committed synthetic fixture only (mac4DSTEMTests/Fixtures/DiskDetector/fixture/): fast, no network, no real data.
# Proves (1) simulate.py's kernel/correlation port equals py4DSTEM's pixel for pixel and (2) py4DSTEM's classical
# detector at the 2026-09-05 settings recovers the drawn centres, then BREAKS the fixture four ways and requires
# each break to fail. Exit 0 only if all of that holds.
# The training, export, evaluation and labelling tools left the repo: ../_archive/mac4DSTEM/tools/disk-detector/.
# Nothing to take from tools/lib/sources.manifest: this harness is Python only, it compiles no Swift.
# py4DSTEM is the LOCK (References/py4DSTEM-dev, fetch-py4dstem.sh), put on PYTHONPATH here;
# the conda environment's own py4DSTEM (0.14.17) is not the reference (decisions.md, 2026-09-07).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"

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
echo "disk-detector fixture: pass, and every break fails"
