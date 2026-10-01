#!/bin/zsh
set -uo pipefail
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
until mkdir "$SP/heavy.lock" 2>/dev/null; do sleep 15; done
trap 'rmdir "$SP/heavy.lock"' EXIT
cd "$REPO"
. tools/lib/developer-dir.sh; resolve_mac4dstem_developer_dir
. tools/lib/sources.manifest; mac4dstem_sources "$REPO" ptychography
xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$SP/R/dump/dump2" "$SP/R/dump/main.swift" "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate
echo "EXIT=$?"
