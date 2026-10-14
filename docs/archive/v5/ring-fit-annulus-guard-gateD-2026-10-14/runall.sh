#!/bin/zsh
AG=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/7af9476c-5986-457d-8367-3bdc05d2d20d/scratchpad/lanes/AG
OLD=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
L=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
for s in heavy.1 heavy.2; do if mkdir $L/$s 2>/dev/null; then slot=$L/$s; break; fi; done
[[ -z $slot ]] && { echo NOSLOT > $AG/logs/run.exit; exit 75; }
cd $AG
typeset -A DIR
DIR=(A $OLD/data/plantsA B $OLD/data/plantsB C $OLD/lanes/RF/data/plantsC P $OLD/lanes/RF/data/plantsP N $OLD/lanes/RF/data/plantsN T $OLD/lanes/RF/data/plantsT S3 $OLD/lanes/RF2/data/plantsS3 S4 $OLD/lanes/RF2/data/plantsS4)
# real sources: key file rows cols centreRow centreCol annulifile
typeset -A CEN
CEN=(au "64 64 28.47 34.43" s1 "64 64 31.7953815 31.80266" s2 "64 64 31.7953815 31.80266" s3 "128 128 63.7328357 63.7380687" s4 "128 128 63.8875198 63.8874969" s5 "32 32 15.001983 15.162129")
jobs=()
for s in P A B C N T S3 S4; do for v in cb cbg; do jobs+=("rf2 $s $v ${DIR[$s]}"); done; done
for v in cb cbg; do
 for s in au s1 s2 s3 s4 s5; do jobs+=("fit $s $v real/$s.f32 ${CEN[$s]} real/$s.ann"); done
 for s in au s3 s4 s5; do jobs+=("fit sw-$s $v real/$s.f32 ${CEN[$s]} real/sw-$s.ann"); done
 for s in a1 w3; do jobs+=("fit sh-$s $v real/au.f32 ${CEN[au]} real/sh-$s.ann"); done
done
printf '%s\n' "${jobs[@]}" | xargs -P 6 -L 1 zsh -c 'k=$0; s=$1; v=$2; shift 2; if [[ $k == rf2 ]]; then bin/rf2-$v $1 all > logs/$s-$v.log 2> logs/$s-$v.err; else bin/fit-$v $1 $2 $3 $4 $5 $6 > logs/$s-$v.log 2> logs/$s-$v.err; fi; echo $? > logs/$s-$v.exit'
rmdir $slot; echo ALLDONE > logs/ALLDONE
