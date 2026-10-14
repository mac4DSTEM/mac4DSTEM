import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
def reason(r):
    t=(r.get('fallback') or '')+(r.get('err') or '')
    if 'moved the ring' in t or 'ringLeftSeed' in t: return 'seed'
    if 'lost the ring' in t or 'ringWidthAtFloor' in t: return 'floor'
    return None
for v,rs in [('s','seed'),('b2','floor'),('cbs','seed'),('cbs','floor'),('cs','seed'),('cb','floor')]:
    better=worse=same=0; tb=[]; tw=[]; dRb=dRw=0
    Lw=[]
    thr=0
    for s in SETS:
        for n,r in D[s][v].items():
            h=D[s]['head'][n]
            if reason(r)!=rs or h['status']!='profile': continue
            if r['status']=='THREW': thr+=1; continue
            # compare to the plain head profile fit (what the refused fit would have been is head's only if v has no c; for c-variants compare to c's fit)
            ref = h if v in ('s','b2') else D[s]['c'][n]
            if not accepted(ref): continue
            ea,eb=abs(ref['dba']),abs(r['dba'])
            if eb<ea-2e-3: better+=1
            elif eb>ea+2e-3: worse+=1; Lw.append((s,n,ref,r))
            else: same+=1
    print(f'{v:4} refusal={rs:5}: fallback conic vs the refused profile fit (|dba| by 2e-3): better {better} same {same} worse {worse}; THREW (no fallback) {thr}')
    for s,n,ref,r in sorted(Lw,key=lambda x:-(abs(x[3]['dba'])-abs(x[2]['dba'])))[:6]:
        print(f"      worse: {s} {n[:46]} refused fit dR={ref['dR']:+.4f} dba={ref['dba']:+.4f} -> conic dR={r['dR']:+.4f} dba={r['dba']:+.4f}")
