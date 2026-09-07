#!/bin/zsh
# Stage L6 (docs/load-pipeline-plan.md): a load specification must survive the
# session sidecar unchanged, and what comes back must be APPLIED to the source
# rather than used to re-derive from reduced data. See the header of main.swift
# for why the comparison is on the applied view, not only on the JSON.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-load-spec-roundtrip.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" replay
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate

"$WORK/harness"
