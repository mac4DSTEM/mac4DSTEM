import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from swlib import parse,fl,acc,ba,rad,RUN,VARS
import math, statistics as st
from collections import defaultdict, Counter
FAM={'au':[('A1','W1'),('A2','W2'),('A3','W3'),('A4','W4')],
     's3':[('s3-R1','s3-R1w'),('s3-R2','s3-R2w'),('s3-R3','s3-R3w')],
     's4':[('s4-R1','s4-R1w'),('s4-R2','s4-R2w'),('s4-R3','s4-R3w'),('s4-R4','s4-R4w'),('s4-R5','s4-R5w')],
     's5':[('S5-R3','S5-R3w')]}
def base(t): return t.split(':')[0].split('~')[0] if t[0] in 'AW' else t.split('~')[0]
def seedrad(r): return (fl(r,'seed_a')+fl(r,'seed_b'))/2
print('Truth-free consistency sweep. A fit is "healthy" if it is a head profile fit whose radius is within 4 % and whose b/a within 0.02 of the median of ALL head profile fits of that ring family (two annulus widths x 25 shifts).')
print('family       nHead(profile) med rad  med b/a | healthy | s refuses | b2 refuses | cbs: profile kept / conic / THREW | c moves b/a>0.005')
agg=Counter()
for src,fams in FAM.items():
    V={v:parse(f'{RUN}/sweep-{src}-{v}.log') for v in VARS}
    for fam in fams:
        ts=[t for t in V['head'] if base(t) in fam]
        prof=[t for t in ts if V['head'][t].get('status')=='profile']
        if len(prof)<5: print(fam[0],'too few profile fits',len(prof)); continue
        mr=st.median(rad(V['head'][t]) for t in prof); mb=st.median(ba(V['head'][t]) for t in prof)
        healthy=[t for t in prof if abs(rad(V['head'][t])/mr-1)<=0.04 and abs(ba(V['head'][t])-mb)<=0.02]
        def cnt(v): 
            c=Counter()
            for t in healthy:
                r=V[v][t]; c[r.get('status')]+=1
            return c
        sc=cnt('s'); bc=cnt('b2'); cc=cnt('cbs'); c2=cnt('c')
        cm=sum(1 for t in prof if acc(V['c'][t]) and abs(ba(V['c'][t])-ba(V['head'][t]))>0.005)
        print(f"{fam[0]:8}/{fam[1]:6} {len(prof):4d} {mr:8.3f} {mb:7.4f} | {len(healthy):4d} | {len(healthy)-sc['profile']:3d} ({sc['conic']} conic, {sc['THREW']} threw) | {len(healthy)-bc['profile']:3d} | {cc['profile']:3d} / {cc['conic']:3d} / {cc['THREW']:3d} | {cm}")
        agg['healthy']+=len(healthy); agg['s']+=len(healthy)-sc['profile']; agg['b2']+=len(healthy)-bc['profile']; agg['cbsprof']+=cc['profile']; agg['cbsconic']+=cc['conic']; agg['cbsthrew']+=cc['THREW']
        for t in healthy:
            r=V['s'][t]
            if r.get('status')!='profile':
                h=V['head'][t]; agg['s_seed_depart_%s'%src]+=0
print(dict(agg))
