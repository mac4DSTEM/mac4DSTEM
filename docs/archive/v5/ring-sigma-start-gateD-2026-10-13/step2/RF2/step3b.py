#!/usr/bin/env python3
# usage: step3b.py <S> <tier-substring> <out>   -- cost analysis over every plant of the tier using logs/full_<S>_{head,a}.log (full %.17g params)
import sys, numpy as np, multiprocessing as mp, warnings
warnings.filterwarnings("ignore")
from cost2 import *
from p2 import parse2
S,tier,out=sys.argv[1],sys.argv[2],sys.argv[3]
H=parse2("logs/full_%s_head.log"%S); A=parse2("logs/full_%s_a.log"%S)
names=[n for n in H if tier in H[n]["tier"] and n in A]
def errs(P,pl):
    c=pl.c; return ((P[8]+P[9])/2/c["R"]-1, P[9]/P[8]-c["b"]/c["a"])
def work(name):
    pl=Plant(S,name); dh,da=H[name],A[name]
    res={"name":name}
    for lab,d in (("H",dh),("a",da)):
        if d["status"]=="profile":
            P=row_params(d); e=errs(P,pl); res[lab]=("profile",e[0],e[1],pl.nres(P),float(d["resid"]))
        else: res[lab]=(d["status"],float(d.get("dR","nan")),float(d.get("dba","nan")),float("nan"),float(d.get("resid","nan")))
    st=row_params(dh) if dh["status"]=="profile" else (row_params(da) if da["status"]=="profile" else np.array([pl.dyn,pl.dyn,pl.inner/2+10,3,3,pl.vmin]+list(pl.truth)))
    best=None
    for s6 in (st[:6], np.array([pl.dyn*0.1,pl.dyn,10,3,3,pl.vmin])):
        P,cst=pl.fit_rest(pl.truth,s6)
        if best is None or cst<best[1]: best=(P,cst)
    Pfix,cfix=best
    Pb,cb=pl.fit_rest(None,Pfix,full=True)
    res["Tfix"]=np.sqrt(cfix/pl.N)/pl.dyn; res["Tbasin"]=np.sqrt(cb/pl.N)/pl.dyn; res["Tb_err"]=errs(Pb,pl)
    return res
if __name__=="__main__":
    with mp.Pool(4) as pool: R=pool.map(work,names,chunksize=2)
    with open(out,"w") as f:
        f.write("name | H: status dR dba nres(replica) resid(log) | a: status dR dba nres resid | Tfix Tbasin Tbasin_dR Tbasin_dba\n")
        for r in R:
            f.write("%s | %s %.5f %.5f %.5f %.5f | %s %.5f %.5f %.5f %.5f | %.5f %.5f %.5f %.5f\n"%(r["name"],*r["H"],*r["a"],r["Tfix"],r["Tbasin"],r["Tb_err"][0],r["Tb_err"][1]))
