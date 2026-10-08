import re, sys, math
root = sys.argv[1]
src = open(root + '/mac4DSTEM/Core/Spectroscopy/XRayLineData.swift').read()
rows = re.findall(r'^(\d+) (\w+) (\w+) ([\d.]+) ([\d.]+)$', src, re.M)
LINES = [dict(el=el, name=name, e=float(e), w=float(w), id=f"{el}_{name}") for z, el, name, e, w in rows]
byid = {l['id']: l for l in LINES}
SIKA = byid['Si_Ka']['e']
targets = {  # target id -> kind, sum energy (valid parent pair only)
    'Tb_La': ('alpha', 6.2728), 'Lu_La': ('esc', 5.9159), 'Au_La': ('esc', 7.9733),
    'Hg_Ma': ('alpha', 2.1964), 'Te_La': ('alpha', 3.7693), 'I_La': ('alpha', 3.9377), 'V_Ka': ('esc', 3.2125),
    'Ti_Ka': ('esc', 2.7712)}
def comp(t, lo, hi, beam=200.0, res=130.0):
    a = byid[t]; letter = a['name'][0]
    fam = [l for l in LINES if l['el'] == a['el'] and l['name'][0] == letter and l['name'] != a['name'] and lo < l['e'] < min(hi, beam)]
    if not (lo < a['e'] < min(hi, beam)): return None
    lines = [a] + fam
    esc = [l for l in lines if l['e'] > 1.839]
    return len(lines), len(esc), [l['id'] for l in lines]
single_alpha = []; single_esc = []
for t, (kind, s) in targets.items():
    for lo in [0.0, 0.1, 0.2, 0.3, 0.45, 0.5, 0.75, 1.0]:
        for hi10 in range(20, 2001, 5):
            hi = hi10 / 100.0
            c = comp(t, lo, hi)
            if c is None: continue
            n, ne, ids = c
            if kind == 'alpha' and n == 1: single_alpha.append((t, lo, hi))
            if kind == 'esc' and ne == 1 and comp(t, lo, hi)[1] == 1: single_esc.append((t, lo, hi, ids))
def summarize(lst, label):
    print(label, len(lst))
    seen = {}
    for x in lst:
        seen.setdefault(x[0], []).append(x[1:])
    for t, v in seen.items():
        print(' ', t, 'lo/hi examples', v[:3], '... count', len(v), 'hi range', min(a[1] for a in v), '-', max(a[1] for a in v))
summarize(single_alpha, 'alpha single-line (axis low, high) combos:')
summarize([(t, lo, hi) for t, lo, hi, ids in single_esc], 'escape single-component (axis low, high) combos:')
