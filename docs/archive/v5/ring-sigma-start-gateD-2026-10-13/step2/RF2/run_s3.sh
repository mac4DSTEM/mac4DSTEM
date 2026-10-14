#!/bin/zsh
cd /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF2
for v in head a b ab; do ( ./bin/rf2-$v data/plantsS3 all > logs/S3_$v.log 2> logs/S3_$v.err; echo $? > logs/S3_$v.exit ) & done
wait
