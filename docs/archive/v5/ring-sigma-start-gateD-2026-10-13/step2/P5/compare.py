# Lane P5 comparison: default-argument calls only (fitBestAvailable) for the verdict; fit1D printed for reference.
import math, re, sys
L = "/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/P5/logs/"
KV = re.compile(r'(\w+)=(\S+)')
def load(v):
    out = {}
    for line in open(L + v + ".log"):
        if not line.startswith("P5 A") and not line.startswith("P5 W"): continue
        parts = line.split(" ", 3)
        tag = parts[1]; fn = parts[2].split("=", 1)[1]
        if fn != "fitBestAvailable": continue  # verdict = default-argument calls only
        rest = line.rstrip("\n")
        if " THREW " in rest:
            out[tag] = {"threw": rest.split(" THREW ", 1)[1]}
            continue
        d = {k: v2 for k, v2 in KV.findall(rest.split(" profile:")[0])}
        if " profile:" in rest:
            d["profile"] = rest.split(" profile:", 1)[1]
        m = re.search(r'fallbackReason=(.*)$', rest)
        if m: d["fallback"] = m.group(1)
        out[tag] = d
    return out
def ang(x, y):
    r = abs(x - y) % math.pi
    return min(r, math.pi - r)
H = load("head")
tags = list(H.keys())
print("%-9s %-8s %-8s %-8s %-8s %-8s %-6s %-6s" % ("annulus", "variant", "model", "|da|px", "|db|px", "|dc|px", "|dth|", "b/a"))
for v in ["a", "b", "ab"]:
    V = load(v)
    for t in tags:
        h, x = H[t], V.get(t)
        if "threw" in h or x is None or "threw" in x:
            mh = "threw" if "threw" in h else h["model"]
            mx = "threw" if (x is None or "threw" in x) else x["model"]
            same = (mh == mx) and ("threw" not in h and "threw" not in x or h.get("threw") == (x or {}).get("threw"))
            print("%-9s %-8s head=%s variant=%s same=%s" % (t, v, mh, mx, same))
            continue
        fa = float(h["a"]); fb = float(h["b"]); th = float(h["theta"]); cx = float(h["centerQX"]); cy = float(h["centerQY"])
        ga = float(x["a"]); gb = float(x["b"]); gt = float(x["theta"]); gx = float(x["centerQX"]); gy = float(x["centerQY"])
        same = h["model"] == x["model"]
        da, db = abs(ga - fa), abs(gb - fb)
        dc = math.hypot(gx - cx, gy - cy)
        dth = ang(gt, th)
        ba = fb / fa
        print("%-9s %-8s %-8s %-8.3g %-8.3g %-8.3g %-6.3g %-6.4f model_head=%s model_%s=%s" % (
            t, v, "same" if same else "DIFF", da, db, dc, dth, ba, "head", v, x["model"]))
