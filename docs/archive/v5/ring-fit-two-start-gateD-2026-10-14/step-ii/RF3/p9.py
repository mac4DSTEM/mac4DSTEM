import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
def cls(r):
    if not accepted(r): return 'T'
    x=abs(r['dR']); return 'R' if x<=0.001 else ('M' if x<=0.01 else 'W')
print('cbs-wrong plants: class string over (head a c b2 s cb cs cbs); marks those where some variant is not W')
C=Counter(); L=[]
for s in SETS:
    for n,r in D[s]['cbs'].items():
        if not wrong(r): continue
        cl=''.join(cls(D[s][v][n]) for v in ['head','a','c','b2','s','cb','cs','cbs'])
        C[cl]+=1
        L.append((s,n,cl,r))
for k,v in sorted(C.items(),key=lambda kv:-kv[1]): print(k,v)
print()
print('cbs wrong while c, b2 or s alone is not wrong (R/M/T):')
for s,n,cl,r in L:
    c,b2,ss=cl[2],cl[3],cl[4]
    if c!='W' or b2!='W' or ss!='W':
        print(s,n[:55],cl,f"cbs dR={r['dR']:+.3f} dba={r['dba']:+.3f}")
print()
print('wrong under cbs by set and by tier:')
print(Counter((s,n.split('-')[0]) for s,n,cl,r in L))
print('size of cbs-wrong: |dR| quantiles, |dba| quantiles')
import statistics
xs=sorted(abs(r['dR']) for s,n,cl,r in L); ys=sorted(abs(r['dba']) for s,n,cl,r in L)
q=lambda a,p:a[min(len(a)-1,int(p*len(a)))]
print('dR',[round(q(xs,p),3) for p in (0,.25,.5,.75,.9,1)],'dba',[round(q(ys,p),3) for p in (0,.25,.5,.75,.9,1)])
