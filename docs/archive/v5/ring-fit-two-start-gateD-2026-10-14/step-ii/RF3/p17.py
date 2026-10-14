import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
from collections import Counter
N=parse(f'{SPD}/Z_none.log')
c=Counter()
for n,r in N.items():
    p=n.split('-')
    key=(p[1],p[4],p[6]) # R, tail, ann
    c[(key, r.get('status'), (r.get('err') or r.get('seed') or '')[:34])]+=1
t=Counter()
for n,r in N.items():
    p=n.split('-'); t[(p[1],p[6],p[4], 'seed:'+r.get('seed','')[:28] if r.get('seed')!='ok' else 'ok')]+=1
for k in sorted(t): print(k,t[k])
print()
for n,r in N.items():
    if r.get('status')=='profile' and abs(r['dR'])>0.01:
        S=parse(f'{SPD}/Z_s.log')[n]; C=parse(f'{SPD}/Z_cbs.log')[n]
        print(n[:44],f"head dR={r['dR']:+.3f} dba={r['dba']:+.3f} depart={r['depart']:+.3f} seed_dR={r['seed_dR']:+.3f} | s:{S['status']} dR={S.get('dR',float('nan')):+.3f} | cbs:{C['status']} dR={C.get('dR',float('nan')):+.3f}")
