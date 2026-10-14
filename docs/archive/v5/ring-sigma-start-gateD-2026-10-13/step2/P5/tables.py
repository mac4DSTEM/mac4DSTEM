# Lane P5: markdown tables generated from the logs (no hand transcription).
import math, re, sys
sys.path.insert(0, "/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/P5")
L = "/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/P5/logs/"
KV = re.compile(r'(\w+)=(\S+)')
def rows(v):
    seed, best = {}, {}
    for line in open(L + v + ".log"):
        if not (line.startswith("P5 A") or line.startswith("P5 W")): continue
        tag = line.split(" ")[1]; fn = re.search(r'fn=(\S+)', line).group(1)
        d = {"raw": line.rstrip("\n")}
        if " THREW " in line:
            d["threw"] = line.split(" THREW ", 1)[1].strip()
        else:
            head = line.split(" profile:")[0]
            d.update({k: x for k, x in KV.findall(head)})
            if " profile:" in line: d["profile"] = dict(KV.findall(line.split(" profile:", 1)[1]))
        (seed if fn == "fit1D" else best)[tag] = d
    return seed, best
def f(x): return float(x)
S, H = rows("head"); _, A = rows("a"); _, B = rows("b"); _, AB = rows("ab")
guess = (28.47, 34.43)
out = []
out.append("| annulus | fit1D seed: model, residual, b/a | head fitBestAvailable: model | a (px) | b (px) | b/a | theta (rad) | centre row, col (px) | dist from guess (px) | normalizedResidual | occupied bins |")
out.append("|---|---|---|---|---|---|---|---|---|---|---|")
for t in H:
    s = S[t]; h = H[t]
    if "threw" in h:
        out.append("| %s | %s, resid %s, refused | THREW %s | - | - | - | - | - | - | - | - |" % (t, s.get("model", "threw"), s.get("normalizedResidual", "-"), h["threw"]))
        continue
    dist = math.hypot(f(h["centerQX"]) - guess[0], f(h["centerQY"]) - guess[1])
    out.append("| %s | %s, %s, %.4f | %s | %.6f | %.6f | %.4f | %.5f | (%.4f, %.4f) | %.2f | %s | %s |" % (
        t, s["model"], s["normalizedResidual"], f(s["b"]) / f(s["a"]), h["model"], f(h["a"]), f(h["b"]), f(h["b"]) / f(h["a"]),
        f(h["theta"]), f(h["centerQX"]), f(h["centerQY"]), dist, h["normalizedResidual"], h["occupiedAngularBins"]))
out.append("")
out.append("Head profile parameters (fitBestAvailable, default arguments):")
out.append("")
out.append("| annulus | I0 | I1 | centralSigma | innerSigma | outerSigma | background | flags |")
out.append("|---|---|---|---|---|---|---|---|")
for t in H:
    h = H[t]
    if "profile" not in h: continue
    p = h["profile"]; flags = []
    if abs(f(p["I0"]) - 738549.375) < 1e-3: flags.append("I0 at intensityLimit 5 x global max")
    if f(p["centralSigma"]) <= 0.2500001: flags.append("centralSigma at 0.25 floor")
    if f(p["innerSigma"]) <= 0.2500001: flags.append("innerSigma at 0.25 floor")
    if f(p["outerSigma"]) <= 0.2500001: flags.append("outerSigma at 0.25 floor")
    if f(p["I1"]) == 0: flags.append("I1 = 0")
    if f(p["innerSigma"]) >= 2 * float(t.split(":")[1].split("-")[1]) - 1e-6: flags.append("innerSigma at 2 x outer")
    if f(p["outerSigma"]) >= 2 * float(t.split(":")[1].split("-")[1]) - 1e-6: flags.append("outerSigma at 2 x outer")
    out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (t, p["I0"], p["I1"], p["centralSigma"], p["innerSigma"], p["outerSigma"], p["background"], "; ".join(flags) or "none"))
out.append("")
out.append("Differences from head (fitBestAvailable, default arguments; theta difference mod pi, meaningful here because every head b/a differs from 1 by more than 1e-3):")
out.append("")
out.append("| annulus | variant | model | model same | abs da (px) | abs db (px) | centre distance (px) | abs dtheta (rad) |")
out.append("|---|---|---|---|---|---|---|---|")
def ang(x, y):
    r = abs(x - y) % math.pi
    return min(r, math.pi - r)
for name, V in [("a", A), ("b", B), ("ab", AB)]:
    for t in H:
        h, x = H[t], V[t]
        if "threw" in h:
            out.append("| %s | %s | refused (head and %s) | %s | - | - | - | - |" % (t, name, name, "yes" if "threw" in x and x["threw"] == h["threw"] else "NO"))
            continue
        if "threw" in x:
            out.append("| %s | %s | THREW %s | NO | - | - | - | - |" % (t, name, x["threw"])); continue
        same = h["model"] == x["model"]
        dc = math.hypot(f(x["centerQX"]) - f(h["centerQX"]), f(x["centerQY"]) - f(h["centerQY"]))
        out.append("| %s | %s | %s -> %s | %s | %.3g | %.3g | %.3g | %.3g |" % (
            t, name, h["model"], x["model"], "yes" if same else "NO",
            abs(f(x["a"]) - f(h["a"])), abs(f(x["b"]) - f(h["b"])), dc, ang(f(x["theta"]), f(h["theta"]))))
print("\n".join(out))
