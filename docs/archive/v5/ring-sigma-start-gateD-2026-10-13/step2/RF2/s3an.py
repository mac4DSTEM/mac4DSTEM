import collections, sys
from p2 import parse2
pre=sys.argv[1]
VARS=["head","a","b","ab"]
R={v:parse2("%s_%s.log"%(pre,v)) for v in VARS}
names=list(R["head"])
def acc(d): return None if d["status"]=="THREW" else abs(float(d["dR"]))
def state(d):
    if d["status"]=="THREW": return "T"
    e=acc(d)
    if d["status"]=="conic": return "C0" if e<=0.01 else "C1"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
grp=collections.defaultdict(list)
for n in names: grp[R["head"][n]["tier"]+"|n%s"%R["head"][n].get("noise","?")].append(n)
def key(n): 
    d=R["head"][n]; return (d["tier"], n.split("-n")[1].split("-")[0])
grp=collections.defaultdict(list)
for n in names: grp[key(n)].append(n)
print("group (bg, noise%%): n | head | a | b | ab states ; right(HEAD any model) lost under a (>=0.1%%) / count")
for k in sorted(grp):
    v=grp[k]
    cs={x:collections.Counter(state(R[x][n]) for n in v) for x in VARS}
    hr=[n for n in v if acc(R["head"][n]) is not None and acc(R["head"][n])<0.001]
    la=[n for n in hr if acc(R["a"][n]) is None or acc(R["a"][n])>=0.001]
    lb=[n for n in hr if acc(R["b"][n]) is None or acc(R["b"][n])>=0.001]
    print(" %-12s n%-3s %2d | H%s | a%s | b%s | ab%s | a lost %d/%d, b lost %d/%d"%(k[0],k[1],len(v),dict(sorted(cs["head"].items())),dict(sorted(cs["a"].items())),dict(sorted(cs["b"].items())),dict(sorted(cs["ab"].items())),len(la),len(hr),len(lb),len(hr)))
