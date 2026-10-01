#!/bin/zsh
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
until mkdir "$SP/heavy.lock" 2>/dev/null; do sleep 15; done
trap 'rmdir "$SP/heavy.lock"' EXIT
cd /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
start=$(date +%s)
tools/singleslice-ptychography-test/run.sh > "$SP/R/$1" 2>&1
echo "EXIT=$?" >> "$SP/R/$1"
echo "seconds=$(( $(date +%s) - start ))" >> "$SP/R/$1"
