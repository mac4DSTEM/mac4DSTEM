from an2 import *
import sys
# model-agnostic accuracy: any accepted fit (profile or conic); threw -> lost
S=sys.argv[1]; R,names=cmp_sets(S)
def acc(d):
    if d["status"]=="THREW": return None
    return abs(fl(d,"dR"))
tiers=["ALL"]+sorted(set(R["head"][n]["tier"] for n in names))
for scope in tiers:
    sel=[n for n in names if scope=="ALL" or R["head"][n]["tier"]==scope]
    hr=[n for n in sel if acc(R["head"][n]) is not None and acc(R["head"][n])<0.001]
    hw=[n for n in sel if R["head"][n]["status"]=="profile" and acc(R["head"][n])>0.01]
    out=["%-8s n=%d headRight(any model)=%d headWrongProf=%d"%(scope,len(sel),len(hr),len(hw))]
    for v in ["a","b","ab"]:
        lost=[n for n in hr if acc(R[v][n]) is None or acc(R[v][n])>=0.001]
        lost1=[n for n in hr if acc(R[v][n]) is None or acc(R[v][n])>0.01]
        wrong_any=[n for n in sel if acc(R[v][n]) is not None and acc(R[v][n])>0.01]
        fixed=[n for n in hw if acc(R[v][n]) is not None and acc(R[v][n])<=0.01]
        out.append("   %-2s: wrongAny(>1%%)=%d  rightLost(>=0.1%%)=%d  rightLost(>1%%)=%d  headWrongFixed(<=1%%)=%d/%d"%(v,len(wrong_any),len(lost),len(lost1),len(fixed),len(hw)))
    print("\n".join(out))
