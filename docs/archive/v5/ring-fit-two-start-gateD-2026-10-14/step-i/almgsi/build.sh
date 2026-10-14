#!/bin/zsh
# usage: build.sh <out-binary> <main.swift> — the 'detection' source group of the clean HEAD copy ($SP/gates/head/mac4DSTEM), as tools/disk-detection-test/run.sh.
set -e
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
REPO=$SP/gates/head/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" detection
xcrun swiftc -O -package-name mac4DSTEM -o "$1" "$2" "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate -framework Metal
