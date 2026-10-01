#!/bin/zsh
# Graphene: app arms (graphene.sh -> gr/) vs py4DSTEM (gr/py-dm-m600-nm*, R1's py-df-600-auto = reference_ptycho.py --defocus -600 --method gd) -> gr-compare.log
REPO=${REPO:-/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM}; PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}
R1=${R1:-$PWD/gr/py-df-600-auto}   # the py4DSTEM GD -600 run (error_history.json, object_phase.npy)
$PY - <<PYEOF
import json
def rel(a, p): return ["%.1e" % (abs(x - y) / y) for x, y in zip(a, p)]
app = json.load(open("gr/app-gd-c1/app_ptycho_gd.json"))["errorHistory"]; py = json.load(open("$R1/error_history.json"))
print("GD clamp ON app vs py -600:", rel(app, py), "max %.3f" % max(abs(x - y) / y for x, y in zip(app, py)))
for arm, pyd in (("app-dm-nm1-c1", "py-dm-m600-nm1"), ("app-dm-nm1-c0", "py-dm-m600-nm1"), ("app-dm-nm0.05-c1", "py-dm-m600-nm0.05")):
    a = json.load(open(f"gr/{arm}/app_ptycho_dmap.json"))["errorHistory"]; p = json.load(open(f"gr/{pyd}/error_history.json"))
    print(arm, "vs", pyd, rel(a, p))
PYEOF
$PY $REPO/tools/parallax-ptycho-real-probe/compare_ptycho.py --app gr/app-gd-c1 --py $R1 --method gd --name "GD clamp on -600 vs py -600" --json gr/cmp-gd-c1.json
$PY $REPO/tools/parallax-ptycho-real-probe/compare_ptycho.py --app gr/app-dm-nm0.05-c1 --py gr/py-dm-m600-nm0.05 --method dmap --name "DM nm0.05 app vs py" --json gr/cmp-dm-nm0.05.json | grep -v errors
