#!/bin/zsh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
if [[ ! -x "$HERE/gated" ]]; then
  . "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
  . "$REPO/tools/lib/sources.manifest"
  mac4dstem_sources "$REPO" readers parallax rotation
  for lib in libhdf5 libsz.2 libaec.0; do cp "$REPO/$lib.dylib" "$HERE/"; codesign -f -s - "$HERE/$lib.dylib" 2>/dev/null; done
  xcrun swiftc -O -swift-version 5 -package-name mac4DSTEM -parse-as-library -module-cache-path "$HERE/mc" -o "$HERE/gated" \
    "$HERE/main.swift" "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate
  codesign -f -s - "$HERE/gated" 2>/dev/null
fi
export MAC4DSTEM_HDF5_PATH="$HERE/libhdf5.dylib"
"$HERE/gated" "$@"
