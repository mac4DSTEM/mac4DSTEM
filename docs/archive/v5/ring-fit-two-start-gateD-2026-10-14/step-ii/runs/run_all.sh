#!/bin/zsh
# Step (ii): build rf2 for every variant, then run every set x variant (8 at a time). Exit codes in logs/<set>_<v>.exit.
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
cd $SP/ii
for v in head a b none c b2 s cb cs cbs; do
  $SP/heavy-build.sh build/rf2-$v.log $SP/harness/build.sh bin/rf2-$v $SP/lanes/RF2/src/main.swift $v || echo "BUILD FAIL $v"
done
typeset -A DIR
DIR=(A $SP/data/plantsA B $SP/data/plantsB C $SP/lanes/RF/data/plantsC P $SP/lanes/RF/data/plantsP N $SP/lanes/RF/data/plantsN T $SP/lanes/RF/data/plantsT S3 $SP/lanes/RF2/data/plantsS3 S4 $SP/lanes/RF2/data/plantsS4)
jobs=()
for s in P A B C N T S3 S4; do for v in c cbs cb cs head a b none b2 s; do jobs+=("$s $v ${DIR[$s]}"); done; done
printf '%s\n' "${jobs[@]}" | xargs -P 8 -L 1 zsh -c 'bin/rf2-$1 $2 all > logs/$0_$1.log 2> logs/$0_$1.err; echo $? > logs/$0_$1.exit'
echo ALLDONE > logs/ALLDONE
