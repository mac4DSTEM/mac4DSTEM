import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import defaultdict
D=load()
def summ(set_, names, vs=('head','a','c','b2','s','cbs')):
    out=[]
    for v in vs:
        rr=[D[set_][v][n] for n in names]
        acc=[r for r in rr if accepted(r)]
        ba=sorted(abs(r['dba']) for r in acc)
        q=lambda p: ba[min(len(ba)-1,int(p*len(ba)))] if ba else math.nan
        out.append(f"{v}: W{sum(wrong(r) for r in rr):3d} T{sum(not accepted(r) for r in rr)} ba>.01:{sum(abs(r['dba'])>0.01 for r in acc):3d} ba>.1:{sum(abs(r['dba'])>0.1 for r in acc):3d} med{q(.5):.4f} p90{q(.9):.4f} max{ba[-1] if ba else math.nan:.3f}")
    return out
print('--- P by gap x background (n=48 each) ---')
G=defaultdict(list)
for n in D['P']['head']:
    p=n.split('-'); g=[x for x in p if x.startswith('g')][0]; bgk=p[5][:3]
    G[(g,bgk)].append(n)
for k in sorted(G):
    if k[0]!='g60': continue
    print(k,len(G[k])); [print('   ',x) for x in summ('P',G[k])]
print('--- P g60 r28 by amplitude ---')
for amp in ['a10','a20','a50','a200']:
    names=[n for n in G[('g60','r28')] if n.split('-')[1]==amp]
    print(amp,len(names)); [print('   ',x) for x in summ('P',names,('head','a','c','cbs'))]
print('--- T by subtype ---')
T=defaultdict(list)
for n in D['T']['head']:
    p=n.split('-'); T[p[1]].append(n)
for k in sorted(T):
    print(k,len(T[k])); [print('   ',x) for x in summ('T',T[k])]
print('--- S3 by name prefix ---')
S=defaultdict(list)
for n in D['S3']['head']:
    p=n.split('-'); S[p[1] if len(p)>1 else p[0]].append(n)
print(list(D['S3']['head'])[:3])
for k in sorted(S):
    print(k,len(S[k])); [print('   ',x) for x in summ('S3',S[k])]
print('--- S3 plants wrong under c / cbs ---')
for n,r in D['S3']['c'].items():
    if wrong(r) or wrong(D['S3']['cbs'][n]):
        print(n,{v:(f"{D['S3'][v][n]['status'][:4]} dR={D['S3'][v][n]['dR']:+.3f} dba={D['S3'][v][n]['dba']:+.3f}" if accepted(D['S3'][v][n]) else 'THREW') for v in ('head','a','c','s','cbs')})
