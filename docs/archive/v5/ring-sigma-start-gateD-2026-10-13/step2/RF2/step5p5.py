import re, collections
P5="/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/P5"
def parse(v):
    out=collections.OrderedDict()
    for ln in open("%s/logs/%s.log"%(P5,v)):
        m=re.match(r"P5 (\S+) fn=(\S+) (.*)",ln.strip())
        if not m or m.group(2)!="fitBestAvailable": continue
        ann,_,rest=m.groups()
        d={}
        if rest.startswith("THREW"): d={"model":"THREW","err":rest}
        else:
            for kv in re.findall(r"(\w+)=(\S+)",rest): d[kv[0]]=kv[1]
        out[ann]=d
    return out
V={v:parse(v) for v in ["head","a","b","ab"]}
print("annulus | head model | a model | b model | ab model | |da| |db| |dtheta| |dcentre| (a vs head)")
nsame=0; worst=0
for ann in V["head"]:
    h,a,b,ab=[V[v][ann] for v in ["head","a","b","ab"]]
    same=h["model"]==a["model"]
    nsame+=same
    if h["model"]!="THREW" and a["model"]!="THREW":
        da=abs(float(a["a"])-float(h["a"])); db=abs(float(a["b"])-float(h["b"])); dt=abs(float(a["theta"])-float(h["theta"]))
        dc=((float(a["centerQX"])-float(h["centerQX"]))**2+(float(a["centerQY"])-float(h["centerQY"]))**2)**.5
        worst=max(worst,da,db)
        print("%-9s| %-8s| %-8s| %-8s| %-8s| %.1e %.1e %.1e %.1e"%(ann,h["model"],a["model"],b["model"],ab["model"],da,db,dt,dc))
    else: print("%-9s| %-8s| %-8s| %-8s| %-8s| (threw: %s)"%(ann,h["model"],a["model"],b["model"],ab["model"],h.get("err","")))
print("same model head vs a: %d/%d ; worst |da| or |db| = %.2e px"%(nsame,len(V["head"]),worst))
# sigma at bounds in head fits
print("\nHEAD profile fits: ring/central sigma and bounds (floor 0.25, ceiling = max(2, 2*outer))")
for ann,h in V["head"].items():
    if h["model"]=="profile":
        s=re.findall(r"(\w+)=(\S+)",open("%s/logs/head.log"%P5).read().split("P5 %s fn=fitBestAvailable"%ann)[1].split("\n")[0])
        dd=dict(s)
        print("  %-8s a=%.2f b=%.2f b/a=%.4f I1=%s sig0=%s sin=%s sout=%s"%(ann,float(h["a"]),float(h["b"]),float(h["b"])/float(h["a"]),dd.get("I1"),dd.get("centralSigma"),dd.get("innerSigma"),dd.get("outerSigma")))
for v in ["b","ab"]:
    print(v,{ann:d["model"] for ann,d in V[v].items()})
dbg=open("%s/dbg/err.log"%P5).read()
print("estimator nil on", dbg.count("halfMaxSigma=nil"), "of", dbg.count("DBG"), "(W1 never reached: conic stage threw)")
