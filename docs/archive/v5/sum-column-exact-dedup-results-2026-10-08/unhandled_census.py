import re, itertools, sys, collections
src = open(sys.argv[1] + '/mac4DSTEM/Core/Spectroscopy/XRayLineData.swift').read()
rows = re.findall(r'^(\d+) (\w+) (\w+) ([\d.]+) ([\d.]+)$', src, re.M)
alpha = {}; allline = []
for z, el, name, e, w in rows:
    e = float(e); allline.append((e, el, name))
    if name in ('Ka', 'La', 'Ma'): alpha.setdefault(el, {})[name] = (e, int(z))
par = [(el, fam, e) for el, d in alpha.items() for fam, (e, z) in d.items() if 0.1 < e < 20]
si_ka = [e for e, el, n in allline if el == 'Si' and n == 'Ka'][0]
print('rows', len(rows), 'alpha elements', len(alpha), 'Si Ka', si_ka)
sums = []
for (e1, f1, x1), (e2, f2, x2) in itertools.combinations_with_replacement(par, 2):
    if f1 == e1 and False: pass
    s = round(x1 + x2, 4)
    if s < 20 and not (e1 == e2 and f1 != f2): sums.append((s, e1, f1, e2, f2))
# (a) sum equal (to 1e-6) to an alpha line of an element not in the pair
lines_alpha = [(e, el, fam) for el, d in alpha.items() for fam, (e, z) in d.items()]
hitsA = set(); hitsE = set()
esc = [(round(e - si_ka, 4), el, fam) for e, el, fam in lines_alpha if e > 1.84]
for s, e1, f1, e2, f2 in sums:
    for e, el, fam in lines_alpha:
        if el not in (e1, e2) and abs(e - s) < 1e-6: hitsA.add((s, el, fam))
    for e, el, fam in esc:
        if abs(e - s) < 1e-6 and el not in (e1, e2): hitsE.add((s, el, fam))
print('sum pairs (alpha parents) <20 keV', len(sums))
print('exact sum == alpha line of another element:', len(hitsA), sorted(hitsA)[:6])
print('exact sum == Si-escape of an alpha line (not in the pair):', len(hitsE), sorted(hitsE)[:6])
