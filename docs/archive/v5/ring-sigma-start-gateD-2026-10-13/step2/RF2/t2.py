from an2 import *
import sys
def state(d, ref=None):
    st=d["status"]
    if st=="THREW": return "T"
    e=abs(fl(d,"dR"))
    if st=="conic": return "C0" if e<0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
S=sys.argv[1]; R,names=cmp_sets(S)
order=["R","M","W","C0","C1","T"]
tiers=["ALL"]+sorted(set(R["head"][n]["tier"] for n in names)) if len(sys.argv)<3 else sys.argv[2:]
for scope in tiers:
    sel=[n for n in names if scope=="ALL" or R["head"][n]["tier"]==scope]
    print("==",scope,len(sel))
    print("   state counts:",{v:{s:sum(1 for n in sel if state(R[v][n])==s) for s in order if any(state(R[v][n])==s for n in sel)} for v in VARS})
    for v in ["a","b","ab"]:
        m=collections.Counter((state(R["head"][n]),state(R[v][n])) for n in sel)
        print("   head->%s:"%v, ", ".join("%s>%s:%d"%(x,y,k) for (x,y),k in sorted(m.items()) if x!=y))
