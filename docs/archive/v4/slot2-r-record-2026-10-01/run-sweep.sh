#!/bin/zsh
# DM over normalization_min on both sides, three s1 fixtures, scored against truth -> sweep-1.log, sweep/ (after run-e0.sh)
PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}; mkdir -p sweep
for D in 200 400 600; do F=fx/df$D-s1.json
  for NM in 0.5 0.2 0.1 0.05 0.02; do
    $PY synth.py py $F --variant same --method dm --norm-min $NM --out sweep/py-dm-nm$NM-df$D.json | grep -v "^  errors\|checks"
    ./dump/dump $F sweep/app-dm-nm$NM-df$D.json --method dm --clamp 1 --norm-min $NM > /dev/null
    $PY synth.py score $F sweep/app-dm-nm$NM-df$D.json --py sweep/py-dm-nm$NM-df$D.json | grep "it 32\|it  8\|vs py\|final" | sed "s/^/   app nm$NM df$D: /"
  done
  $PY synth.py py $F --variant same --method gd --norm-min 0.1 --out sweep/py-gd-nm0.1-df$D.json | grep -v "^  errors\|checks"
done
