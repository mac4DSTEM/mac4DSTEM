import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from p12 import *
from collections import Counter, defaultdict
s=sys.argv[1] if len(sys.argv)>1 else 'Z'
VS=[v for v in ['none','a','c','b2','s','cbs'] if os.path.exists(f'{SPD}/{s}_{v}.log')]
V={v:parse(f'{SPD}/{s}_{v}.log') for v in VS}
N=V['none']
def acc(r): return r.get('status') in ('profile','conic')
def wr(r): return acc(r) and abs(r['dR'])>0.01
def rt(r): return acc(r) and abs(r['dR'])<=0.001
print('set',s,{v:len(r) for v,r in V.items()})
sd=[abs(r['seed_dR']) for r in N.values() if r.get('seed')=='ok']
print('seed THREW:',sum(r.get('seed')!='ok' for r in N.values()),' conic-seed |dR| p50 %.4f p90 %.4f p99 %.4f max %.4f'%(q(sd,.5),q(sd,.9),q(sd,.99),max(sd)))
for v in VS:
    rr=V[v].values()
    print(f"{v:5} wrong {sum(wr(r) for r in rr):3d} right {sum(rt(r) for r in rr):3d} threw {sum(not acc(r) for r in rr):3d} conic {sum(r.get('status')=='conic' for r in rr):3d} |dba|>.01 {sum(acc(r) and abs(r['dba'])>0.01 for r in rr):3d} median|dba| {q([abs(r['dba']) for r in rr if acc(r)],.5):.4f} max|dba| {max(abs(r['dba']) for r in rr if acc(r)):.3f}")
# right head fits refused by s / cbs
for v in ['s','cbs','b2']:
    if v not in V: continue
    L=[(n,N[n],V[v][n]) for n in N if rt(N[n]) and not rt(V[v][n])]
    print(f'right-under-head lost under {v}:',len(L))
    for n,h,r in L[:60]:
        print(f"   {n[:48]:48} head dR={h['dR']:+.4f} dba={h['dba']:+.4f} depart={h['depart']:+.3f} | {v}: {r.get('status')} dR={r.get('dR',float('nan')):+.4f} dba={r.get('dba',float('nan')):+.4f} {r.get('fallback','')[:40]}")
# right profile fits departure
for v in ['none','a','c']:
    rr=[abs(r['depart']) for r in V[v].values() if r.get('status')=='profile' and abs(r['dR'])<=0.001]
    print(f'{v}: right profile fits {len(rr)} depart p50 %.3f p90 %.3f max %.3f  >0.08: {sum(x>.08 for x in rr)}'%(q(rr,.5),q(rr,.9),max(rr)))
