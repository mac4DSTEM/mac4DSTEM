# Sum-peak (pile-up) energy coincidences in the app's line table: python3 sum_collisions.py <repo root>  (2026-10-08)
# Parents are each element's Ka/La/Ma line (an approximation: the proposer uses each proposed element's strongest line).
import re, itertools, collections, sys
src=open((sys.argv[1] if len(sys.argv)>1 else '.')+'/mac4DSTEM/Core/Spectroscopy/XRayLineData.swift').read()
lines=re.findall(r'^(\d+) (\w+) (\w+) ([\d.]+) ([\d.]+)$', src, re.M)
alpha={}
for z,el,name,e,w in lines:
    if name in ('Ka','La','Ma'): alpha.setdefault(el,{})[name]=(float(e),int(z))
parents=[(el,fam,e) for el,d in alpha.items() for fam,(e,z) in d.items() if 0.1<e<20]
print('elements with alpha lines', len(alpha), 'parent energies', len(parents))
sums=[]
for (a,(e1,f1,x1)),(b,(e2,f2,x2)) in itertools.combinations_with_replacement(list(enumerate([(p[0],p[1],p[2]) for p in parents])),2):
    if e1==e2 and f1!=f2: continue                       # one group per element in a pass
    s=x1+x2
    if s<20: sums.append((round(s,6),frozenset([e1,e2]) if e1!=e2 else frozenset([e1]),f"{e1}{f1}+{e2}{f2}"))
by=collections.defaultdict(list)
for s,els,lab in sums: by[s].append((els,lab))
exact=[(s,v) for s,v in by.items() if len({x[0] for x in v})>1]
print('pair sums < 20 keV', len(sums), 'exact coincidences between different element pairs', len(exact))
for s,v in sorted(exact)[:40]: print(f'  {s:.4f} keV: '+' | '.join(sorted({x[1] for x in v})))
ss=sorted(sums)
near=0; nearAlMgSi=[]
focus={'Al','Mg','Si','Cu','O','C','Fe','Mn','Zn','Ti','Cr','Ga','Pt','Ar'}
for i in range(len(ss)):
    for j in range(i+1,len(ss)):
        if ss[j][0]-ss[i][0]>0.06: break
        if ss[i][1]!=ss[j][1]:
            near+=1
            if (ss[i][1]|ss[j][1])<=focus: nearAlMgSi.append((ss[i][0],ss[i][2],ss[j][0],ss[j][2]))
print('near coincidences (<= 0.06 keV) between different element pairs', near)
print('near ones among common Al-alloy/TEM elements', len(nearAlMgSi))
for x in nearAlMgSi[:25]: print('  %.4f %s ~ %.4f %s'%x)
