#!/bin/zsh
# builds bin/est from src2/main.swift against the HEAD copy with the exposed patch-a file (run THROUGH heavy.sh)
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
L=$SP/lanes/RF2
REPO=$SP/gates/head/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
SRCS=("${MAC4DSTEM_SOURCES[@]}")
SRCS=("${(@)SRCS:#*Analysis/EllipseCalibration.swift}" "$L/EllipseCalibration.a-exposed.swift")
xcrun swiftc -O -package-name mac4DSTEM -o "$L/bin/est" "$L/src2/main.swift" "${SRCS[@]}" -framework Accelerate && echo built_est
