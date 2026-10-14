from p2 import parse2
import an2
def close(x,y):
    try: fx,fy=float(x),float(y)
    except: return x==y
    return abs(fx-fy)<=5e-9*max(abs(fy),abs(fx))+1e-300
tot=bad=0
for S in "PT":
    for v in ("head","a"):
        mine=parse2("logs/full_%s_%s.log"%(S,v)); RF=an2.parse("%s/logs/%s_%s.log"%(an2.SP,S,v))
        n=m=0
        assert list(mine)==list(RF), (S,v)
        for name,d in mine.items():
            r=RF[name]; n+=1
            diff=[k for k in ("status","dR","dba","dth","cerr","resid","I1","sin","sout","s0") if k in r and not close(d.get(k),r.get(k))]
            if diff: m+=1; print("MISMATCH",S,v,name,diff,[(d.get(k),r.get(k)) for k in diff][:2])
        print(S,v,"rows",n,"mismatching",m); tot+=n; bad+=m
print("TOTAL rows",tot,"mismatching",bad)
