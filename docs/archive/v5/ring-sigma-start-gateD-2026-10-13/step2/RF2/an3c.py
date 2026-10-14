import collections
from an2 import *
R,names=cmp_sets("T")
g=collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
def st(d):
    if d["status"]=="THREW": return "T"
    e=abs(fl(d,"dR"))
    if d["status"]=="conic": return "C0" if e<=0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
for n in names:
    t=R["head"][n]["tier"]
    if t in ("T-neigh","T-neigh2"):
        k=n.rsplit("-e",1)[0]
        for v in VARS: g[k][v][st(R[v][n])]+=1
print("%-22s %s"%("group","state counts head | a | b | ab   (R <0.1%, M 0.1-1%, W profile >1%, C0 conic <=1%, C1 conic >1%)"))
for k in sorted(g):
    print("%-22s %s"%(k," | ".join("%s: %s"%(v,"".join("%s%d "%(s,c) for s,c in sorted(g[k][v].items()))) for v in VARS)))
