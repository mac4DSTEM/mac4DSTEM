#!/bin/zsh
# usage: build.sh <variant cb|cbg> <rf2|fit>
AG=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/7af9476c-5986-457d-8367-3bdc05d2d20d/scratchpad/lanes/AG
REPO=$AG/copies/$1/mac4DSTEM
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" ellipse
xcrun swiftc -O -package-name mac4DSTEM -o $AG/bin/$2-$1 $AG/src/$2/main.swift "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate
