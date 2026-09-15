#!/bin/zsh
# Compile and run the rotation-null-probe harness (see main.swift).
#
# WHAT THIS MEASURES. RotationCalibration.solve's permutation null
# (`Result.carriesRotation`, RotationCalibration.swift) is a whiteness test,
# not a rotation test: docs/open-items.md's "The rotation null is a
# whiteness test, not a rotation test — Gate B 2026-09-15" entry quotes
# measured certification rates for white noise, box-smoothed noise, a
# per-row descan drift, a specimen edge, a planted 30° rotation and a real
# rotation at several noise levels — but every one of those numbers came
# from a scratch probe that was never checked in. CLAUDE.md's rule is "no
# claim a reader cannot reproduce"; this harness is that instrument.
#
# WHY A NEW DIRECTORY. No existing tools/ runner constructs a
# centre-of-mass field or calls RotationCalibration.solve without a real
# dataset behind it — tools/origin-fit-diagnostics is the nearest cousin
# but needs the gitignored training cubes under References/, and every
# other calibration harness (ellipse-calibration-test, calibration-test,
# calibration-readiness-test) drives a different fit entirely. The six
# fields this probe needs (white noise, box-smoothed noise, row drift, a
# specimen edge, a planted rotation, and a noise sweep on that plant) exist
# nowhere else in tools/.
#
# DIAGNOSTIC, NOT GATED. This measures; it asserts nothing (no `exit 1` on
# a disagreement with the recorded claims) and is not wired into
# tools/run-tests.sh. Runtime is on the order of a couple of minutes.
#
# Env overrides (both optional, both no-ops at their default — used only
# to sanity-check that the harness is not vacuous; see the session's
# report for what moved):
#   ROTATION_PROBE_SEED_OFFSET_A  default 0   — shifts experiment A's seeds
#   ROTATION_PROBE_ANGLE_E        default 30  — experiment E's planted angle (deg)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-rotation-null-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" calibration
# RotationCalibration.swift and its AnalysisCancellationToken parameter type
# are in neither the `calibration` group nor any group that composes it
# (checked: `grep -n RotationCalibration tools/lib/sources.manifest` finds
# nothing) — added explicitly rather than to the manifest, since this probe
# is diagnostic and the manifest's groups are meant for harnesses several
# runners share.
MAC4DSTEM_SOURCES+=(
  "$ROOT/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift"
  "$ROOT/mac4DSTEM/Core/Compute/FFT2D.swift"
  "$ROOT/mac4DSTEM/Core/Analysis/RotationCalibration.swift"
)

xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/probe" \
  "$ROOT/tools/rotation-null-probe/main.swift" \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate
codesign -f -s - "$WORK/probe" 2>/dev/null

"$WORK/probe"
