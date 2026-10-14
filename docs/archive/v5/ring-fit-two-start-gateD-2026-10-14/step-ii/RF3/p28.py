import sys,io,contextlib; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
from collections import Counter, defaultdict
D=load()
names=Counter(n for s in SETS for n in D[s]['head'])
dups=[n for n,c in names.items() if c>1]
print('unique names',len(names),'of',sum(names.values()),'; names occurring in >1 set:',len(dups),'; copies distribution',Counter(names[n] for n in dups))
# are the duplicates identical across sets (pixels likely same)? compare head rows between sets
ident=0; diff=0
for n in dups:
    rows=[D[s]['head'][n] for s in SETS if n in D[s]['head']]
    if all(abs(r['dR']-rows[0]['dR'])<1e-12 and r['status']==rows[0]['status'] for r in rows): ident+=1
    else: diff+=1
print('duplicate names with identical head result across sets:',ident,'differing:',diff)
# unique-plant tallies (take first occurrence)
seen=set(); tot=Counter()
for s in SETS:
    for n in D[s]['head']:
        if n in seen: continue
        seen.add(n)
        for v in ['head','a','c','b2','s','cbs']:
            r=D[s][v][n]
            tot[v,'W']+=wrong(r)
            tot[v,'ba']+=accepted(r) and abs(r['dba'])>0.01
        tot['n']+=1
print('unique plants',tot['n'],{v:(tot[v,'W'],tot[v,'ba']) for v in ['head','a','c','b2','s','cbs']},'(wrong, |dba|>0.01)')
# which names are duplicated by tier prefix
print(Counter(n.split('-')[0] for n in dups))
