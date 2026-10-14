import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
V={v:parse(f'{SPD}/E_{v}.log') for v in ['none','a','c','s','b2','cbs']}
def f(r):
    if r.get('status') not in ('profile','conic'): return 'THREW '+(r.get('err') or r.get('seed') or '')[:30]
    return f"{r['status'][:4]} dR={r['dR']:+.4f} dba={r['dba']:+.4f}"
for n in V['none']:
    h=V['none'][n]
    print(f"{n[:30]:30} seed dR={h.get('seed_dR',float('nan')):+.4f} depart(head)={h.get('depart',float('nan')):+.4f} | head {f(h):26} | c {f(V['c'][n]):26} | s {f(V['s'][n]):26} | cbs {f(V['cbs'][n]):26}")
