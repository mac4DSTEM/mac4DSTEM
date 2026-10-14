import sys, collections, statistics as st
f=sys.argv[1]
rows=[]
for ln in open(f).read().splitlines()[1:]:
    p=[x.strip() for x in ln.split("|")]
    name=p[0]; H=p[1].split(); A=p[2].split(); T=p[3].split()
    rows.append(dict(name=name,Hs=H[0],HdR=float(H[1]),Hdba=float(H[2]),Hn=float(H[3]),Hr=float(H[4]),As=A[0],AdR=float(A[1]),Adba=float(A[2]),An=float(A[3]),Ar=float(A[4]),Tf=float(T[0]),Tb=float(T[1]),TbdR=float(T[2]),Tbdba=float(T[3])))
mx=max(abs(r["Hn"]-r["Hr"]) for r in rows if r["Hs"]=="profile"); print("replica vs logged resid (HEAD profile fits): max abs diff %.2e"%mx)
mxa=max(abs(r["An"]-r["Ar"]) for r in rows if r["As"]=="profile"); print("replica vs logged resid (a profile fits): max abs diff %.2e"%mxa)
g=collections.defaultdict(list)
for r in rows: g[r["name"].rsplit("-e",1)[0]].append(r)
print("%-22s n | HEAD: med|dR| med nres | a: med|dR| med nres (a status) | truth basin: med nres, med|dR| | cost order"%"group")
for k in sorted(g):
    v=g[k]
    def med(x): return st.median(x)
    print("%-22s %d | H |dR| %.4f nres %.4f | a |dR| %.4f nres %s (%s) | Tbasin nres %.4f |dR| %.4f | a-cost>H-cost: %d/%d  H-cost>Tbasin*1.05: %d  a-cost>Tbasin*1.05: %d"%(
        k,len(v),med([abs(r["HdR"]) for r in v]),med([r["Hn"] for r in v if r["Hn"]==r["Hn"]] or [float('nan')]),
        med([abs(r["AdR"]) for r in v]),("%.4f"%med([r["An"] for r in v if r["An"]==r["An"]])) if any(r["An"]==r["An"] for r in v) else "n/a", ",".join(sorted(set(r["As"] for r in v))),
        med([r["Tb"] for r in v]),med([abs(r["TbdR"]) for r in v]),
        sum(1 for r in v if r["Hn"]==r["Hn"] and r["An"]==r["An"] and r["An"]>r["Hn"]*1.0001), sum(1 for r in v if r["Hn"]==r["Hn"] and r["An"]==r["An"]),
        sum(1 for r in v if r["Hn"]==r["Hn"] and r["Hn"]>r["Tb"]*1.05), sum(1 for r in v if r["An"]==r["An"] and r["An"]>r["Tb"]*1.05)))
