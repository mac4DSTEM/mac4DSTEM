import sys,re; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter, defaultdict
D=load()
def cls(r):
    if not accepted(r): return 'THREW'
    x=abs(r['dR'])
    return 'R' if x<=0.001 else ('M' if x<=0.01 else 'W')
def seedtxt(r):
    t=r.get('fallback') or r.get('err') or ''
    m=re.search(r'ringLeftSeed\(([0-9.e-]+)\)',t)
    if m: return float(m.group(1))
    m=re.search(r'moved the ring ([0-9.]+) %',t)
    if m: return float(m.group(1))/100
    return None
def what(r):
    t=r.get('fallback') or r.get('err') or ''
    if 'moved the ring' in t or 'ringLeftSeed' in t: return 'seed'
    if 'lost the ring' in t or 'ringWidthAtFloor' in t: return 'floor'
    return None
# s vs head, per set: of plants where s refused for the seed (s row has seed text) -> transition table head class -> s class
for v in ['s','cs','cbs','cb','b2']:
    print('==',v,': refusals by head-class -> variant-class (reason seed/floor); right-fit refusals listed')
    for s in SETS:
        T=Counter(); right_refused=[]
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            w=what(r)
            if w and h['status']=='profile':
                T[(w,cls(h),cls(r))]+=1
                if cls(h)=='R' and w=='seed' : right_refused.append((n,seedtxt(r),r['dR'],r['dba']))
        if T: print(s, dict(sorted(T.items())))
        for x in right_refused[:30]: print('    RIGHT REFUSED(seed)',x)
