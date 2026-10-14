#!/bin/zsh
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
for S in C P N T; do ( ./bin/est /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF/data/plants$S all > logs/est_$S.log 2> logs/est_$S.err; echo $? > logs/est_$S.exit ) & done
wait
