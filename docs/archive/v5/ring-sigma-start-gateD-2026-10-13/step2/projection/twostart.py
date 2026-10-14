# Projection (NOT a measurement): "two starts, keep the lower-cost profile fit, then the usual cap/fallback",
# built from logged head and a rows of the same plant. Same pixels and normalisation per plant, so the
# normalised residual orders the costs. If only one variant returned a profile fit, the other was capped or
# refused (its residual was over the cap), so take the profile one. If neither, take HEAD's row.
import sys, collections
def load(f):
    d={}
    for line in open(f):
        if not line.startswith('ROW|'): continue
        kv=dict(p.split('=',1) for p in line.strip().split('|')[1:] if '=' in p)
        d[kv['name']]=kv
    return d
def res(r):
    for k in ('resid','res','normalizedResidual','nres'):
        if k in r: return float(r[k])
    raise KeyError(list(r))
def cls(r):
    if r['status']=='THREW': return 'T'
    x=abs(float(r['dR'])); return 'R' if x<=0.001 else ('M' if x<=0.01 else 'W')
def dba(r):
    return abs(float(r['dba'])) if r['status']!='THREW' else float('nan')
sets=[(n,h,a) for n,h,a in (x.split(',') for x in sys.argv[1:])]
tot=collections.Counter()
for name,hf,af in sets:
    H=load(hf); A=load(af); c=collections.Counter()
    for n,h in H.items():
        a=A[n]; hp=h['status']=='profile'; ap=a['status']=='profile'
        if hp and ap: p = h if res(h)<=res(a) else a
        elif ap: p=a
        else: p=h
        tier=h.get('tier','')
        c['n']+=1
        for lab,r in (('H',h),('A',a),('X',p)):
            k=cls(r); c[lab+k]+=1
            if k!='T' and dba(r)>0.01: c[lab+'_ba>.01']+=1
        if cls(h)=='R' and cls(p)!='R': c['X_lostRight']+=1
        if cls(p)=='W' and cls(h)!='W': c['X_newWrong']+=1
        if hp and ap and (p is a): c['X_choseA']+=1
    tot.update(c)
    print(name, ' '.join(f'{k}={v}' for k,v in sorted(c.items())))
print('TOTAL', ' '.join(f'{k}={v}' for k,v in sorted(tot.items())))
