#!/bin/zsh
# Break the new harness checks: apply ONE mutation, run the harness (lock), record the exit, restore byte-for-byte (cmp).
# usage: mutate.sh <name>   name in: defocus-sign | dm-projection-a | clamp-off | scorer-mean | neg-control-off
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
CORE=$REPO/mac4DSTEM/Core/Analysis
HARN=$REPO/tools/singleslice-ptychography-test/main.swift
name=$1
mkdir -p $SP/R/mut
case $name in
  defocus-sign)  F=$CORE/PtychographyPreparation.swift; FROM='            -defocusAngstrom'; TO='            +defocusAngstrom' ;;
  dm-projection-a) F=$CORE/SingleslicePtychography.swift; FROM='                    let projectionA = -alpha'; TO='                    let projectionA = alpha' ;;
  clamp-off) F=$HARN; FROM='                    options.constrainObjectAmplitude = clamp'; TO='                    options.constrainObjectAmplitude = false' ;;
  scorer-mean) F=$HARN; FROM='        let a = phasesObject[index] - meanA, b = phasesTruth[index] - meanB'; TO='        let a = phasesObject[index], b = phasesTruth[index]' ;;
  neg-control-off) F=$HARN; FROM='                let minus = try appProbe(sign: -1)'; TO='                let minus = try appProbe(sign: 1)' ;;
  *) echo "unknown mutation"; exit 64 ;;
esac
cp "$F" $SP/R/mut/$name.orig
python3 - "$F" "$FROM" "$TO" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, ("mutation anchor count", s.count(sys.argv[2]))
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
until mkdir "$SP/heavy.lock" 2>/dev/null; do sleep 15; done
cd $REPO
tools/singleslice-ptychography-test/run.sh > $SP/R/mut/$name.log 2>&1
echo "MUTATION $name EXIT=$?" | tee -a $SP/R/mut/$name.log
rmdir "$SP/heavy.lock"
cp $SP/R/mut/$name.orig "$F"
cmp "$F" $SP/R/mut/$name.orig && echo "restored $F byte-identical"
grep -m1 "Fatal error\|Error raised" $SP/R/mut/$name.log | cut -c1-400
