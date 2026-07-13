#!/bin/zsh
# Standalone numeric parity harness for the production virtual-detector mask
# builder and Metal kernels. Reference values are source-locked to the checked-
# in py4DSTEM make_detector implementation; no Python packages are required.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

python3 reference.py > "$WORK/expected.json"

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main.
# Build the app's real shader sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MetalEngine.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/VirtualDetector.swift" \
  -framework Metal -framework MetalKit

cd "$WORK"
./harness expected.json
