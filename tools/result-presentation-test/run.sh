#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-result-presentation.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

xcrun swiftc -package-name mac4DSTEM \
  "$ROOT/mac4DSTEM/Core/Data/ResultPresentation.swift" \
  "$ROOT/tools/result-presentation-test/main.swift" \
  -o "$TMP/result-presentation-test"
"$TMP/result-presentation-test"
