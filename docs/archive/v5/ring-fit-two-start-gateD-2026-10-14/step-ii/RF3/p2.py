import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF3')
from lib import *
KEYS_NUM=['dR','dba','dth','cerr','resid','cres','cx','cy','fa','fb','fth']
KEYS_PROF=['I0','I1','s0','sin','sout','cbg']
def same(r1,r2,tol=0.0):
    if r1['status']!=r2['status']: return False
    if r1['status']=='THREW': return True   # error text compared separately
    ks=KEYS_NUM+(KEYS_PROF if r1['status']=='profile' else [])
    for k in ks:
        a,b=r1[k],r2[k]
        if a!=b and abs(a-b)>tol*max(abs(a),abs(b),1e-300): return False
    return True
def textsame(r1,r2):
    return (r1.get('fallback')==r2.get('fallback')) and (r1.get('err')==r2.get('err'))
D=load()
def cmp(v1,v2,label):
    tot=0; mism=0; txt=0
    ex=[]
    for s in SETS:
        for n,r in D[s][v1].items():
            tot+=1
            r2=D[s][v2][n]
            if not same(r,r2): mism+=1; ex.append((s,n))
            elif not textsame(r,r2): txt+=1
    print(f'{label}: {tot} rows, numeric mismatches {mism}, text-only differences {txt}', ex[:5])
cmp('none','head','X0 none vs head (exact)')
cmp('b2','b','X0 b2 vs b (exact)')
# X1: c in {head,a}
def which(v, cands):
    out={}
    for s in SETS:
        for n,r in D[s][v].items():
            w=[c for c in cands if same(r,D[s][c][n])]
            out[(s,n)]=w
    return out
for v,cands in [('c',['head','a']),('cb',['head','a','b']),('cs',['head','a','s']),('cbs',['head','a','b','s','c'])]:
    w=which(v,cands)
    none=[k for k,x in w.items() if not x]
    print(f'X1 {v}: rows equal to none of {cands}: {len(none)} of {len(w)}', none[:8])
