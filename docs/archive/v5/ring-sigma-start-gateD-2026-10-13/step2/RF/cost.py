#!/usr/bin/env python3
"""RF: cost ordering on clean plants. usage: cost.py <plants dir> <headlog> <alog> [tier-regex]
Reads fits (cx,cy,fa,fb,fth,I0,I1,s0,sin,sout,cbg) printed by rf2 binaries; recomputes the 11-parameter model's sum of squares on the
annulus pixels (circular annulus about the plant's guess, strict inequalities) with numpy; adds (T) truth geometry with sigma=3,
I0=0 and I1, c from linear LS; (S) scipy least_squares from the truth start and from each fit's own parameters."""
import json, sys, re, math
import numpy as np
from scipy.optimize import least_squares
d, headlog, alog = sys.argv[1], sys.argv[2], sys.argv[3]
tier = sys.argv[4] if len(sys.argv) > 4 else "clean"
namef = sys.argv[5] if len(sys.argv) > 5 else ".*"
def load(path):
    rows = {}
    for line in open(path):
        if not line.startswith("ROW|"): continue
        r = dict(kv.partition("=")[::2] for kv in line.rstrip("\n").split("|")[1:])
        rows[r["name"]] = r
    return rows
H, A = load(headlog), load(alog)
man = json.load(open(d + "/planted.json"))["cases"]
def model(p, x, y):
    I0, I1, s0, s1, s2, c, x0, y0, a, b, t = p
    st, ct = math.sin(t), math.cos(t); a2, b2 = a * a, b * b
    R = 0.5 * (a + b)
    A_ = (st * st / b2 + ct * ct / a2) * R * R; B_ = 2.0 * (b2 - a2) * st * ct / (a2 * b2) * R * R; C_ = (ct * ct / b2 + st * st / a2) * R * R
    dx, dy = x - x0, y - y0
    e2 = np.maximum(0.0, A_ * dx * dx + B_ * dx * dy + C_ * dy * dy)
    delta = np.sqrt(e2) - R
    sig = np.where(delta < 0, 2.0 * s1 * s1, 2.0 * s2 * s2)
    return I0 * np.exp(-e2 / (2.0 * s0 * s0)) + I1 * np.exp(-delta * delta / sig) + c
def fitp(r):
    return [float(r[k]) for k in ("I0", "I1", "s0", "sin", "sout", "cbg", "cx", "cy", "fa", "fb", "fth")] if "I0" in r else None
print("name | n | cost(head)  cost(a)  cost(truthLS)  cost(scipy-from-truth) cost(scipy-from-head) cost(scipy-from-a) | dR head,a | dth head,a | cerr head,a")
out = []
for c in man:
    if not re.fullmatch(tier, c["tier"]) or not re.search(namef, c["name"]): continue
    h, a = H.get(c["name"]), A.get(c["name"])
    if h is None or a is None: continue
    img = np.fromfile(d + "/" + c["file"], dtype="<f4").reshape(c["rows"], c["cols"]).astype(np.float64)
    rr, cc = np.mgrid[0:c["rows"], 0:c["cols"]].astype(np.float64)
    rad = np.hypot(rr - c["guess_row"], cc - c["guess_col"])
    sel = (rad > c["inner"]) & (rad < c["outer"]) & np.isfinite(img)
    x, y, v = rr[sel], cc[sel], img[sel]
    cost = lambda p: float(np.sum((model(p, x, y) - v) ** 2))
    th = c["theta"] if c["theta"] is not None else 0.0
    tp = [0.0, 1.0, 10.0, c["sigma"], c["sigma"], 0.0, c["r0"], c["c0"], c["a"], c["b"], th]
    ring = model([0, 1, 10, c["sigma"], c["sigma"], 0, c["r0"], c["c0"], c["a"], c["b"], th], x, y)
    M = np.stack([ring, np.ones_like(ring)], 1); sol = np.linalg.lstsq(M, v, rcond=None)[0]
    tLS = [0.0, sol[0], 10.0, c["sigma"], c["sigma"], sol[1], c["r0"], c["c0"], c["a"], c["b"], th]
    ph, pa = fitp(h), fitp(a)
    def opt(p0):
        lo = [0, 0, .25, .25, .25, -np.inf, -np.inf, -np.inf, 1, 1, -np.inf]; hi = [np.inf] * 11
        p0 = np.clip(p0, [l + 1e-9 for l in lo], hi)
        res = least_squares(lambda p: model(p, x, y) - v, p0, bounds=(lo, hi), x_scale="jac", xtol=1e-12, ftol=1e-12, gtol=1e-12, max_nfev=3000)
        return float(np.sum(res.fun ** 2)), res.x
    cT, pT = opt(np.array(tLS))
    cH = opt(np.array(ph))[0] if ph else float("nan")
    cA = opt(np.array(pa))[0] if pa else float("nan")
    ch, ca = (cost(ph) if ph else float("nan")), (cost(pa) if pa else float("nan"))
    nm = c["name"]
    fmt = lambda r, k: ("%.5f" % float(r[k])) if k in r else "NA"
    print(f"{nm[:42]:42} {len(v):6d} | {ch:10.4g} {ca:10.4g} {cost(tLS):10.4g} | scipy: truth-start {cT:10.4g} head-start {cH:10.4g} a-start {cA:10.4g} | dR {fmt(h,'dR')} {fmt(a,'dR')} | dth {fmt(h,'dth')} {fmt(a,'dth')} | cerr {fmt(h,'cerr')} {fmt(a,'cerr')} | st {h['status']}/{a['status']}")
