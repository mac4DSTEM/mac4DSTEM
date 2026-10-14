from an2 import *
import sys
S=sys.argv[1]; R,names=cmp_sets(S)
for v in VARS:
    for scope in ["noisy","ALL"]:
        sel=[n for n in names if scope=="ALL" or R["head"][n]["tier"]==scope]
        c=collections.Counter()
        for n in sel:
            d=R[v][n]; st=d["status"]
            e=abs(fl(d,"dR")) if st!="THREW" else None
            c[st]+=1
            if st=="profile" and e>0.01: c["prof_dR>1%"]+=1
            if st=="profile" and e>0.001: c["prof_dR>0.1%"]+=1
            if st=="profile" and abs(fl(d,"dba"))>0.01: c["prof_dba>1e-2"]+=1
            if st=="conic" and e>0.01: c["conic_dR>1%"]+=1
            if st=="conic" and e>0.001: c["conic_dR>0.1%"]+=1
        print(scope,v,dict(c))
