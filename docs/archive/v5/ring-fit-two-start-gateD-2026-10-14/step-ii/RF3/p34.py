import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from swlib import parse,fl,acc,ba,rad,RUN,VARS
import math, statistics as st
from collections import Counter
FAM={'au':[('A1','W1'),('A2','W2'),('A3','W3')],'s3':[('s3-R1','s3-R1w'),('s3-R2','s3-R2w'),('s3-R3','s3-R3w')],'s4':[('s4-R1','s4-R1w'),('s4-R2','s4-R2w'),('s4-R3','s4-R3w'),('s4-R4','s4-R4w'),('s4-R5','s4-R5w')],'s5':[('S5-R3','S5-R3w')]}
def base(t): return t.split('~')[0].split(':')[0] if t[0] in 'AW' else t.split('~')[0]
print('Truth-free outlier count per family: accepted fits (any model) whose radius is >4 % or b/a >0.02 from the family median of the UNION of variants\' consensus (median over all accepted head/cbs fits)')
for src,fams in FAM.items():
    V={v:parse(f'{RUN}/sweep-{src}-{v}.log') for v in VARS}
    for fam in fams:
        ts=[t for t in V['head'] if base(t) in fam]
        # reference = median of conic-seed-free consensus: median over head profile fits that all of head,c,b2,cbs agree on
        ref=[t for t in ts if all(acc(V[v][t]) for v in ('head','c','cbs')) and abs(rad(V['head'][t])-rad(V['cbs'][t]))<0.05]
        if len(ref)<5: continue
        mr=st.median(rad(V['head'][t]) for t in ref); mb=st.median(ba(V['head'][t]) for t in ref)
        row=[]
        for v in ['head','c','b2','s','cbs']:
            acc_t=[t for t in ts if acc(V[v][t])]
            out=[t for t in acc_t if abs(rad(V[v][t])/mr-1)>0.04 or abs(ba(V[v][t])-mb)>0.02]
            thr=len(ts)-len(acc_t)
            row.append(f"{v}: acc {len(acc_t)} outl {len(out)}")
        print(f"{fam[0]:8} (median rad {mr:.2f} b/a {mb:.4f}, {len(ts)} annuli) "+' | '.join(row))
