import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
from collections import defaultdict
N=parse(f'{SPD}/T_none.log'); A=parse(f'{SPD}/T_a.log')
G=defaultdict(list)
for n,r in N.items():
    p=n.split('-')
    if p[1]=='slope': G[p[2]].append(n)
for k in sorted(G):
    ns=G[k]
    sd=[abs(N[n]['seed_dR']) for n in ns if N[n].get('seed')=='ok']
    dep=[abs(N[n]['depart']) for n in ns if N[n].get('status')=='profile' and abs(N[n]['dR'])<=0.001]
    depa=[abs(A[n]['depart']) for n in ns if A[n].get('status')=='profile' and abs(A[n]['dR'])<=0.001]
    print(k,len(ns),'seed|dR| max %.4f | head right departs: n=%d max %.4f | a: n=%d max %.4f'%(max(sd),len(dep),max(dep) if dep else float('nan'),len(depa),max(depa) if depa else float('nan')))
