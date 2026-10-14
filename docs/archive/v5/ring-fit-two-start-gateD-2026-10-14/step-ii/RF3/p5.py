import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
D=load()
def f(r):
    if not accepted(r): return 'THREW '+r.get('err','')[:50]
    return f"{r['status'][:4]} dR={r['dR']:+.4f} dba={r['dba']:+.4f} cres={r['cres']:.3f}"
for v in ['s','cs','cbs']:
    print('== new throws under',v)
    for s in SETS:
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            if r['status']=='THREW' and h['status']!='THREW':
                print(f"{s:3} {n[:48]:48} head: {f(h):45} a: {f(D[s]['a'][n]):45} c: {f(D[s]['c'][n])} | {r.get('err','')[:70]}")
print()
print('== error text census of THREW rows (variant: counts)')
from collections import Counter
for v in VARS:
    c=Counter()
    for s in SETS:
        for n,r in D[s][v].items():
            if r['status']=='THREW': c[r.get('err','')[:60]]+=1
    print(v,dict(c))
