#!/bin/zsh
set -euo pipefail

# Checks Core/Data/Calibration.swift's CalibrationReadinessReport.make: which
# combination of Calibration values and CalibrationProvenance counts as ready,
# that provenance (file/session/manual/mixed) is retained per item, that
# pixel-only metadata is never mistaken for physical q/r calibration, and that
# missing units are never guessed. No py4DSTEM comparison; this is mac4DSTEM's
# own readiness logic. Run with no arguments: tools/calibration-readiness-test/run.sh.
# Listed in the `scientific` array of tools/run-tests.sh, so it runs under
# `tools/run-tests.sh scientific` (and `all`). Pass condition: every `require()`
# holds and the harness prints "calibration-readiness-test: all passed";
# a failed require throws and the process exits non-zero.

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-calibration-readiness-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" calibration
xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
"$WORK/harness"
