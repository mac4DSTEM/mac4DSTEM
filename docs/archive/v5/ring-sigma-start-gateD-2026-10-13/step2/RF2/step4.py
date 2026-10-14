from an2 import *
import re, collections
R,names=cmp_sets("N")
H,B,AB,A=R["head"],R["b"],R["ab"],R["a"]
def acc(d): return None if d["status"]=="THREW" else abs(fl(d,"dR"))
print("N: b refusals of HEAD profile fits, by HEAD state and true sigma")
tab=collections.defaultdict(lambda: collections.Counter())
for n in names:
    if H[n]["status"]=="profile" and B[n]["status"]!="profile":
        hs="right" if acc(H[n])<0.001 else ("mid" if acc(H[n])<=0.01 else "WRONG")
        tab[float(H[n]["sigma_true"])][hs]+=1
for s in sorted(tab): print("  sigma_true %.2f: %s"%(s,dict(tab[s])))
print("\nb refused-right (HEAD profile right, b conic): name | tier | s_true | HEAD sin,sout | HEAD dR | conic dR, dba | a dR | ab status")
rows=[]
for n in names:
    if H[n]["status"]=="profile" and acc(H[n])<0.001 and B[n]["status"]!="profile":
        rows.append(n)
        print("  %-34s %-7s s=%.2f  head sin/sout %.3f/%.3f dR %.1e | b %s dR %+.4f dba %+.4f | a dR %+.1e | ab %s"%(n,H[n]["tier"],float(H[n]["sigma_true"]),fl(H[n],"sin"),fl(H[n],"sout"),fl(H[n],"dR"),B[n]["status"],fl(B[n],"dR"),fl(B[n],"dba"),fl(A[n],"dR"),AB[n]["status"]))
import statistics as st
cd=[abs(fl(B[n],"dR")) for n in rows]; cb=[abs(fl(B[n],"dba")) for n in rows]
print("\n n=%d: conic |dR| max %.4f median %.5f, >0.1%%: %d, >1%%: %d ; conic |dba| max %.4f median %.5f"%(len(rows),max(cd),st.median(cd),sum(x>=0.001 for x in cd),sum(x>0.01 for x in cd),max(cb),st.median(cb)))
# HEAD's fitted sigma vs true for ALL right head profile fits with min sigma<=0.30 vs >0.30
print("\nfitted min sigma vs true sigma for HEAD profile fits that are right (<0.1%):")
by=collections.defaultdict(list)
for n in names:
    if H[n]["status"]=="profile" and acc(H[n])<0.001:
        by[float(H[n]["sigma_true"])].append(min(fl(H[n],"sin"),fl(H[n],"sout")))
for s in sorted(by): 
    v=by[s]; print("  sigma_true %.2f n=%2d  min(fitted) median %.3f  n<=0.30: %d"%(s,len(v),st.median(v),sum(x<=0.30 for x in v)))
# N: b's refusals that were WRONG at head (the catches) -- conic error
ctch=[n for n in names if H[n]["status"]=="profile" and acc(H[n])>0.01 and B[n]["status"]!="profile"]
cc=[abs(fl(B[n],"dR")) for n in ctch]; ccb=[abs(fl(B[n],"dba")) for n in ctch]
print("\nb catches (HEAD wrong -> conic): n=%d conic |dR| max %.4f med %.5f >1%%: %d ; HEAD wrong |dR| median %.3f, |dba| median %.3f"%(len(ctch),max(cc),st.median(cc),sum(x>0.01 for x in cc),st.median(abs(fl(H[n],"dR")) for n in ctch),st.median(abs(fl(H[n],"dba")) for n in ctch)))
# ab: what a does with narrow rings (a's fitted sigma, a right)
print("\nab vs a on N: ab refuses %d a-profile fits; of those, a-right: %d"%(sum(1 for n in names if A[n]["status"]=="profile" and AB[n]["status"]!="profile"),sum(1 for n in names if A[n]["status"]=="profile" and AB[n]["status"]!="profile" and acc(A[n])<0.001)))
refa=[n for n in names if A[n]["status"]=="profile" and AB[n]["status"]!="profile"]
byt=collections.Counter((float(A[n]["sigma_true"]),"right" if acc(A[n])<0.001 else ("mid" if acc(A[n])<=0.01 else "WRONG")) for n in refa)
print("  by (sigma_true, a-state):",sorted(byt.items()))
