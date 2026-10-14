import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
from collections import Counter
D=load()
c=Counter()
for s in SETS:
    for n,r in D[s]['s'].items():
        h=D[s]['head'][n]
        t=(r.get('fallback') or '')+(r.get('err') or '')
        if not (('moved the ring' in t) or ('ringLeftSeed' in t)): continue
        if h['status']!='profile': continue
        low = h['cres']<=0.2
        W = wrong(h)
        c[('cres<=0.2' if low else 'cres>0.2', 'head wrong' if W else 'head not wrong')]+=1
print('s refusals (seed) by conic residual of the seed and head status (ii plants):',dict(c))
# how many head-wrong fits would s still catch if it only acted when cres<=0.2 ?
tot=Counter()
for s in SETS:
    for n,h in D[s]['head'].items():
        if wrong(h) and h['status']=='profile':
            tot['wrong profile']+=1
            tot['cres<=0.2' if h['cres']<=0.2 else 'cres>0.2']+=1
print('head wrong profile fits by conic residual:',dict(tot))
