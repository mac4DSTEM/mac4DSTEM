import re, itertools, sys, math
root = sys.argv[1]
src = open(root + '/mac4DSTEM/Core/Spectroscopy/XRayLineData.swift').read()
rows = re.findall(r'^(\d+) (\w+) (\w+) ([\d.]+) ([\d.]+)$', src, re.M)
LINES = [dict(z=int(z), el=el, name=name, e=float(e), w=float(w), id=f"{el}_{name}") for z, el, name, e, w in rows]
byid = {l['id']: l for l in LINES}
MN = 5.8987
REFUSED = {"H", "He", "Li", "Be"}
EXCL = {"Tc", "Pm", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Pa", "Np", "Pu", "Am", "Ne", "Kr", "Xe"}
POOL = {l['el'] for l in LINES} - REFUSED - EXCL
LO, HI, BEAM = 0.0, 0.01 * 1499, 200.0
SIKA = byid['Si_Ka']['e']
def fwhm(res, e):
    v = 2.5 * (e - MN) * 1000.0 + res * res
    return math.sqrt(v) / 1000.0 if v >= 0 else None
def group(alpha_id, res):
    """Mirror EDSLineModel.build (escapePeaks on). Returns (lines, escapes) after fwhm drops, or None if alpha dropped."""
    a = byid[alpha_id]; letter = a['name'][0]
    if fwhm(res, a['e']) is None: return None
    lines = [(alpha_id, a['e'], 1.0)]
    for l in LINES:
        if l['el'] == a['el'] and l['name'][0] == letter and l['name'] != a['name'] and LO < l['e'] < min(HI, BEAM):
            if fwhm(res, l['e']) is not None: lines.append((l['id'], l['e'], l['w']))
    esc = []
    for i, e, w in lines:
        if e > 1.839 and fwhm(res, e - SIKA) is not None: esc.append((i + '_esc', e - SIKA, w))
    return lines, esc
alpha_ids = [l['id'] for l in LINES if l['name'] in ('Ka', 'La', 'Ma') and l['el'] in POOL and 0.45 <= l['e'] < HI]
# every valid parent pair sum (parents: pool elements with an alpha 0.45..HI) and every coinciding target
par = [(l['el'], l['id'], l['e']) for l in LINES if l['name'] in ('Ka', 'La', 'Ma') and l['el'] in POOL and 0.45 <= l['e'] < HI]
sums = []
for (e1, i1, x1), (e2, i2, x2) in itertools.combinations_with_replacement(par, 2):
    if e1 == e2 and i1 != i2: continue
    sums.append((round(x1 + x2, 4), (e1, i1, x1), (e2, i2, x2)))
print('valid pool alpha lines', len(par), 'valid parent pairs', len(sums))
targets = []
for i in alpha_ids:
    targets.append(('alpha', i, byid[i]['e']))
    if byid[i]['e'] > 1.839: targets.append(('esc', i, round(byid[i]['e'] - SIKA, 4)))
RES = 130.0
print('--- at 130 eV: valid-pair sums that coincide exactly with a pool column ---')
n = 0
for kind, i, te in targets:
    hits = []
    for s, p1, p2 in sums:
        if abs(s - te) < 1e-6 and p1[0] != byid[i]['el'] and p2[0] != byid[i]['el']:
            hits.append(f"{p1[1]}+{p2[1]}")
    if not hits: continue
    g = group(i, RES)
    lines, esc = g
    if kind == 'alpha':
        ncomp = len(lines)
    else:
        ncomp = len(esc)
    n += 1
    print(f"{kind} {i} E={te:.4f} | pairs {hits[:3]}{'...' if len(hits)>3 else ''} | group lines={len(lines)} escapes={len(esc)} | single-component={ncomp==1}")
print('targets with valid pairs:', n)
print('--- resolution scan 100..160 eV: targets whose column becomes a single Gaussian (identical to a sum column) ---')
for r in range(50, 251):
    res = float(r)
    for kind, i, te in targets:
        if not any(abs(s - te) < 1e-6 and p1[0] != byid[i]['el'] and p2[0] != byid[i]['el'] for s, p1, p2 in sums): continue
        g = group(i, res)
        if g is None: continue
        lines, esc = g
        if kind == 'alpha' and len(lines) == 1: print('res', r, 'alpha single-line', i, round(te, 4))
        if kind == 'esc' and len(esc) == 1 and esc[0][2] == 1.0: print('res', r, 'escape single-component', i, round(te, 4))
print('scan done')
