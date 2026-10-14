import sys, collections
from p2 import parse2
VARS=["head","a","b","ab"]
pre=sys.argv[1]  # e.g. logs/CG6
R={v:parse2("%s_%s.log"%(pre,v)) for v in VARS}
names=list(R["head"])
def acc(d): return None if d["status"]=="THREW" else abs(float(d["dR"]))
def state(d):
    if d["status"]=="THREW": return "T"
    e=acc(d)
    if d["status"]=="conic": return "C0" if e<=0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
for scope in ("noisy","clean"):
    sel=[n for n in names if R["head"][n]["tier"]==scope]
    print("== %s %s n=%d"%(pre,scope,len(sel)))
    for v in VARS:
        c=collections.Counter(state(R[v][n]) for n in sel)
        wrongany=sum(1 for n in sel if acc(R[v][n]) is not None and acc(R[v][n])>0.01)
        hr=[n for n in sel if acc(R["head"][n]) is not None and acc(R["head"][n])<0.001]
        lost=[n for n in hr if acc(R[v][n]) is None or acc(R[v][n])>=0.001]
        lost1=[n for n in hr if acc(R[v][n]) is None or acc(R[v][n])>0.01]
        bad=[n for n in sel if R[v][n]["status"]!="THREW" and abs(float(R[v][n]["dba"]))>0.01]
        print("   %-4s %s | wrongAny %d | right(HEAD) lost >=0.1%%: %d, >1%%: %d | |dba|>0.01 accepted: %d"%(v,dict(sorted(c.items())),wrongany,len(lost),len(lost1),len(bad)))
