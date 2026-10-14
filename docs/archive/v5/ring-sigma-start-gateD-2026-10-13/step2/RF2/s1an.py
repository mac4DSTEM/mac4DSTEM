import collections, statistics as st
from p2 import parse2
V={v:parse2("logs/S1_%s.log"%v) for v in ("head","a","b","ab")}
names=list(V["head"])
def stt(d):
    if d["status"]=="THREW": return "T"
    e=abs(float(d["dR"]))
    if d["status"]=="conic": return "C" if e<=0.01 else "C!"
    return "R" if e<0.001 else ("M" if e<=0.01 else "W")
groups=collections.defaultdict(list)
for n in names: groups[(V["head"][n]["tier"],V["head"][n].get("tier"))].append(n)
print("%-18s noise | HEAD  a  b  ab states per noise level (R<0.1%%, M 0.1-1%%, W>1%% profile; C conic<=1%%, C! conic>1%%, T threw)"%"group")
for (t,_),ns in sorted(groups.items()):
    line=[]
    for noise in ("0","0.01","0.03","0.1"):
        sel=[n for n in ns if abs(float(open('/dev/null').read() or 0)+float(n.split('-n')[1].split('-')[0])/100-float(noise))<1e-9]
        if not sel: continue
        c={v:collections.Counter(stt(V[v][n]) for n in sel) for v in V}
        line.append("n=%s%%: H%s a%s b%s ab%s"%(noise if noise=="0" else str(float(noise)*100).rstrip('0').rstrip('.'),dict(c["head"]),dict(c["a"]),dict(c["b"]),dict(c["ab"])))
    print(t); [print("    "+l) for l in line]
# b refusals of right fits and their conic error
print("\nb refusals where HEAD profile fit is within 0.1%: conic error")
rows=[]
for n in names:
    h,b=V["head"][n],V["b"][n]
    if h["status"]=="profile" and abs(float(h["dR"]))<0.001 and b["status"]!="profile":
        rows.append((V["head"][n]["tier"],n,float(h["sin"]),float(h["sout"]),float(b["dR"]),float(b["dba"]),float(b["dth"])))
for r in rows: print("  %-26s %-40s head sin/sout %.3f/%.3f | conic dR %+.4f dba %+.4f dth %.3f"%r)
if rows:
    print("  n=%d conic |dR| max %.4f med %.4f ; >1%%: %d ; |dba| max %.4f med %.4f"%(len(rows),max(abs(r[4]) for r in rows),st.median(abs(r[4]) for r in rows),sum(abs(r[4])>0.01 for r in rows),max(abs(r[5]) for r in rows),st.median(abs(r[5]) for r in rows)))
