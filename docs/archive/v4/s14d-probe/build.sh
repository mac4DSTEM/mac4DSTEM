#!/bin/zsh
set -euo pipefail
ROOT=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad
W=$SP/s14d/run; mkdir -p $W
. "$ROOT/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
for lib in libhdf5 libsz.2 libaec.0; do cp "$ROOT/$lib.dylib" "$W/"; codesign -f -s - "$W/$lib.dylib" 2>/dev/null; done
python3 $SP/s14d/gen.py $SP/s14d/metal
xcrun -sdk macosx metal -c $SP/s14d/metal/s14d.metal -o $SP/s14d/metal/s14d.air
xcrun -sdk macosx metallib $SP/s14d/metal/s14d.air -o $W/s14d.metallib
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do xcrun -sdk macosx metal -c "$source" -o "$W/${source:t:r}.air"; done
xcrun -sdk macosx metallib "$W"/[A-Z]*.air -o "$W/default.metallib"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" qcalibration
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$W/s14dprobe" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/mac4DSTEM/Core/Data/DisplayedProduct.swift" \
  $SP/s14d/main.swift -framework Accelerate -framework Metal -framework MetalKit
codesign -f -s - "$W/s14dprobe" 2>/dev/null
echo built
