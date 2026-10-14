import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
from collections import defaultdict
s=sys.argv[1]
V={v:parse(f'{SPD}/{s}_{v}.log') for v in ['none','a','c','b2','s','cbs']}
def acc(r): return r.get('status') in ('profile','conic')
def cls(r):
    if not acc(r): return 'T'
    x=abs(r['dR']); return 'R' if x<=.001 else 'M' if x<=.01 else 'W'
G=defaultdict(list)
for n in V['none']:
    p=n.split('-'); G[(p[1],p[2],p[4])].append(n)   # R, sigma, tail
print('R sigma tail  n | seed|dR| median | class counts (R/M/W/T) head a c b2 s cbs')
for k in sorted(G):
    ns=G[k]
    sd=[abs(V['none'][n]['seed_dR']) for n in ns if V['none'][n].get('seed')=='ok']
    row=[]
    for v in ['none','a','c','b2','s','cbs']:
        c=defaultdict(int)
        for n in ns: c[cls(V[v][n])]+=1
        row.append(f"{c['R']}/{c['M']}/{c['W']}/{c['T']}")
    print(k,len(ns),'seed|dR| med %.3f'%(q(sd,.5) if sd else float('nan')),'|',' '.join(row))
