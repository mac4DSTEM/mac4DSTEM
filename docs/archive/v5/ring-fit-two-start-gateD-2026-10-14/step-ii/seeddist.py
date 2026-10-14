# Distribution of the seed move m = |R_profile / R_seed - 1| for right (<=0.1 %) and wrong (>1 %) accepted profile fits,
# per set and variant (head, a), from logged rows that carry seed_dR. Informs the seed check's threshold (not a decision).
import sys, glob
def load(f):
    for line in open(f):
        if line.startswith('ROW|'):
            yield dict(p.split('=',1) for p in line.strip().split('|')[1:] if '=' in p)
def q(xs,p):
    xs=sorted(xs); 
    return xs[min(len(xs)-1,int(p*(len(xs)-1)))] if xs else float('nan')
L=sys.argv[1]
files=[('A',f'{L}/M/logs/%s_A.log'),('B',f'{L}/M/logs/%s_B.log')]+[(s,f'{L}/RF/logs/{s}_%s.log') for s in 'CPNT']
allR=[];allW=[]
for s,pat in files:
    for v in ('head','a'):
        R=[];W=[]
        for h in load(pat%v):
            if h.get('status')!='profile' or 'seed_dR' not in h: continue
            dR=float(h['dR']); m=abs((1+dR)/(1+float(h['seed_dR']))-1)
            (R if abs(dR)<=0.001 else W if abs(dR)>0.01 else []).append(m)
        allR+=R; allW+=W
        print(f'{s} {v}: right n={len(R)} p50={q(R,.5):.4f} p99={q(R,.99):.4f} max={max(R) if R else float("nan"):.4f} | wrong n={len(W)} min={min(W) if W else float("nan"):.4f} p10={q(W,.1):.4f}')
print(f'ALL right n={len(allR)} p99={q(allR,.99):.4f} p999={q(allR,.999):.4f} max={max(allR):.4f} | wrong n={len(allW)} p05={q(allW,.05):.4f} p10={q(allW,.1):.4f}')
for t in (0.01,0.02,0.03,0.05,0.08,0.10):
    print(f'  T={t:.2f}: right flagged {sum(m>t for m in allR)}/{len(allR)}  wrong flagged {sum(m>t for m in allW)}/{len(allW)}')
