import collections, re
from an2 import *
R,names=cmp_sets("P")
def st_(d):
    if d["status"]=="THREW": return "T"
    e=abs(fl(d,"dR"))
    if d["status"]=="conic": return "C0" if e<=0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
def bg(n): return re.search(r"-(none|const|exp|r2|tilt)",n).group(1) if re.search(r"-(none|const|exp|r2|tilt)",n) else "?"
tab=collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
for n in names:
    k=(R["head"][n]["tier"],bg(n))
    for v in VARS: tab[bg(n)][v][st_(R[v][n])]+=1
    tab[bg(n)]["_n"]["n"]+=1
print("P set by background kind (all amplitudes):  states R(<0.1%) M W(>1%) C0 C1 T")
for b in sorted(tab):
    print(" %-6s n=%d"%(b,tab[b]["_n"]["n"]))
    for v in VARS: print("    %-4s %s"%(v,dict(sorted(tab[b][v].items()))))
# lost-right under a by bg and tier
lost=collections.Counter(); tot=collections.Counter()
for n in names:
    if st_(R["head"][n])=="R" or (R["head"][n]["status"]=="conic" and abs(fl(R["head"][n],"dR"))<0.001):
        tot[(R["head"][n]["tier"],bg(n))]+=1
        if not (R["a"][n]["status"]!="THREW" and abs(fl(R["a"][n],"dR"))<0.001): lost[(R["head"][n]["tier"],bg(n))]+=1
print("\nright-at-HEAD plants lost under a, by (amplitude tier, background): lost/right")
for t in ("P-a10","P-a20","P-a50","P-a200"):
    print("  %-7s "%t+"  ".join("%s %d/%d"%(b,lost[(t,b)],tot[(t,b)]) for b in ("none","const","exp","r2","tilt")))
