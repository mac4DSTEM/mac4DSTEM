#!/bin/zsh
# usage: mkcopies.sh — builds the eight gate copies G-<name> (HEAD archive + patch file + test file)
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
G=$SP/lanes/G
mk() { # name patchvariant testdir|-
  local name=G-$1 v=$2 t=$3
  local d=$($SP/gate-copy.sh $name)
  if [[ $v != head ]]; then cp $SP/patches/EllipseCalibration.$v.swift $d/mac4DSTEM/Core/Analysis/EllipseCalibration.swift; fi
  if [[ $t != - ]]; then cp $G/$t/EllipseNoisyRingTests.swift $d/mac4DSTEMTests/EllipseNoisyRingTests.swift; fi
  echo "$name: $d  patch=$v test=$t"
}
mk head-c head test-c
mk a-c a test-c
mk c c test-c
mk cbs cbs test-c
mk s s test-s
mk head-s head test-s
mk b2 b2 test-b2
mk none none -
