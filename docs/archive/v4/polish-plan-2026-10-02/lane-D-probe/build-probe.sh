#!/bin/zsh
# usage (from the repo root): build-probe.sh <DM4Reader.swift to compile> <out binary>
# Builds the lane-D probe against the repo's `readers` source group with the given DM4Reader.swift
# swapped in: `git show <commit>:mac4DSTEM/Core/Data/DM4Reader.swift > head.swift` for the HEAD reader.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" && . tools/lib/sources.manifest && mac4dstem_sources "$ROOT" readers
SRCS=()
for f in "${MAC4DSTEM_SOURCES[@]}"; do
  if [[ "$f" == */Core/Data/DM4Reader.swift ]]; then SRCS+=("$1"); else SRCS+=("$f"); fi
done
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library "${SRCS[@]}" "$HERE/helpers.swift" "$HERE/main.swift" -o "$2" -framework Accelerate
