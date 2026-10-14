from an2 import *
import random
def acc(d): return None if d["status"]=="THREW" else abs(fl(d,"dR"))
out={}
R,names=cmp_sets("P")
H,A=R["head"],R["a"]
out["P"]=[n for n in names if acc(H[n]) is not None and acc(H[n])<0.001 and (acc(A[n]) is None or acc(A[n])>=0.001)]
out["P"]+=[n for n in names if H[n]["status"]=="profile" and 0.001<=acc(H[n])<=0.01 and A[n]["status"]=="profile" and acc(A[n])>0.01]
R,names=cmp_sets("N")
H,B=R["head"],R["b"]
out["N"]=[n for n in names if acc(H[n])<0.001 and B[n]["status"]!="profile"]
R,names=cmp_sets("T")
H,A=R["head"],R["a"]
out["T"]=[n for n in names if acc(H[n]) is not None and acc(H[n])<0.001 and (acc(A[n]) is None or acc(A[n])>=0.001)]
out["T"]+=[n for n in names if H[n]["status"]=="profile" and 0.001<=acc(H[n])<=0.01 and A[n]["status"]=="profile" and acc(A[n])>0.01]
R,names=cmp_sets("C")
H,A=R["head"],R["a"]
random.seed(7)
w=[n for n in names if H[n]["status"]=="profile" and acc(H[n])>0.01]
c=[n for n in names if H[n]["tier"]=="clean" and H[n]["status"]=="conic"]
out["C"]=random.sample(w,3)+random.sample(c,3)
for S,l in out.items():
    open("spot_%s.txt"%S,"w").write("\n".join(l)+"\n"); print(S,len(l))
