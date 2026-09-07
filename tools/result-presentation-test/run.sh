#!/bin/zsh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-result-presentation.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" presentation
xcrun swiftc -package-name mac4DSTEM \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/result-presentation-test/main.swift" \
  -o "$TMP/result-presentation-test" -framework Accelerate
"$TMP/result-presentation-test"
