#!/bin/zsh
# usage: build.sh <out-binary> <main.swift> [ellipse swift file | head]
# Compiles main.swift against the 'ellipse' source group of the clean HEAD copy
# (gates/R-head/mac4DSTEM), swapping in a variant of EllipseCalibration.swift.
set -e
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/9a75d16e-2daa-42dd-9da7-edb11d848287/scratchpad
REPO=$SP/gates/R-head/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
SRCS=("${MAC4DSTEM_SOURCES[@]}")
if [[ ${3:-head} != head ]]; then
  SRCS=("${(@)SRCS:#*Analysis/EllipseCalibration.swift}" "$3")
fi
xcrun swiftc -O -package-name mac4DSTEM -o "$1" "$2" "${SRCS[@]}" -framework Accelerate
