#!/bin/zsh
# Fixed-probe DM (py4DSTEM fix_probe=True) on the s1 fixtures and seeds 2/3 at df400 on both sides -> seeds-fixp-1.log, fixp/, seeds/
# Needs ./dump/dump built with --fix-probe (build-dump.sh writes dump/dump2; the session used dump/dump for the seeds).
PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}; mkdir -p fixp seeds
for S in 2 3; do $PY synth.py make --seed $S --defocus 400 --out fx/df400-s$S.json | tail -1; done
for D in 200 400 600; do for NM in 0.1 1; do $PY synth.py py fx/df$D-s1.json --variant same --method dm --norm-min $NM --fix-probe 1 --out fixp/py-dm-nm$NM-fixp-df$D.json | grep "it  8\|it 32" | sed "s/^/py fixp nm$NM df$D/"; done; done
for S in 2 3; do
  $PY synth.py py fx/df400-s$S.json --variant same --method gd --out seeds/py-gd-s$S.json | grep "it 32" | sed "s/^/py gd s$S/"
  $PY synth.py py fx/df400-s$S.json --variant same --method dm --norm-min 0.02 --out seeds/py-dm-nm0.02-s$S.json | grep "it  8\|it 32" | sed "s/^/py dm nm0.02 s$S/"
  ./dump/dump fx/df400-s$S.json seeds/app-gd-s$S.json --method gd --clamp 1 >/dev/null
  ./dump/dump fx/df400-s$S.json seeds/app-gd-neg-s$S.json --method gd --clamp 1 --probe app-neg >/dev/null
  ./dump/dump fx/df400-s$S.json seeds/app-dm-nm0.02-s$S.json --method dm --clamp 1 --norm-min 0.02 >/dev/null
  $PY synth.py score fx/df400-s$S.json seeds/app-gd-s$S.json --py seeds/py-gd-s$S.json | grep "it 32\|vs py\|final" | cut -c1-120 | sed "s/^/app gd s$S/"
  $PY synth.py score fx/df400-s$S.json seeds/app-gd-neg-s$S.json | grep "it 32" | sed "s/^/app gd NEG s$S/"
  $PY synth.py score fx/df400-s$S.json seeds/app-dm-nm0.02-s$S.json --py seeds/py-dm-nm0.02-s$S.json | grep "it  8\|it 32\|vs py" | cut -c1-160 | sed "s/^/app dm nm0.02 s$S/"
done
