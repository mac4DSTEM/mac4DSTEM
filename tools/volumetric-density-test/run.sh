#!/bin/zsh
# diagnostic: T6 of docs/archive/v4/volumetric-density-preregistration-2026-09-28.md
#
# Synthetic foil of zero-thickness plates of known N_V, counted through the
# app's own PrecipitateSegmentation.classObjects / PrecipitateStatistics.density,
# scoring four volumetric-density estimators. Every parameter is fixed by §7
# of the pre-registration; see main.swift's header. `diagnostic`: it needs no
# machine-local data but is a measurement about estimators, not a gated
# invariant of the code, and it runs for minutes.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-volumetric-density-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# Does not source tools/lib/sources.manifest: it takes three named files, not a group.
# Only Foundation is needed: the two precipitate files plus FloatImage's file
# (PrecipitateSegmentation.labelImage returns a FloatImage). -swift-version 5
# matches MAC4DSTEM_ISOLATION_FLAGS; the default-isolation flag is left out
# because this harness's own main.swift runs its cells on plain threads.
xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -swift-version 5 \
  -o "$WORK/t6" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/Precipitates/PrecipitateStatistics.swift"
"$WORK/t6" "$@"
