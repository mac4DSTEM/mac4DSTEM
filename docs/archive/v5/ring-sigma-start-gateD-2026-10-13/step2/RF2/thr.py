import an2
from p2 import parse2
sets=[("C",None),("P",None),("N",None),("T",None),("S1","logs/S1"),("S3","logs/S3"),("CG0","logs/CG0"),("CG1","logs/CG1"),("CG3","logs/CG3"),("CG6","logs/CG6"),("CG12","logs/CG12")]
tot={v:0 for v in ("a","b","ab")}; n=0
for s,pre in sets:
    R={}
    for v in ("head","a","b","ab"):
        try: R[v]=an2.parse("%s/logs/%s_%s.log"%(an2.SP,s,v)) if pre is None else parse2("%s_%s.log"%(pre,v))
        except FileNotFoundError: R[v]=None
    if any(R[v] is None for v in R): 
        h=R["head"]; 
        print(s,"head threw",sum(1 for d in h.values() if d["status"]=="THREW"),"(a only run)", "a new throws",sum(1 for k,d in R["a"].items() if d["status"]=="THREW" and h[k]["status"]!="THREW") if R["a"] else ""); continue
    h=R["head"]; n+=len(h)
    line=["%s: head threw %d"%(s,sum(1 for d in h.values() if d["status"]=="THREW"))]
    for v in ("a","b","ab"):
        new=[k for k,d in R[v].items() if d["status"]=="THREW" and h[k]["status"]!="THREW"]
        gone=[k for k,d in R[v].items() if d["status"]!="THREW" and h[k]["status"]=="THREW"]
        tot[v]+=len(new); line.append("%s new throws %d (gone %d)"%(v,len(new),len(gone)))
    print(" | ".join(line))
print("total plants",n,"new throws",tot)
