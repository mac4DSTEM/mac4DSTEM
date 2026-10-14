import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
V={v:parse(f'{SPD}/H_{v}.log') for v in ['none','a','c','s','cbs']}
def f(r):
    if r.get('status') not in ('profile','conic'): return 'THREW '+(r.get('err') or '')[:28]
    d=f" dep={r['depart']:+.3f}" if 'depart' in r else ''
    return f"{r['status'][:4]} dR={r['dR']:+.4f} dba={r['dba']:+.4f} res={r['resid']:.4f}{d}"
for n in V['none']:
    print(n, 'seed dR=%+.4f seed dba=%+.4f'%(V['none'][n]['seed_dR'],V['none'][n]['seed_dba']))
    for v in ['none','a','c','s','cbs']: print('    %-5s %s'%(v,f(V[v][n])))
