import collections
from p2 import parse2
import an2
def acc(d): return None if d["status"]=="THREW" else abs(float(d["dR"]))
def state(d):
    if d["status"]=="THREW": return "T"
    e=acc(d)
    if d["status"]=="conic": return "C0" if e<=0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
print("Set C noisy (144) and clean (84): HEAD / a states by caller's centre-guess offset (px from the true centre)")
runs=[("0.0","logs/CG0"),("0.75","logs/CG1"),("1.6 (RF base)",None),("3.0","logs/CG3"),("7.8","logs/CG6"),("15.6","logs/CG12")]
for lab,pre in runs:
    out=[]
    for tier in ("noisy","clean"):
        for v in ("head","a"):
            if pre is None:
                R=an2.parse("%s/logs/C_%s.log"%(an2.SP,v))
            else:
                R=parse2("%s_%s.log"%(pre,v))
            sel=[n for n in R if R[n]["tier"]==tier]
            c=collections.Counter(state(R[n]) for n in sel)
            out.append("%s %s %s"%(tier,v,dict(sorted(c.items()))))
    print(" offset %-14s %s"%(lab," | ".join(out)))
