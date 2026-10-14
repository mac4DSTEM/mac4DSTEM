#!/bin/zsh
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
# full-parameter reruns (head and a) over all of P and T; four background jobs
for S in P T; do for v in head a; do
  ( ./bin/rf2-$v /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF/data/plants$S all > logs/full_${S}_$v.log 2> logs/full_${S}_$v.err; echo $? > logs/full_${S}_$v.exit ) &
done; done
wait
