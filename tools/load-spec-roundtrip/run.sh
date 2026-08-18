#!/bin/zsh
# Stage L6 (docs/load-pipeline-plan.md): a load specification must survive the
# session sidecar unchanged, and what comes back must be APPLIED to the source
# rather than used to re-derive from reduced data. See the header of main.swift
# for why the comparison is on the applied view, not only on the JSON.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
SRC="$REPO/mac4DSTEM/Core/Data"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "$SRC/DatasetDescriptor.swift" \
  "$SRC/DiffractionPattern.swift" \
  "$SRC/FourDDataSource.swift" \
  "$SRC/LoadSpecification.swift" \
  "$SRC/Calibration.swift" \
  "$SRC/CalibrationReReference.swift" \
  main.swift

"$WORK/harness"
