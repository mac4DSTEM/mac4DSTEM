#!/bin/zsh
set -euo pipefail

# reference.py source-locks py4DSTEM's single-slice gradient-descent ptychography operator (overlap
# projection, object/probe update, the DM operator) across process/phase/ptychographic_methods.py,
# phase_base_class.py, singleslice_ptychography.py, and ptychographic_constraints.py; the Swift
# harness runs Core/Analysis/SingleslicePtychography.swift's SingleslicePtychography.reconstruct (GD
# and DM), a position/crop-convention check, error cases, and an origin-shift/circular-shift
# invariant, and (R1, 2026-09-30) the initial probe against py4DSTEM's own ComplexProbe (defocus, astigmatism, every term to fifth
# order; reference.py imports References/py4DSTEM-dev for it) plus the aberration-free probe's bit-for-bit hashes from git 02174c9c.
# Run with no arguments: tools/singleslice-ptychography-test/run.sh. Listed in both the
# scientific and campaign arrays of tools/run-tests.sh (and all). Pass condition: final line
# singleslice-ptychography-test: all passed.

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-singleslice-ptychography-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py > "$WORK/expected.json"
# R3 (2026-10-01): a synthetic cube with a known object and a defocused probe, plus py4DSTEM's own runs on it (truth.py's docstring).
"$PYTHON_BIN" truth.py > "$WORK/truth.json"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ptychography
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json" "$WORK/truth.json"
