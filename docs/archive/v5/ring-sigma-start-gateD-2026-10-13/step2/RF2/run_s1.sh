#!/bin/zsh
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
for v in head a b ab; do ( ./bin/rf2-$v data/plantsS1 all > logs/S1_$v.log 2> logs/S1_$v.err; echo $? > logs/S1_$v.exit ) & done
wait
