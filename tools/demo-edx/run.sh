#!/bin/zsh
# No tools/lib/sources.manifest: this harness compiles no Swift; it is Python only (generator + checker).
# tools/demo-edx/run.sh — builds the SIMULATED 4D-STEM + EDX dataset (v5.0 WP2 lane S, ADR 055) and checks it.
#
# WHY A NEW DIRECTORY: tools/demo-dataset writes the 4D cube only; this adds the EDX forward model, the GMS-style
# multi-object .dm4 writer (the layout of docs/archive/v5/4d-edx-file-structure-2026-10-05.md §4a) and the HyperSpy
# .hspy pair (§4b). It IMPORTS demo-dataset/make_demo.py for the recipes and the reflection geometry; it does not copy them.
#
# DIAGNOSTIC, not gated (tools/run-tests.sh inventory's `diagnostic` list): it needs machine-local Python and
# References/demo-dataset/reflections.json (run tools/demo-dataset/run.sh once), and writes ~400 MB under References/.
#
# Python for the generator: the repo's resolver (numpy, scipy, h5py, Pillow — make_demo imports Pillow).
# Python for the check (S1/S2): needs rsciio + h5py + numpy; set CHECK_PYTHON=/path/to/python (skipped if unset and
# the generator's python has no rsciio).
#
# Usage: run.sh [output-dir]   (default: References/demo-edx)
#        run.sh --tiny-fixture  (rewrites mac4DSTEMTests/Fixtures/demo-edx-tiny.{dm4,truth.json}, 115 kB)
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
"$PYTHON_BIN" -c 'import h5py, PIL, numpy' >/dev/null 2>&1 || { echo "demo-edx needs numpy, h5py and Pillow. Set PYTHON=/path/to/python." >&2; exit 1; }
REFL="$REPO/References/demo-dataset/reflections.json"
[[ -f "$REFL" ]] || { echo "missing $REFL — run tools/demo-dataset/run.sh first." >&2; exit 1; }

if [[ "${1:-}" == "--tiny-fixture" ]]; then
  "$PYTHON_BIN" sim_edx.py --reflections "$REFL" --out-dir "$REPO/mac4DSTEMTests/Fixtures" --tiny
  exit 0
fi
OUT_DIR="${1:-$REPO/References/demo-edx}"
mkdir -p "$OUT_DIR"
echo "== generating (64 x 48 scan, 128^2 detector, 4096 channels) =="
"$PYTHON_BIN" sim_edx.py --reflections "$REFL" --out-dir "$OUT_DIR" --seed 42
CHECK="${CHECK_PYTHON:-$PYTHON_BIN}"
if "$CHECK" -c 'import rsciio' >/dev/null 2>&1; then
  echo "== checks S1 (rsciio round trip) and S2 (window counts vs the model, exact Poisson) =="
  "$CHECK" check_edx.py "$OUT_DIR"
else
  echo "== rsciio not importable in $CHECK: checks skipped (set CHECK_PYTHON) =="
fi
ls -la "$OUT_DIR"
