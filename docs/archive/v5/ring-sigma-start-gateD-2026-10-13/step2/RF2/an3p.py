import sys, collections, statistics as st
f=sys.argv[1]
rows=[]
for ln in open(f).read().splitlines()[1:]:
    p=[x.strip() for x in ln.split("|")]
    name=p[0]; H=p[1].split(); A=p[2].split(); T=p[3].split()
    rows.append(dict(name=name,tier=name.split("-R")[0] if name.startswith("P-") else name,Hs=H[0],HdR=float(H[1]),Hdba=float(H[2]),Hn=float(H[3]),As=A[0],AdR=float(A[1]),Adba=float(A[2]),An=float(A[3]),Tf=float(T[0]),Tb=float(T[1]),TbdR=float(T[2]),Tbdba=float(T[3])))
def right(x): return abs(x)<0.001
def wrong(x): return abs(x)>0.01
nan=float("nan")
def fin(x): return x==x
print("n=%d plants"%len(rows))
# (1) the lost-right plants
lost=[r for r in rows if right(r["HdR"]) and not right(r["AdR"])]
print("\n(1) HEAD right (<0.1%%) and a not right: %d plants"%len(lost))
c=collections.Counter()
for r in lost:
    hn,an_,tb=r["Hn"],r["An"],r["Tb"]
    if r["As"]!="profile": c["a not profile"]+=1; continue
    rel=an_/hn
    c["a cost < HEAD cost (a is the better optimum)" if an_<hn*0.9999 else ("costs equal(+-0.01%)" if an_<=hn*1.0001 else "a cost > HEAD cost (a worse optimum)")]+=1
    c["a within 2%% of truth-basin cost" if an_<=tb*1.02 else "a cost >2%% above truth-basin"]+=1
    c["HEAD within 2%% of truth-basin cost" if hn<=tb*1.02 else "HEAD >2%% above truth-basin cost"]+=1
    c["truth-basin |dR| < 0.1%%" if abs(r["TbdR"])<0.001 else "truth-basin |dR| >= 0.1%% (the model's own optimum is off truth)"]+=1
for k,v in sorted(c.items()): print("   %3d  %s"%(v,k))
print("   |dR| of lost: HEAD median %.1e max %.1e ; a median %.1e p75 %.1e max %.1e"%(st.median(abs(r["HdR"]) for r in lost),max(abs(r["HdR"]) for r in lost),st.median(abs(r["AdR"]) for r in lost),sorted(abs(r["AdR"]) for r in lost)[int(.75*len(lost))],max(abs(r["AdR"]) for r in lost)))
print("   |d(b/a)| of lost: HEAD median %.1e max %.1e ; a median %.1e p75 %.1e max %.1e"%(st.median(abs(r["Hdba"]) for r in lost),max(abs(r["Hdba"]) for r in lost),st.median(abs(r["Adba"]) for r in lost),sorted(abs(r["Adba"]) for r in lost)[int(.75*len(lost))],max(abs(r["Adba"]) for r in lost)))
print("   truth-basin |dR| of lost: median %.1e max %.1e ; |dba| median %.1e max %.1e"%(st.median(abs(r["TbdR"]) for r in lost),max(abs(r["TbdR"]) for r in lost),st.median(abs(r["Tbdba"]) for r in lost),max(abs(r["Tbdba"]) for r in lost)))
print("\n   per-plant (lost): name | H dR dba nres | a dR dba nres | Tbasin nres dR dba")
for r in sorted(lost,key=lambda r:r["name"]):
    print("   %-40s | %+.4f %+.4f %.4f | %+.4f %+.4f %.4f | %.4f %+.4f %+.4f"%(r["name"],r["HdR"],r["Hdba"],r["Hn"],r["AdR"],r["Adba"],r["An"],r["Tb"],r["TbdR"],r["Tbdba"]))
# (2) HEAD wrong set
hw=[r for r in rows if r["Hs"]=="profile" and wrong(r["HdR"])]
print("\n(2) HEAD wrong profile fits: %d"%len(hw))
c=collections.Counter()
for r in hw:
    c["HEAD cost >5%% above truth-basin" if r["Hn"]>r["Tb"]*1.05 else ("HEAD cost within 5%% of truth-basin" if r["Hn"]>=r["Tb"]*0.95 else "HEAD cost >5%% BELOW truth-basin (truth is not the model's optimum)")]+=1
    if r["As"]=="profile": c["  a fit cost < HEAD cost" if r["An"]<r["Hn"] else "  a fit cost >= HEAD cost"]+=1
    c["  a still wrong" if (r["As"]=="profile" and wrong(r["AdR"])) else "  a fixed (<=1%)"]+=1
    if r["As"]=="profile" and wrong(r["AdR"]):
        c["    a-wrong: a cost within 5%% of truth-basin" if r["An"]<=r["Tb"]*1.05 else "    a-wrong: a cost >5%% above truth-basin"]+=1
        c["    a-wrong: truth basin cost < a cost by >5%% => truth fairly better" if r["Tb"]<r["An"]*0.95 else "    a-wrong: truth basin cost not lower by 5%% (ambiguous/unfair truth)"]+=1
for k,v in sorted(c.items()): print("   %3d  %s"%(v,k))
# (3) all plants: a cost vs H cost
bo=[r for r in rows if r["Hs"]=="profile" and r["As"]=="profile"]
print("\n(3) both profile: %d ; a cost < HEAD cost: %d ; a cost > HEAD cost*1.01: %d ; equal: %d"%(len(bo),sum(r["An"]<r["Hn"]*0.9999 for r in bo),sum(r["An"]>r["Hn"]*1.01 for r in bo),sum(abs(r["An"]/r["Hn"]-1)<=1e-4 for r in bo)))
print("    a at a worse cost than HEAD AND |dR| worse than HEAD by >0.5%%: %d"%(sum(1 for r in bo if r["An"]>r["Hn"]*1.01 and abs(r["AdR"])>abs(r["HdR"])+0.005)))
byt=collections.defaultdict(list)
for r in rows: byt[r["tier"]].append(r)
for t,v in sorted(byt.items()):
    bo=[r for r in v if r["Hs"]=="profile" and r["As"]=="profile"]
    lost=[r for r in v if right(r["HdR"]) and not right(r["AdR"])]
    print("  %-7s n=%d bothprofile=%d: a cost<H %d, a cost>1.01*H %d ; truth-basin cost lower than HEAD's by >5%%: %d, than a's: %d ; lost-right %d (of which a cost<H cost: %d)"%(t,len(v),len(bo),sum(r["An"]<r["Hn"]*0.9999 for r in bo),sum(r["An"]>r["Hn"]*1.01 for r in bo),sum(r["Tb"]<r["Hn"]*0.95 for r in bo),sum(r["Tb"]<r["An"]*0.95 for r in bo),len(lost),sum(1 for r in lost if r["As"]=="profile" and r["An"]<r["Hn"]*0.9999)))
