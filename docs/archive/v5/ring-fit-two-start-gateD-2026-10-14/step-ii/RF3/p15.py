import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
from collections import defaultdict
s=sys.argv[1]
V={v:parse(f'{SPD}/{s}_{v}.log') for v in ['none','a','c']}
print('set',s,{v:len(r) for v,r in V.items()})
# group by subtype (name's 2nd token for T, tier for others) and background
def grp(n,r):
    p=n.split('-')
    return p[1] if s in('T','S3') else r['tier']
G=defaultdict(list)
for n,r in V['none'].items(): G[grp(n,r)].append(n)
print(f"{'group':14} n  seed|dR| p50/p90/max   seed|dba| max | head right-fit depart max (n) | a right-fit depart max | head wrong depart (>.08 / .05-.08)")
for k in sorted(G):
    ns=G[k]
    sd=[abs(V['none'][n]['seed_dR']) for n in ns if V['none'][n].get('seed')=='ok']
    sdb=[abs(V['none'][n]['seed_dba']) for n in ns if V['none'][n].get('seed')=='ok']
    out=[]
    for v in ['none','a']:
        rr=[V[v][n] for n in ns if n in V[v]]
        rt=[abs(r['depart']) for r in rr if r.get('status')=='profile' and abs(r['dR'])<=0.001]
        out.append(f"{max(rt) if rt else float('nan'):.4f} ({len(rt)})")
    rw=[abs(r['depart']) for r in (V['none'][n] for n in ns) if r.get('status')=='profile' and abs(r['dR'])>0.01]
    print(f"{k:14} {len(ns):3} {q(sd,.5):.4f}/{q(sd,.9):.4f}/{max(sd) if sd else float('nan'):.4f}   {max(sdb) if sdb else float('nan'):.4f}   | {out[0]} | {out[1]} | {sum(x>.08 for x in rw)}/{sum(.05<x<=.08 for x in rw)} of {len(rw)}")
