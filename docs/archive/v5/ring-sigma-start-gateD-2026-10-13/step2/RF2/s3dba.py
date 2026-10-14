import collections, sys, statistics as st
from p2 import parse2
pre=sys.argv[1]; VARS=["head","a","b","ab"]
R={v:parse2("%s_%s.log"%(pre,v)) for v in VARS}
names=list(R["head"])
grp=collections.defaultdict(list)
for n in names: grp[R["head"][n]["tier"]].append(n)
print("S3 by background (both noise levels pooled): accepted fits |d(b/a)|: n>0.01 / n>0.003 / median / max ; and |dR| n>1%% ")
for k in sorted(grp):
    v=grp[k]; out=[]
    for x in VARS:
        e=[abs(float(R[x][n]["dba"])) for n in v if R[x][n]["status"]!="THREW"]; r=[abs(float(R[x][n]["dR"])) for n in v if R[x][n]["status"]!="THREW"]
        out.append("%s: dba>0.01 %2d >0.003 %2d med %.1e max %.3f | dR>1%% %2d"%(x,sum(y>0.01 for y in e),sum(y>0.003 for y in e),st.median(e),max(e),sum(y>0.01 for y in r)))
    print(" %-11s n=%d\n    "%(k,len(v))+"\n    ".join(out))
