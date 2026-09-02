#!/bin/zsh
# v2 S13 (docs/v2-release.md §8): the Q-calibration gate fixture.
#
# Pins the four things S13 changed about what the app is willing to claim:
#   1. the robust (iteratively-trimmed) origin fit,
#   2. the ONE derivation of "which origin do I re-centre on?" and its kind,
#   3. the sane-origin / measure-Q split, including the refusal of a stand-in
#      origin,
#   4. the estimator's own plausibility checks and their measured thresholds.
#
# Every case is synthetic and hand-checkable — the real-data numbers behind the
# thresholds live in tools/origin-fit-diagnostics, which does not gate because
# it needs the gitignored training data. This one gates.
#
# Sources come from tools/lib/sources.manifest and compile with the app's
# isolation flags (the S2 conventions).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

mac4dstem_sources "$REPO" qcalibration

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  "${MAC4DSTEM_SOURCES[@]}" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

"$WORK/harness"
