#!/bin/zsh
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
until grep -q "ALL DONE" "$SP/R/mut/all.log"; do sleep 20; done
"$SP/R/mutate2.sh" dm-nm-mismatch > "$SP/R/mut/dm-nm-mismatch.out" 2>&1
"$SP/R/harness.sh" harness-4.log
cd $REPO
tools/run-tests.sh core > "$SP/R/core-2.log" 2>&1; echo "core EXIT=$?" >> "$SP/R/core-2.log"
tools/run-tests.sh inventory > "$SP/R/inventory-2.log" 2>&1; echo "inventory EXIT=$?" >> "$SP/R/inventory-2.log"
git status --short > "$SP/R/git-status-final.txt"
echo "FINISH DONE $(date)" >> "$SP/R/finish.log"
