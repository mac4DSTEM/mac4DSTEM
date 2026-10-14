# Of the plants where HEAD and (a) both return profile fits of a different class (right <= 0.1 %, mid <= 1 %, wrong > 1 %
# in (a+b)/2), how often does the worse fit have the LOWER normalised residual (cost)? 2026-10-14: 8 of 441 (P 4, T 4).
# usage: python3 -I costorder.py <scratchpad lanes dir>
import sys
L=sys.argv[1]
def load(f):
    d={}
    for line in open(f):
        if line.startswith('ROW|'):
            kv=dict(p.split('=',1) for p in line.strip().split('|')[1:] if '=' in p); d[kv['name']]=kv
    return d
def res(r):
    for k in ('resid','res','normalizedResidual'):
        if k in r: return float(r[k])
def cls(r):
    x=abs(float(r['dR'])); return 0 if x<=0.001 else (1 if x<=0.01 else 2)
pairs=[('A',f'{L}/M/logs/head_A.log',f'{L}/M/logs/a_A.log'),('B',f'{L}/M/logs/head_B.log',f'{L}/M/logs/a_B.log')]+[(s,f'{L}/RF/logs/{s}_head.log',f'{L}/RF/logs/{s}_a.log') for s in 'CPNT']+[(s,f'{L}/RF2/logs/{s}_head.log',f'{L}/RF2/logs/{s}_a.log') for s in ('S3','S4')]
tot=bad=0
for s,hf,af in pairs:
    H=load(hf);A=load(af);n=b=0
    for k,h in H.items():
        a=A[k]
        if h['status']!='profile' or a['status']!='profile': continue
        ch,ca=cls(h),cls(a)
        if ch==ca: continue
        n+=1
        worse,better=(h,a) if ch>ca else (a,h)
        if res(worse)<res(better): b+=1
    print(s,'differing',n,'worse-at-lower-cost',b); tot+=n; bad+=b
print('TOTAL',tot,bad)
