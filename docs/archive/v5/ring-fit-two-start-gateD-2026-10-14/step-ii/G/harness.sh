#!/bin/zsh
# tools/ellipse-calibration-test/run.sh in the copies none, c, b2, s, cbs; each its own log + .exit, via heavy-build.sh (no test host)
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
L=$SP/lanes/G/logs
for n in none c b2 s cbs; do
  TMPDIR=$SP/gates/G-$n/tmp $SP/heavy-build.sh $L/$n-harness.log $SP/gates/G-$n/mac4DSTEM/tools/ellipse-calibration-test/run.sh
done
echo all-done > $L/harness.done
