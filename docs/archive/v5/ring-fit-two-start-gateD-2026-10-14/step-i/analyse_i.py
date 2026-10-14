# Step (i) analysis: per source, annulus and variant — model, geometry, flags, seed move; b/a spread across annuli.
import sys, glob, collections, math
def rows(f):
    out=[]
    for line in open(f):
        if line.startswith('ROW|'):
            out.append(dict(p.split('=',1) for p in line.strip().split('|')[1:] if '=' in p))
    return out
def flags(r):
    fl=[]
    if r['status']!='profile': return fl
    inner,outer=float(r['inner']),float(r['outer']); a,b=float(r['a']),float(r['b']); R=(a+b)/2
    I1=float(r['I1']); sin_,sout=float(r['sin']),float(r['sout'])
    if I1<=1e-9*max(1,abs(float(r['I0']))): fl.append('I1=0')
    if min(sin_,sout)<=0.30: fl.append('sigma@floor')
    ceil=max(2,2*outer)
    if max(sin_,sout)>=ceil*0.999: fl.append('sigma@ceiling')
    if float(r['s0'])<=0.2501: fl.append('s0@floor')
    if not (inner<=R<=outer): fl.append('ring-outside-annulus')
    return fl
srcs=['au','s1','s2','s3','s4','s5']
for s in srcs:
    print(f'=== {s}')
    V={v:rows(f'runs/{s}-{v}.log') for v in ('head','a','b','ab')}
    for i,h in enumerate(V['head']):
        line=f"  {h['tag']:<12} [{float(h['inner']):g},{float(h['outer']):g}]"
        if 'seed_a' in h:
            sa,sb=float(h['seed_a']),float(h['seed_b']); seedR=(sa+sb)/2
            line+=f" seed R={seedR:.2f} b/a={sb/sa:.4f} res={float(h['seed_res']):.3f} |"
        else:
            seedR=None; line+=f" seed {h.get('seed','?')[:60]} |"
        for v in ('head','a','b','ab'):
            r=V[v][i]
            if r['status']=='THREW': line+=f" {v}:THREW({r['err'][:40]})"; continue
            a,b=float(r['a']),float(r['b']); R=(a+b)/2
            mv=f"{abs(R/seedR-1)*100:.1f}%" if seedR else '-'
            line+=f" {v}:{r['status'][0]} R={R:.2f} b/a={b/a:.4f} th={float(r['theta']):.3f} res={float(r['resid']):.3f} mv={mv}"
            fl=flags(r)
            if fl: line+='['+','.join(fl)+']'
        print(line)
    # spread of b/a across annuli per variant (accepted fits), flagged vs not
    for v in ('head','a','b','ab'):
        ok=[float(r['b'])/float(r['a']) for r in V[v] if r['status']!='THREW' and not flags(r)]
        allf=[float(r['b'])/float(r['a']) for r in V[v] if r['status']!='THREW']
        if allf: print(f"  {v}: b/a spread all {max(allf)-min(allf):.4f} (n={len(allf)}), unflagged {max(ok)-min(ok) if len(ok)>1 else float('nan'):.4f} (n={len(ok)})")
