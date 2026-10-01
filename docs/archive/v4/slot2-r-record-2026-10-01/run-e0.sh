#!/bin/zsh
# E0 (2026-10-01): py4DSTEM 'same' GD/DM and the app engine (dump tool) on the three s1 fixtures -> run-e0-1.log, out/
# Needs: fixtures from `python synth.py make --seed 1 --defocus D --out fx/dfD-s1.json` (D = 200 400 600) and ./dump/dump (build-dump.sh).
PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}; mkdir -p out
for D in 200 400 600; do F=fx/df$D-s1.json
  for M in gd dm; do $PY synth.py py $F --variant same --method $M --out out/py-same-$M-df$D.json; done
  for M in gd dm; do for C in 1 0; do ./dump/dump $F out/app-$M-c$C-df$D.json --method $M --clamp $C; done; done
  ./dump/dump $F out/app-gd-c1-appprobe-df$D.json --method gd --clamp 1 --probe app
  ./dump/dump $F out/app-dm-c1-appprobe-df$D.json --method dm --clamp 1 --probe app
  ./dump/dump $F out/app-gd-c1-neg-df$D.json --method gd --clamp 1 --probe app-neg
  ./dump/dump $F out/app-dm-c1-neg-df$D.json --method dm --clamp 1 --probe app-neg
done
