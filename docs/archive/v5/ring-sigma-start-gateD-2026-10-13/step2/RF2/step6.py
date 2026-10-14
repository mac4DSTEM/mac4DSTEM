import collections, statistics as st, math
from p2 import parse2
def load(S): return parse2("logs/est_%s.log"%S)
def num(d,k):
    v=d.get(k,"nil")
    return None if v in ("nil",) else float(v)
def ratio(d,k): 
    x=num(d,k); s=float(d["sigma_true"])
    return None if x is None else x/s
def summ(rows, key, label):
    r=[ratio(d,key) for d in rows]; nil=sum(1 for x in r if x is None); v=sorted(x for x in r if x is not None)
    if not v: print("   %-24s n=%d nil=%d"%(label,len(rows),nil)); return
    q=lambda p: v[min(len(v)-1,int(p*len(v)))]
    print("   %-24s n=%3d nil=%3d  start/sigma_true: p10 %.2f p25 %.2f med %.2f p75 %.2f p90 %.2f  within[0.5,2]: %d/%d"%(label,len(rows),nil,q(.1),q(.25),q(.5),q(.75),q(.9),sum(0.5<=x<=2 for x in v),len(rows)))
print("== E1 theta convention: C noisy (sigma=3), by eps, using the seed theta / negated / rot90 / circular")
E=load("C")
for eps in ("0.01","0.03"):
    rows=[d for d in E.values() if d["tier"]=="noisy" and abs(float(d["eps"])-float(eps))<1e-3]
    print(" eps~%s n=%d"%(eps,len(rows)))
    for k in ("start_a","start_negtheta","start_rot90","start_circ"): summ(rows,k,k)
print("== E1b clean-ish: C clean (sigma=3) eps 3%")
rows=[d for d in E.values() if d["tier"]=="clean" and abs(float(d["eps"])-0.03)<1e-3]
for k in ("start_a","start_negtheta","start_rot90","start_circ"): summ(rows,k,k)
print("== E2 narrow rings N, start_a/sigma_true by sigma_true (HEAD start = ringWidth/4 = 10 or 4)")
E=load("N")
bys=collections.defaultdict(list)
for d in E.values(): bys[float(d["sigma_true"])].append(d)
for s in sorted(bys):
    v=[num(d,"start_a") for d in bys[s]]
    print("  sigma %.2f n=%d start_a: nil %d, values min %.2f med %.2f max %.2f"%(s,len(v),sum(x is None for x in v),min(x for x in v if x is not None),st.median([x for x in v if x is not None]),max(x for x in v if x is not None)))
print("== E3 Poisson P by amplitude tier: start_a/sigma_true (sigma_true=3)")
E=load("P")
for t in ("P-a10","P-a20","P-a50","P-a200"):
    summ([d for d in E.values() if d["tier"]==t],"start_a",t)
print("== E3b P-a10 by background kind")
byb=collections.defaultdict(list)
for n,d in E.items():
    if d["tier"]=="P-a10":
        kind=n.split("-")[-2] if False else n.rsplit("-",2)[1]
        byb[kind.rstrip("0123456789.")].append(d)
for k,v in byb.items(): summ(v,"start_a","a10 bg=%s"%k)
print("== E4 T-edge by (m_in,m_out): start_a vs sigma_true=3 / head start")
E=load("T")
for t in ("T-edge","T-neigh","T-slope","T-gap","T-wide","T-neigh2"):
    rows=[d for d in E.values() if d["tier"]==t]
    summ(rows,"start_a",t)
for n,d in list(E.items()):
    if d["tier"]=="T-edge" and n.endswith("-e3-n3-t20-"+n.split("-")[-1]) or False: pass
byname=collections.defaultdict(list)
for n,d in E.items():
    if d["tier"]=="T-edge": byname[n.split("-e")[0]].append(d)
for k,v in byname.items(): summ(v,"start_a",k)
byname=collections.defaultdict(list)
for n,d in E.items():
    if d["tier"]=="T-wide": byname[n.split("-e")[0]].append(d)
for k,v in sorted(byname.items()): summ(v,"start_a",k)
print("== T-neigh by neighbour: start_a/sigma_true (sigma 3; head start 10)")
byname=collections.defaultdict(list)
for n,d in E.items():
    if d["tier"]=="T-neigh": byname[n.split("-e")[0]].append(d)
for k,v in sorted(byname.items()): summ(v,"start_a",k)
