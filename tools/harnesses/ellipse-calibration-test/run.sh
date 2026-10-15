#!/bin/zsh
set -euo pipefail
# reference.py source-locks py4DSTEM's ellipse/profile fit conventions in
# process/calibration/ellipse.py and process/utils/elliptical_coords.py and
# emits synthetic ring, profile, overlap, and spotty-ring fixtures; the Swift
# harness runs DiffractoKit's (DiffractoGeometry) EllipseCalibration fit1D/fitBestAvailable
# against them, checking fitted parameters, insufficient-signal/coverage
# refusals, and the sparse-coverage "fit anyway" path. Since 2026-10-12 it also
# plants a clean sweep of 48 single rings (512x512 and 384x512, R 80-200 px,
# circle / 1 % / 3 % ellipse, unbroken or a 60 degree arc missing; numpy, raw
# float32 files in $WORK/sweep) and solves each with scipy: every ring must
# FIT (fit1D's stop rule once threw didNotConverge at the optimum on about one
# ring in seven; the old rule refused 7 of these 48 on 2026-10-12), the centre
# must be within 0.05 px of the plant, and fit1D must equal scipy's optimum of
# the same objective (which also pins the objective). The radius bias is printed.
# swiftc runs with -O (added 2026-10-12): without it the harness alone takes
# 96 s on the M5 Pro, with it all of run.sh takes 15 s, and the harness prints
# the same lines either way. Run with no arguments:
# tools/harnesses/ellipse-calibration-test/run.sh. Listed in the `scientific` array of
# tools/run-tests.sh, so it runs under `tools/run-tests.sh scientific` (and
# `all`). Needs numpy and scipy for the sweep (tools/lib/python.sh finds an
# interpreter with both). Pass condition: each case prints "PASS: ..."; fail()
# prints "FAIL: ..." and exits 1; the final line is
# "ellipse-calibration-test: all passed".
cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-ellipse-calibration-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"

"$PYTHON_BIN" reference.py "$WORK/sweep" > "$WORK/expected.json"
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
xcrun swiftc -O -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness" "$WORK/expected.json"
