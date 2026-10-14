#!/bin/zsh
# usage: build.sh <out-binary> <main.swift> <variant: head|a|b|ab>
# Compiles main.swift against the 'ellipse' source group of the clean HEAD copy ($SP/gates/head/mac4DSTEM),
# swapping in patches/EllipseCalibration.<variant>.swift unless the variant is head.
set -e
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
REPO=$SP/gates/head/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
SRCS=("${MAC4DSTEM_SOURCES[@]}")
if [[ $3 != head ]]; then
  SRCS=("${(@)SRCS:#*Analysis/EllipseCalibration.swift}" "$SP/patches/EllipseCalibration.$3.swift")
fi
xcrun swiftc -O -package-name mac4DSTEM -o "$1" "$2" "${SRCS[@]}" -framework Accelerate
