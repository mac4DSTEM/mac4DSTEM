import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
import math
from collections import Counter
D=load()
def e(r): return (abs(r['dR']),abs(r['dba'])) if accepted(r) else (math.nan,math.nan)
def desc(r):
    return f"{r['status'][:4]} dR={r['dR']:+.4f} dba={r['dba']:+.4f}" if accepted(r) else 'THREW'
def worse(x,y,tolR=1e-3,tolB=2e-3):
    # x worse than y: both accepted and (|dR| bigger by tolR) or (|dba| bigger by tolB)
    return (x[0]>y[0]+tolR) or (x[1]>y[1]+tolB)
for A,Bs in [('cbs',['c','b2','s']),('cbs',['c','cb','cs']),('cb',['c','b2']),('cs',['c','s'])]:
    out=[]
    for s in SETS:
        for n,r in D[s][A].items():
            if not accepted(r): continue
            ex=e(r)
            ok=True
            for B in Bs:
                rb=D[s][B][n]
                if not accepted(rb): ok=False; break
                if not worse(ex,e(rb)): ok=False; break
            if ok: out.append((s,n))
    print(f'{A} worse than ALL of {Bs} (accepted in all; |dR|+1e-3 or |dba|+2e-3): {len(out)}', Counter(x[0] for x in out))
    for s,n in out[:20]:
        print('   ',s,n[:50],{v:desc(D[s][v][n]) for v in ['head']+Bs+[A]})
# Also looser: cbs worse than at least c and (b2 or s) (not all)
print()
cnt=Counter(); lst=[]
for s in SETS:
    for n,r in D[s]['cbs'].items():
        c,b2,ss=D[s]['c'][n],D[s]['b2'][n],D[s]['s'][n]
        if not accepted(r): continue
        w_c = accepted(c) and worse(e(r),e(c))
        w_b = accepted(b2) and worse(e(r),e(b2))
        w_s = accepted(ss) and worse(e(r),e(ss))
        cnt[(w_c,w_b,w_s)]+=1
        if w_c and (w_b or w_s): lst.append((s,n,w_c,w_b,w_s))
print('cbs worse than (c, b2, s) pattern counts:',dict(cnt))
print('cbs worse than c and at least one of b2/s:',len(lst),Counter(x[0] for x in lst))
for s,n,wc,wb,ws in lst[:40]:
    print('   ',s,n[:55],'worse c/b2/s',wc,wb,ws,{v:desc(D[s][v][n]) for v in ['head','c','b2','s','cbs']})
print()
print('--- all plants where cbs is worse than head by > (1e-3 R or 2e-3 b/a) or newly wrong, and plants (False,True,True)/(True,False,True)')
for s in SETS:
    for n,r in D[s]['cbs'].items():
        h=D[s]['head'][n]; c,b2,ss=D[s]['c'][n],D[s]['b2'][n],D[s]['s'][n]
        if not accepted(r): continue
        pat=(accepted(c) and worse(e(r),e(c)), accepted(b2) and worse(e(r),e(b2)), accepted(ss) and worse(e(r),e(ss)))
        hw = accepted(h) and worse(e(r),e(h))
        if hw or pat in [(False,True,True),(True,False,True)]:
            print(s,n[:52],'pat',pat,'worseThanHead',hw,{v:desc(D[s][v][n]) for v in ['head','c','b2','s','cbs']})
