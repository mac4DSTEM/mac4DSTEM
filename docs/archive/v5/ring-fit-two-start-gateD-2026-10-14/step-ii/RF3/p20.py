import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
print('accepted fits "right in R" (|dR|<=1%) but with |d(b/a)| > 0.01, and ">50 % of the true ellipticity":')
print('var   set: R-ok&ba>.01 | R-ok&ellipticity-error>50% | R-wrong')
for v in ['head','a','c','b2','s','cbs']:
    tot=Counter()
    for s in SETS:
        for n,r in D[s][v].items():
            if not accepted(r): continue
            eps=1-r['ba_true']
            ok = abs(r['dR'])<=0.01
            if ok and abs(r['dba'])>0.01: tot['ba']+=1
            if ok and eps>0 and abs(r['dba'])>0.5*eps: tot['ell50']+=1
            if not ok: tot['W']+=1
    print(v,dict(tot))
print()
print('per set, c and cbs: R-ok but |dba|>0.01')
for s in SETS:
    row=[]
    for v in ['head','c','cbs']:
        k=sum(1 for r in D[s][v].values() if accepted(r) and abs(r['dR'])<=0.01 and abs(r['dba'])>0.01)
        row.append(f'{v} {k}')
    print(s,row)
# which tiers carry them under cbs
cnt=Counter()
for s in SETS:
    for n,r in D[s]['cbs'].items():
        if accepted(r) and abs(r['dR'])<=0.01 and abs(r['dba'])>0.01: cnt[(s,n.split('-')[0], n.split('-')[1] if s in('T',) else '')]+=1
print(dict(cnt))
