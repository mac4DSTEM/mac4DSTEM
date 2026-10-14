import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
def desc(r):
    return f"{r['status'][:4]} dR={r['dR']:+.4f} dba={r['dba']:+.4f} dth={r['dth']:.3f}" if accepted(r) else 'THREW'
for v in ['c','cbs']:
    print('== right lost under',v)
    for s in SETS:
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            if right(h) and not right(r): print(s,n[:55],'| head',desc(h),'|',v,desc(r))
    print('== newly wrong under',v)
    for s in SETS:
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            if (not wrong(h)) and wrong(r): print(s,n[:55],'| head',desc(h),'|',v,desc(r))
# Q3: s flags fraction of head's wrong
print()
hw=0; flagged=0; hwp=0; flp=0
for s in SETS:
    for n,r in D[s]['s'].items():
        h=D[s]['head'][n]
        if wrong(h):
            hw+=1
            t=(r.get('fallback') or '')+(r.get('err') or '')
            f = ('moved the ring' in t) or ('ringLeftSeed' in t)
            flagged+=f
            if h['status']=='profile': hwp+=1; flp+=f
print('Q3: s flags',flagged,'of',hw,'head-wrong fits (%.1f%%);'%(100*flagged/hw),'of head-wrong profile fits',flp,'of',hwp,'(%.1f%%)'%(100*flp/hwp))
# per set
for s in SETS:
    hw=fl=0
    for n,r in D[s]['s'].items():
        h=D[s]['head'][n]
        if wrong(h):
            hw+=1; t=(r.get('fallback') or '')+(r.get('err') or ''); fl+=('moved the ring' in t) or ('ringLeftSeed' in t)
    print(' ',s,fl,'of',hw)
