import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from swlib import parse,fl,acc,ba,rad,RUN,VARS
import math, statistics as st
def seedrad(r): return (fl(r,'seed_a')+fl(r,'seed_b'))/2
for src,fams in [('au',[('A1','W1'),('A2','W2'),('A3','W3')]),('s3',[('s3-R3','s3-R3w')])]:
    V={v:parse(f'{RUN}/sweep-{src}-{v}.log') for v in VARS}
    for fam in fams:
        ts=[t for t in V['head'] if t.split('~')[0].split(':')[0] in fam or t.split('~')[0] in fam]
        prof=[t for t in ts if V['head'][t].get('status')=='profile']
        mr=st.median(rad(V['head'][t]) for t in prof); mb=st.median(ba(V['head'][t]) for t in prof)
        print(f'--- {fam}: n profile {len(prof)}, median rad {mr:.3f}, median b/a {mb:.4f}')
        ok=[t for t in prof if V['s'][t].get('status')=='profile']
        ref=[t for t in prof if V['s'][t].get('status')!='profile']
        def rng(L,f): 
            v=[f(V['head'][t]) for t in L]; return (min(v),max(v)) if v else (math.nan,math.nan)
        print(f"   kept by s ({len(ok)}): rad {rng(ok,rad)[0]:.3f}-{rng(ok,rad)[1]:.3f}  b/a {rng(ok,ba)[0]:.4f}-{rng(ok,ba)[1]:.4f}  seed rad {rng(ok,seedrad)[0]:.3f}-{rng(ok,seedrad)[1]:.3f} seed b/a {min(fl(V['head'][t],'seed_b')/fl(V['head'][t],'seed_a') for t in ok):.4f}-{max(fl(V['head'][t],'seed_b')/fl(V['head'][t],'seed_a') for t in ok):.4f}")
        print(f"   refused by s ({len(ref)}): rad {rng(ref,rad)[0]:.3f}-{rng(ref,rad)[1]:.3f}  b/a {rng(ref,ba)[0]:.4f}-{rng(ref,ba)[1]:.4f}  seed rad {rng(ref,seedrad)[0]:.3f}-{rng(ref,seedrad)[1]:.3f}  seed b/a {min(fl(V['head'][t],'seed_b')/fl(V['head'][t],'seed_a') for t in ref):.4f}-{max(fl(V['head'][t],'seed_b')/fl(V['head'][t],'seed_a') for t in ref):.4f}" if ref else "   refused by s (0)")
        for t in ref:
            h=V['head'][t]; sr=V['s'][t]
            print(f"      {t:16} head rad={rad(h):.3f} b/a={ba(h):.4f} dep={rad(h)/seedrad(h)-1:+.3f} seed cres={fl(h,'seed_res'):.3f} | s: {sr.get('status')} {sr.get('reason',sr.get('err',''))[:50]}")
