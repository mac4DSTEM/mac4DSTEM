#!/bin/zsh
# Sequential gate runs, one test host at a time, each through heavy.sh (own slot, own log, own .exit). No pipes on exit codes.
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
L=$SP/lanes/G/logs
run() { # copy-name kind (unit|core)
  local n=G-$1 k=$2 root=$SP/gates/G-$1/mac4DSTEM
  TMPDIR=$SP/gates/$n/tmp $SP/heavy.sh $L/$1-$k.log $root/tools/run-tests.sh $k
}
cls() { # copy-name — class-only rerun for the assertion text
  local n=G-$1
  TMPDIR=$SP/gates/$n/tmp $SP/heavy.sh $L/$1-class.log $SP/lanes/G/classonly.sh $n
}
run head-c unit
run a-c unit
run c unit
run c core
run cbs unit
run cbs core
run s unit
run s core
run head-s unit
run b2 unit
run b2 core
run none unit
run none core
cls head-c
cls a-c
cls head-s
echo all-done > $L/driver.done
