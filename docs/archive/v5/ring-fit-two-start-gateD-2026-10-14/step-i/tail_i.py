# Background regime per HEAD profile fit: the central term at the ring, I0*exp(-R^2/(2 s0^2)), relative to I1;
# and the radial-profile slope across the annulus from the source's own profile file (mean at inner edge / at outer edge).
import math
def rows(f):
    return [dict(p.split('=',1) for p in l.strip().split('|')[1:] if '=' in p) for l in open(f) if l.startswith('ROW|')]
prof={'s3':'ws2/s3_mean.profile.txt','s4':'ws2/s4_bvm.profile.txt','s5':'nicu/s5_mean.profile.txt'}
def pval(src,r):
    if src not in prof: return None
    best=None
    for l in open(prof[src]):
        t=l.split()
        if len(t)<2 or t[0].startswith('#'): continue
        try: rr,m=float(t[0]),float(t[1])
        except: continue
        if best is None or abs(rr-r)<abs(best[0]-r): best=(rr,m)
    return best[1]
for s in ('au','s3','s4','s5'):
    for h in rows(f'runs/{s}-head.log'):
        if h['status']!='profile': continue
        R=(float(h['a'])+float(h['b']))/2; I1=float(h['I1']); I0=float(h['I0']); s0=float(h['s0'])
        tail=I0*math.exp(-R*R/(2*s0*s0))
        rel=tail/I1 if I1>0 else float('inf')
        pi,po=pval(s,float(h['inner'])),pval(s,float(h['outer']))
        slope=f" profile inner/outer {pi/po:.2f}" if pi and po else ''
        print(f"{s} {h['tag']:<10} R={R:6.2f} I1={I1:.3g} tail@R/I1={rel:.3g} bg/I1={float(h['bg'])/I1 if I1>0 else float('inf'):.3g}{slope}")
