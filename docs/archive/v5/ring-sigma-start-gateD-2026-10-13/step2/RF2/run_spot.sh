#!/bin/zsh
# runs all four variants over the spot lists; one background job per variant
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
for v in head a b ab; do
  ( for S in C P N T; do ./bin/rf2-$v /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF/data/plants$S spot_$S.txt > logs/spot_${S}_$v.log 2> logs/spot_${S}_$v.err; echo $? > logs/spot_${S}_$v.exit; done; echo done > logs/spot_$v.done ) &
done
wait
