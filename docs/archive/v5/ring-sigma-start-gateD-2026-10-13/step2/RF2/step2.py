from an2 import *
import math
KEYS=["status","dR","dba","dth","cerr","resid","I1","sin","sout","s0"]
def parse2(path):
    rows={}
    for ln in open(path):
        if ln.startswith("ROW|"):
            d={}
            for kv in ln.rstrip("\n").split("|")[1:]:
                k,_,v=kv.partition("="); d[k]=v
            rows[d["name"]]=d
    return rows
def same9(x,y):
    if x==y: return True
    try: fx,fy=float(x),float(y)
    except: return False
    if fx==fy: return True
    return float("%.9g"%fx)==float(y) or abs(fx-fy)<=1e-8*max(abs(fx),abs(fy),1e-300)*1 and "%.9g"%fx==("%.9g"%fy)
if __name__ != "__main__": raise SystemExit
tot=bad=0; badlist=[]
byset={}
for S in "CPNT":
    for v in VARS:
        mine=parse2("logs/spot_%s_%s.log"%(S,v)); RF=parse("%s/logs/%s_%s.log"%(SP,S,v))
        n=0;m=0
        for name,d in mine.items():
            r=RF[name]; n+=1
            diffs=[k for k in KEYS if k in r or k in d if not same9(d.get(k,"-"),r.get(k,"-"))]
            # near-equal fallback: relative to 1e-6 absolute
            real=[]
            for k in diffs:
                try:
                    if abs(float(d[k])-float(r[k]))<=1e-9*max(1,abs(float(r[k]))): continue
                except: pass
                real.append(k)
            if real: m+=1; badlist.append((S,v,name,real,[(d.get(k),r.get(k)) for k in real]))
        byset[(S,v)]=(n,m); tot+=n; bad+=m
print("compared",tot,"rows; mismatching rows:",bad)
for k,(n,m) in sorted(byset.items()): print(k,n,m)
for b in badlist[:20]: print(b)
