#!/bin/zsh
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
cd $SP/lanes/RF3
typeset -A DIR
DIR=(A $SP/data/plantsA B $SP/data/plantsB C $SP/lanes/RF/data/plantsC P $SP/lanes/RF/data/plantsP N $SP/lanes/RF/data/plantsN T $SP/lanes/RF/data/plantsT S3 $SP/lanes/RF2/data/plantsS3 S4 $SP/lanes/RF2/data/plantsS4)
jobs=()
for s in S4 S3 T N C P; do for v in none a c; do jobs+=("$s $v ${DIR[$s]}"); done; done
printf '%s\n' "${jobs[@]}" | xargs -P 4 -L 1 zsh -c 'bin/rf3-$1 $2 all > logs/$0_$1.log 2> logs/$0_$1.err; echo $? > logs/$0_$1.exit'
echo ALLDONE > logs/ALLDONE
