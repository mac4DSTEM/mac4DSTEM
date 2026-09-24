#!/bin/zsh
# Lattice-based Q + ellipse calibration feasibility probe
# (docs/archive/v4/lattice-calibration-feasibility-2026-09-24.md). See
# lattice_fit.py's docstring. `diagnostic`: it reads peak dumps from
# tools/matrix-orientation-probe --dump-peaks, which need machine-local cubes.
# Sources: none from sources.manifest — pure numpy on a JSON dump.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
exec "$PYTHON_BIN" "$REPO/tools/lattice-calibration-probe/lattice_fit.py" "$@"
