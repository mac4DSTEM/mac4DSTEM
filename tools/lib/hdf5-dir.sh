#!/bin/zsh
# tools/lib/hdf5-dir.sh — prints the folder holding the three HDF5 frameworks (FormatoLibHDF5, FormatoLibSZ, FormatoLibAEC) that every
# reader harness points FORMATO_HDF5_PATH (the one variable the app and FormatoKit read) into: "$(tools/lib/hdf5-dir.sh)/FormatoLibHDF5.framework/FormatoLibHDF5". They are FormatoKit's
# binary targets (0.4.0), the same files Xcode embeds in the app's Contents/Frameworks. SwiftPM unpacks each XCFramework into
# .build/artifacts/formatokit/<Name>/, apart from the others; libhdf5's load commands are @rpath/FormatoLibSZ.framework/... and
# @rpath/FormatoLibAEC.framework/... with the rpath @loader_path/../../.. (the folder holding the framework), so a harness needs the three
# side by side, which this assembles once per pinned FormatoKit revision in .build/hdf5-frameworks. The frameworks are already ad-hoc signed
# (the app's build re-signs its copies); a harness is not hardened, so it loads them as they are. Resolves the packages when missing.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
art="$ROOT/.build/artifacts/formatokit"
out="$ROOT/.build/hdf5-frameworks"
pin=$(awk '/"identity" : "formatokit"/ {f=1} f && /"revision"/ {gsub(/[",]/, "", $3); print $3; exit}' "$ROOT/Package.resolved")
[[ -n "$pin" ]] || { echo "hdf5-dir.sh: no FormatoKit pin in $ROOT/Package.resolved" >&2; exit 65; }
if [[ "$(cat "$out/.pin" 2>/dev/null)" != "$pin" || ! -f "$out/FormatoLibHDF5.framework/FormatoLibHDF5" ]]; then
  # Resolve first, always: it fetches the zips for the CURRENT pin (a no-op when they are current), so a stale .build/artifacts
  # left by an older pin can never be stamped with the new one.
  (cd "$ROOT" && swift package resolve) >&2
  rm -rf "$out"; mkdir -p "$out"
  for name in FormatoLibHDF5 FormatoLibSZ FormatoLibAEC; do
    src="$art/$name/$name.xcframework/macos-arm64/$name.framework"
    [[ -d "$src" ]] || { echo "hdf5-dir.sh: no $name.framework in $art (swift package resolve failed?)" >&2; exit 65; }
    ditto "$src" "$out/$name.framework"
  done
  echo "$pin" > "$out/.pin"
fi
print -r -- "$out"
