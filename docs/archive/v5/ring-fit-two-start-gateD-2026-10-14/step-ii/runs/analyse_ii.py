# Step (ii) analysis over logs/<set>_<variant>.log (rf2 rows). Wrong = accepted fit (any model) off > 1 % in (a+b)/2;
# right = within 0.1 %; lost = right under head, not right under v; newW = wrong under v, not wrong under head.
import sys, collections
SETS=['A','B','C','P','N','T','S3','S4']; VS=['head','a','b','none','c','b2','s','cb','cs','cbs']
def load(s,v):
    d={}
    for l in open(f'logs/{s}_{v}.log'):
        if l.startswith('ROW|'):
            kv=dict(p.split('=',1) for p in l.strip().split('|')[1:] if '=' in p); d[kv['name']]=kv
    return d
def cls(r):
    if r['status']=='THREW': return 'T'
    x=abs(float(r['dR'])); return 'R' if x<=0.001 else ('M' if x<=0.01 else 'W')
def ba(r): return abs(float(r['dba'])) if r['status']!='THREW' else 0.0
L={(s,v):load(s,v) for s in SETS for v in VS}
tot=collections.defaultdict(collections.Counter)
print('set  var   n  wrong(prof) right lost newW throw newThrow ba>.01 conic')
for s in SETS:
    H=L[(s,'head')]
    for v in VS:
        V=L[(s,v)]; c=collections.Counter(); c['n']=len(V)
        for k,h in H.items():
            r=V[k]; cr,ch=cls(r),cls(h)
            c['wrong']+=cr=='W'; c['wprof']+=(cr=='W' and r['status']=='profile'); c['right']+=cr=='R'
            c['lost']+=(ch=='R' and cr!='R'); c['newW']+=(cr=='W' and ch!='W'); c['throw']+=cr=='T'; c['newT']+=(cr=='T' and ch!='T')
            c['ba']+=ba(r)>0.01; c['conic']+=r['status']=='conic'
        tot[v].update(c)
        print(f"{s:<4} {v:<5} {c['n']:>4} {c['wrong']:>4}({c['wprof']:>3}) {c['right']:>5} {c['lost']:>4} {c['newW']:>4} {c['throw']:>5} {c['newT']:>8} {c['ba']:>6} {c['conic']:>5}")
print('\nTOTAL over 2009 plants')
for v in VS:
    c=tot[v]; print(f"  {v:<5} wrong {c['wrong']:>4} (profile {c['wprof']}) right {c['right']} lost {c['lost']} newW {c['newW']} throw {c['throw']} newThrow {c['newT']} ba>.01 {c['ba']} conic {c['conic']}")
# Q0: none == head and b2 == b, row for row (status, dR, dba, dth, cerr)
F=['status','dR','dba','dth','cerr']
for x,y in (('none','head'),('b2','b')):
    diff=sum(1 for s in SETS for k in L[(s,y)] if any(L[(s,x)][k].get(f)!=L[(s,y)][k].get(f) for f in F))
    print(f'Q0 {x} vs {y}: rows differing {diff}')
# projection: lower-cost of head and a profile fits, against c
for s in SETS:
    H,A,C=L[(s,'head')],L[(s,'a')],L[(s,'c')]; pw=cw=agree=0
    for k,h in H.items():
        a=A[k]; hp,ap=h['status']=='profile',a['status']=='profile'
        p = (h if float(h['resid'])<=float(a['resid']) else a) if hp and ap else (a if ap else h)
        pw+=cls(p)=='W'; cw+=cls(C[k])=='W'; agree+=(p['status']==C[k]['status'] and p.get('dR')==C[k].get('dR'))
    print(f'proj {s}: projection wrong {pw}, c wrong {cw}, rows identical {agree}/{len(H)}')
# S3/S4 r2 tiers
for v in ('head','a','c','cbs','s','b2'):
    w=lost=n=0
    for s in ('S3','S4'):
        H,V=L[(s,'head')],L[(s,v)]
        for k,h in H.items():
            if 'r2' not in h['tier']: continue
            n+=1; w+=cls(V[k])=='W'; lost+=(cls(h)=='R' and cls(V[k])!='R')
    print(f'r2 tiers (S3+S4, n={n}) {v}: wrong {w} right lost {lost}')
# s and the guards: refusals of right-at-head fits by reason
for v in ('s','b2','cbs','cs','cb'):
    rr=collections.Counter()
    for s in SETS:
        H,V=L[(s,'head')],L[(s,v)]
        for k,h in H.items():
            r=V[k]
            if cls(h)=='R' and r['status']!='profile' and h['status']=='profile':
                rr[(s, (r.get('fallback') or r.get('err') or '')[:40])]+=1
    print(f'{v}: right-at-head profile fits refused: {sum(rr.values())}', dict(rr) if rr else '')
# s flags: share of head's wrong fits that s turns into non-wrong
for v in ('s','b2','cbs'):
    hw=fixed=0
    for s in SETS:
        H,V=L[(s,'head')],L[(s,v)]
        for k,h in H.items():
            if cls(h)=='W': hw+=1; fixed+=cls(V[k])!='W'
    print(f'{v}: head wrong {hw}, no longer wrong {fixed} ({100*fixed/max(hw,1):.0f} %)')
