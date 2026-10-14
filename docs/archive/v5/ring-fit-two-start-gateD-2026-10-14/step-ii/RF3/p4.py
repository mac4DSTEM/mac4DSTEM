import sys,io,contextlib; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math, statistics as st
D=load()
def ba(r): return abs(r['dba']) if accepted(r) else math.nan
def dr(r): return abs(r['dR']) if accepted(r) else math.nan
# oracle best-of-two (head, a) by |dR| (accepted only)
def pct(x,p):
    x=sorted(v for v in x if not math.isnan(v)); 
    return x[min(len(x)-1,int(p*len(x)))] if x else math.nan
print('Oracle vs c on wrong counts, per set (wrong = |dR|>1%): head a c oracle(min(head,a)) ')
tw=dict(head=0,a=0,c=0,o=0)
for s in SETS:
    w=dict(head=0,a=0,c=0,o=0)
    for n in D[s]['head']:
        h,a,c=D[s]['head'][n],D[s]['a'][n],D[s]['c'][n]
        w['head']+=wrong(h); w['a']+=wrong(a); w['c']+=wrong(c); w['o']+=wrong(h) and wrong(a)
    print(s,w)
    for k in tw: tw[k]+=w[k]
print('ALL',tw)
print()
# P by gap, background: |dba| distribution head/a/c, and c-worse-than-head counts
def feat(n):
    parts=n.split('-')
    return parts
print('P set breakdown by background kind and gap: n, wrong(head,a,c), mean|dba| (accepted), p95|dba|, max|dba|  (head / a / c / cbs)')
from collections import defaultdict
G=defaultdict(list)
for n in D['P']['head']:
    p=n.split('-')
    g=[x for x in p if x.startswith('g')][0]
    bgk=p[5][:3] if len(p)>5 else '?'
    G[(g,bgk)].append(n)
for key in sorted(G):
    names=G[key]
    out=[]
    for v in ['head','a','c','cbs']:
        rr=[D['P'][v][n] for n in names]
        bas=[ba(r) for r in rr if accepted(r)]
        out.append(f"{v}: W{sum(wrong(r) for r in rr):3d} mean{st.mean(bas):.4f} p95{pct(bas,.95):.4f} max{max(bas):.3f}")
    print(key,len(names),' | '.join(out))
