from an2 import *
keys=["status","dR","dba","dth","cerr","resid","I1","sin","sout","s0"]
for S in "CPNT":
    R,names=cmp_sets(S)
    ob=oab=nb=nab=0; bad_b=[]; bad_ab=[]
    thr_b=thr_ab=0
    for n in names:
        H,A,B,AB=[R[v][n] for v in VARS]
        # b profile rows must equal head rows
        if B["status"]=="profile":
            nb+=1
            if all(B.get(k)==H.get(k) for k in keys): ob+=1
            else: bad_b.append(n)
        if AB["status"]=="profile":
            nab+=1
            if all(AB.get(k)==A.get(k) for k in keys): oab+=1
            else: bad_ab.append(n)
        # b non-profile rows: head must be profile or non-profile same
    print(S,"b profile rows identical to head:",ob,"/",nb," ab profile rows identical to a:",oab,"/",nab, bad_b[:3], bad_ab[:3])
    # what are b's refusals: head profile -> b conic
    ref=[n for n in names if R["head"][n]["status"]=="profile" and R["b"][n]["status"]!="profile"]
    # check refusal predicate: min(sin,sout) <= 0.30 at head
    viol=[n for n in ref if min(fl(R["head"][n],"sin"),fl(R["head"][n],"sout"))>0.30+1e-9]
    nonref=[n for n in names if R["head"][n]["status"]=="profile" and R["b"][n]["status"]=="profile" and min(fl(R["head"][n],"sin"),fl(R["head"][n],"sout"))<=0.30]
    print("   b refusals:",len(ref)," refused with min sigma>0.30:",len(viol)," head profile fits with min sigma<=0.30 not refused:",len(nonref))
    refa=[n for n in names if R["a"][n]["status"]=="profile" and R["ab"][n]["status"]!="profile"]
    viola=[n for n in refa if min(fl(R["a"][n],"sin"),fl(R["a"][n],"sout"))>0.30+1e-9]
    nonrefa=[n for n in names if R["a"][n]["status"]=="profile" and R["ab"][n]["status"]=="profile" and min(fl(R["a"][n],"sin"),fl(R["a"][n],"sout"))<=0.30]
    print("   ab refusals:",len(refa)," refused with min sigma>0.30:",len(viola)," a profile fits with min sigma<=0.30 not refused:",len(nonrefa))
