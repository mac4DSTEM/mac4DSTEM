#!/bin/zsh
# usage: classonly.sh <copy-name>   — xcodebuild test of EllipseNoisyRingTests only, NOT -quiet and not parallel,
# so the assertion messages are printed in the log. Same project/scheme/config/flags as run-tests.sh unit_tests otherwise.
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
n=$1; root=$SP/gates/$n/mac4DSTEM; work=$SP/gates/$n/tmp/class-dd
rm -rf "$work"
export TMPDIR=$SP/gates/$n/tmp
xcodebuild test -project "$root/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$work" \
  -only-testing:mac4DSTEMTests/EllipseNoisyRingTests -parallel-testing-enabled NO \
  SWIFT_OPTIMIZATION_LEVEL=-O CODE_SIGNING_ALLOWED=NO
rc=$?
rm -rf "$work"
exit $rc
