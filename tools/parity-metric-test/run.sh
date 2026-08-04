#!/bin/zsh
# Gate the ACOM parity metric itself.
#
# The campaign (tools/training-dataset-campaign/run.sh) is deliberately not in
# tools/run-tests.sh — it needs the real multi-GB datasets. But the metric its
# records are computed with is pure algebra with no data dependency, and it is
# exactly what silently broke before: a misplaced symmetry operator made the
# comparator blind to the lab-frame difference it existed to measure. That is
# cheap to gate, so it is gated here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tools/lib/python.sh"
resolve_mac4dstem_python "$ROOT"
exec "$PYTHON_BIN" "$ROOT/tools/training-dataset-campaign/test_parity_metric.py"
