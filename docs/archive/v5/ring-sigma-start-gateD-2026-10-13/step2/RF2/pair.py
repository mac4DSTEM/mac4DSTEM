import sys, statistics as st, collections
from an2 import *
S=sys.argv[1]; R,names=cmp_sets(S)
def e(d,k): return None if d["status"]=="THREW" else abs(fl(d,k))
def quant(v,p): v=sorted(v); return v[min(len(v)-1,int(p*len(v)))]
tiers=["ALL"]+sorted(set(R["head"][n]["tier"] for n in names)) if len(sys.argv)<3 else sys.argv[2:]
for sc in tiers:
    sel=[n for n in names if sc=="ALL" or R["head"][n]["tier"]==sc]
    print("== %s n=%d"%(sc,len(sel)))
    for key,lab in (("dR","|dR| (a+b)/2"),("dba","|d(b/a)| (what the app applies)"),("dth","dtheta rad")):
        row=[]
        for v in VARS:
            x=[e(R[v][n],key) for n in sel]; x=[y for y in x if y is not None]
            row.append("%s med %.2e mean %.2e p90 %.2e max %.2e"%(v,st.median(x),st.mean(x),quant(x,.9),max(x)))
        print("  %s:"%lab); [print("     "+r) for r in row]
    for v in ("a","b","ab"):
        better=worse=tie=0; wb=0
        for n in sel:
            h=e(R["head"][n],"dba"); x=e(R[v][n],"dba")
            if h is None or x is None: continue
            if x<h*0.8: better+=1
            elif x>h*1.25: worse+=1
            else: tie+=1
        worse10=sum(1 for n in sel if e(R["head"][n],"dba") is not None and e(R[v][n],"dba") is not None and e(R[v][n],"dba")>e(R["head"][n],"dba")+0.01)
        better10=sum(1 for n in sel if e(R["head"][n],"dba") is not None and e(R[v][n],"dba") is not None and e(R[v][n],"dba")+0.01<e(R["head"][n],"dba"))
        print("  paired |d(b/a)| %s vs head: >20%% better %d, >25%% worse %d, ~tie %d ; by >0.01 absolute: better %d worse %d"%(v,better,worse,tie,better10,worse10))
