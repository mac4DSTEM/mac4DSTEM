#!/bin/zsh
# cb gate copy: HEAD + patch cb + lane G's test-c; unit, core, then the ellipse tool. Exits in <log>.exit.
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
C=$($SP/gate-copy.sh cb)
cp $SP/patches/EllipseCalibration.cb.swift $C/mac4DSTEM/Core/Analysis/EllipseCalibration.swift
cp $SP/lanes/G/test-c/EllipseNoisyRingTests.swift $C/mac4DSTEMTests/EllipseNoisyRingTests.swift
L=$SP/lanes/CB/logs
TMPDIR=$SP/gates/cb/tmp $SP/heavy.sh $L/cb-unit.log $C/tools/run-tests.sh unit
TMPDIR=$SP/gates/cb/tmp $SP/heavy-build.sh $L/cb-core.log $C/tools/run-tests.sh core
TMPDIR=$SP/gates/cb/tmp $SP/heavy-build.sh $L/cb-tool.log $C/tools/ellipse-calibration-test/run.sh
grep -rh 'func test' $C/mac4DSTEMTests | wc -l > $L/cb-functest.txt
rm -rf $SP/gates/cb/tmp/* $C/.build
echo done > $L/ALLDONE
