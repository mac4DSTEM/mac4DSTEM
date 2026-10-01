#!/bin/zsh
# Self-sensitivity (1e-6 amplitude perturbation) and py4DSTEM's own pipeline ('own') vs forced-same inputs, df400 s1 -> sens-1.log, sens/
PY=${PYTHON:-$HOME/miniconda3/envs/py4dstem/bin/python}; mkdir -p sens; F=fx/df400-s1.json
$PY synth.py py $F --variant same --method gd --perturb 1e-6 --out sens/py-gd-pert.json | grep -v checks
$PY synth.py py $F --variant same --method dm --perturb 1e-6 --out sens/py-dm-pert.json | grep -v checks
$PY synth.py py $F --variant same --method dm --norm-min 0.1 --perturb 1e-6 --out sens/py-dm-nm0.1-pert.json | grep -v checks
$PY synth.py py $F --variant own --method gd --out sens/py-own-gd.json | grep -v "^  errors"
$PY synth.py py $F --variant own --method dm --out sens/py-own-dm.json | grep -v "^  errors"
$PY synth.py py $F --variant own --method dm --norm-min 0.1 --out sens/py-own-dm-nm0.1.json | grep -v "^  errors"
# the table in the report: relative error-history differences per pair (out2/py-same-*.json come from `synth.py py --variant same`)
$PY - <<'PYEOF'
import json
def e(p): return json.loads(open(p).read())["errors"]
pairs = [("GD nm1 py vs py+1e-6", "out2/py-same-gd-df400.json", "sens/py-gd-pert.json"), ("DM nm1 py vs py+1e-6", "out2/py-same-dm-df400.json", "sens/py-dm-pert.json"),
         ("DM nm0.1 py vs py+1e-6", "sweep/py-dm-nm0.1-df400.json", "sens/py-dm-nm0.1-pert.json"), ("GD nm1 own vs same", "out2/py-same-gd-df400.json", "sens/py-own-gd.json"),
         ("DM nm1 own vs same", "out2/py-same-dm-df400.json", "sens/py-own-dm.json"), ("DM nm0.1 own vs same", "sweep/py-dm-nm0.1-df400.json", "sens/py-own-dm-nm0.1.json")]
for name, a, b in pairs:
    ea, eb = e(a), e(b); rel = [abs(x - y) / y for x, y in zip(ea, eb)]
    print("%-26s rel diff: it1 %.1e it2 %.1e it4 %.1e it8 %.1e it16 %.1e it32 %.1e max %.1e" % (name, rel[0], rel[1], rel[3], rel[7], rel[15], rel[31], max(rel)))
PYEOF
