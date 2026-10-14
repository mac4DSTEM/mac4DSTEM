#!/bin/zsh
# Diagnostic build only: candidate (a) with one stderr line per fitAmorphousRing call (the half-maximum start, or nil).
set -e
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
REPO=$SP/gates/head/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
SRCS=("${(@)MAC4DSTEM_SOURCES:#*Analysis/EllipseCalibration.swift}" "$SP/lanes/P5/dbg/EllipseCalibration.a-dbg.swift")
xcrun swiftc -O -package-name mac4DSTEM -o "$SP/lanes/P5/dbg/p5-a-dbg" "$SP/lanes/P5/main.swift" "${SRCS[@]}" -framework Accelerate
