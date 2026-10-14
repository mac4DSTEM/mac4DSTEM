import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from swlib import parse,fl,acc,ba,rad,RUN,VARS
import math
src=sys.argv[1]; bases=sys.argv[2:]
V={v:parse(f'{RUN}/sweep-{src}-{v}.log') for v in VARS}
def seedrad(r): return (fl(r,'seed_a')+fl(r,'seed_b'))/2
def fm(r):
    if r.get('status')=='THREW': return 'THREW '+r.get('err','')[:42]
    s=f"{r['status'][:4]} rad={rad(r):7.3f} b/a={ba(r):.4f}"
    if r['status']=='profile': s+=f" dep={rad(r)/seedrad(r)-1:+.3f} sig={min(fl(r,'sin'),fl(r,'sout')):.2f} I1={fl(r,'I1'):.3g}"
    else: s+=' '+r.get('reason','')[:40]
    return s
for t in V['head']:
    if not any(t.startswith(b) for b in bases): continue
    h=V['head'][t]; c=V['cbs'][t]
    diff = (h.get('status')!=c.get('status')) or (acc(h) and acc(c) and (abs(ba(h)-ba(c))>0.005))
    seed = f"seed rad={seedrad(h):.3f} b/a={fl(h,'seed_b')/fl(h,'seed_a'):.4f} cres={fl(h,'seed_res'):.3f}" if 'seed_a' in h else 'no seed'
    print(f"{t:16} {'*' if diff else ' '} head: {fm(h):70} | cbs: {fm(c):60} | {seed}")
