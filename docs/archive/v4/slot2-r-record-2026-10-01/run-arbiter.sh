#!/bin/zsh
# The float64 arbiter on df400 s1 -> ref64-gd.log, ref64-dm.log, ref64-mask.log (after run-e0.sh; out2/ = py same runs with checkpoints)
PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}
$PY ref64.py fx/df400-s1.json --method gd --iterations 2 --app out/app-gd-c1-df400.json --py out2/py-same-gd-df400.json
$PY ref64.py fx/df400-s1.json --method gd --iterations 2 --dtype float32 --app out/app-gd-c1-df400.json --py out2/py-same-gd-df400.json
$PY ref64.py fx/df400-s1.json --method dm --iterations 2 --app out/app-dm-c1-df400.json --py out2/py-same-dm-df400.json
for E in 0 1e-6 1e-4; do for DT in float64 float32; do $PY ref64.py fx/df400-s1.json --method gd --iterations 1 --mask-eps $E --dtype $DT --save arb-$DT-$E.npy; done
  $PY -c "import numpy as np; a=np.load('arb-float64-$E.npy'); b=np.load('arb-float32-$E.npy'); print('eps $E: float64 vs float32 max |d| %.3e' % np.abs(a-b).max())"; done
