#!/bin/zsh
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
for m in defocus-sign dm-projection-a clamp-off neg-control-off scorer-mean; do "$SP/R/mutate.sh" $m; done > "$SP/R/mut/all.log" 2>&1
echo "ALL DONE $(date)" >> "$SP/R/mut/all.log"
