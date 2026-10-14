#!/usr/bin/env python3
import sys, numpy as np
from cost2 import *
from p2 import parse2
import warnings; warnings.filterwarnings("ignore")
S=sys.argv[1]
head=parse2("logs/spot_%s_head.log"%S); a=parse2("logs/spot_%s_a.log"%S)
RFlog=lambda v: {}
import an2
RFall=an2.parse("%s/logs/%s_head.log"%(an2.SP,S))
def errs(P,pl):
    c=pl.c; R=c["R"]; return ((P[8]+P[9])/2/R-1, P[9]/P[8]-c["b"]/c["a"])
print("%-52s | %-7s %-8s %-8s %-7s | %-7s %-8s %-8s %-7s | %-7s %-8s | %-7s | seed"%("plant","H.stat","H.dR","H.dba","H.nres","a.stat","a.dR","a.dba","a.nres","T.fixed","T.basin","T.dR"))
for name in head:
    d_h, d_a = head[name], a[name]
    pl=Plant(S,name)
    out=[]
    cache={}
    for lab,d in (("H",d_h),("a",d_a)):
        if d["status"]=="profile":
            P=row_params(d); e=errs(P,pl)
            out.append((d["status"],e[0],e[1],pl.nres(P),float(d["resid"])))
        else:
            out.append((d["status"],float(d["dR"]),float(d["dba"]),float("nan"),float(d["resid"])))
    # truth fixed-geometry and basin
    st=row_params(d_h) if d_h["status"]=="profile" else (row_params(d_a) if d_a["status"]=="profile" else None)
    if st is None: st=np.array([pl.dyn,pl.dyn,pl.inner/2+10,3,3,pl.vmin,pl.truth[0],pl.truth[1],pl.truth[2],pl.truth[3],pl.truth[4]])
    geom=pl.truth
    # try several starts for the 6 free params
    best=None
    for s6 in (st[:6], np.array([pl.dyn*0.1,pl.dyn,10,3,3,pl.vmin])):
        P,cst=pl.fit_rest(geom,s6)
        if best is None or cst<best[1]: best=(P,cst)
    Pfix,cfix=best
    Pb,cb=pl.fit_rest(None,Pfix,full=True)
    nfix=np.sqrt(cfix/pl.N)/pl.dyn; nb=np.sqrt(cb/pl.N)/pl.dyn; eb=errs(Pb,pl)
    sd=RFall[name]
    print("%-52s | %-7s %8.4f %8.4f %7.4f | %-7s %8.4f %8.4f %7.4f | %7.4f %8.4f | %8.4f| %.4f %s"%(name,out[0][0],out[0][1],out[0][2],out[0][3],out[1][0],out[1][1],out[1][2],out[1][3],nfix,nb,eb[0],float(sd["seed_dR"]),"chk %.5f/%.5f"%(out[0][3],out[0][4])))
