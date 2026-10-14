#!/bin/zsh
AG=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/7af9476c-5986-457d-8367-3bdc05d2d20d/scratchpad/lanes/AG
L=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
for s in heavy.1 heavy.2; do if mkdir $L/$s 2>/dev/null; then slot=$L/$s; break; fi; done
[[ -z $slot ]] && { echo NOSLOT > $AG/logs/build.exit; exit 75; }
for v in cb cbg; do for h in rf2 fit; do $AG/build.sh $v $h > $AG/logs/build-$h-$v.log 2>&1; echo $? > $AG/logs/build-$h-$v.exit; done; done
rmdir $slot; echo done > $AG/logs/build.done
