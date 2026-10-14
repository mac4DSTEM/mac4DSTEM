import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
# flags in accepted profile fits (what survives each variant): I1==0, sigma at ceiling (>= 0.99*max(2,2*outer)) -- outer unknown in rows: use sin/sout>=40 as proxy? use I1 only + sigma<=0.31 + sigma>=? 
for v in ['head','c','b2','s','cbs']:
    c=Counter(); w=Counter()
    for s in SETS:
        for n,r in D[s][v].items():
            if r['status']!='profile': continue
            tags=[]
            if r['I1']<=1e-9: tags.append('I1=0')
            m=min(r['sin'],r['sout'])
            if m<=0.30: tags.append('sig<=.30')
            elif m<=0.35: tags.append('sig(.30,.35]')
            if r['s0']<=0.2501: tags.append('s0floor')
            for t in tags:
                c[t]+=1
                if wrong(r): w[t]+=1
            c['n']+=1
    print(v,'profile fits',c['n'],{k:(c[k],'wrong',w[k]) for k in c if k!='n'})
print()
print('accepted profile fits with I1==0 (dead ring) surviving in cbs, by set / wrong:')
for s in SETS:
    k=[(n,r) for n,r in D[s]['cbs'].items() if r['status']=='profile' and r['I1']<=1e-9]
    print(s,len(k),'wrong',sum(wrong(r) for n,r in k), [ (n[:30],round(r['dR'],3),round(min(r['sin'],r['sout']),3)) for n,r in k[:4]])
# fits with a tiny but non-zero I1 relative to truth amplitude? list min I1 (non zero) among accepted cbs profile fits per set (clean sets amplitude 1)
print()
for s in ['A','C','T','N']:
    vals=sorted(r['I1'] for r in D[s]['cbs'].values() if r['status']=='profile')
    print(s,'cbs I1 quantiles', [f'{vals[int(p*(len(vals)-1))]:.3g}' for p in (0,.01,.05,.5,1)])
