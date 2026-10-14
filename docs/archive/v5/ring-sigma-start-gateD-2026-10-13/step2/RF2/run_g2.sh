#!/bin/zsh
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
for T in G0 G1 G3; do for v in head a; do
  ( ./bin/rf2-$v data/plantsC_$T all > logs/C${T}_$v.log 2> logs/C${T}_$v.err; echo $? > logs/C${T}_$v.exit ) &
done; done
wait
