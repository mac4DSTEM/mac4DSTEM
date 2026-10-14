#!/usr/bin/env python3
"""RF refuter generators (own code): Poisson+smooth background (P), narrow rings (N), estimator traps (T).
usage: gen_extra.py <P|N|T> <out-dir>      manifest planted.json in the same field names rf.swift reads.
Geometry as plants_a.py: major axis along (cos t, sin t) in (row, col); R=(a+b)/2; a/b = 1+eps; guess = centre + (1.3,-0.9)."""
import json, math, os, sys
import numpy as np
THETAS = [0.0, 20.0, 45.0, 67.5, 90.0, 112.5, 135.0, 160.0, 179.0]
GUESS = (1.3, -0.9)
def axes(R, eps):
    b = 2.0 * R / (2.0 + eps); return b * (1.0 + eps), b
def centre(Hh, W, k):
    return Hh / 2.0 + 0.31 + 5.0 * math.sin(1.7 * k + 0.4), W / 2.0 - 0.27 + 5.0 * math.cos(2.3 * k + 1.1)
def grids(Hh, W, r0, c0, a, b, theta, ss=1):
    # sub-pixel supersampling ss x ss (pixel-integrated), returns rho, r (shape Hh,W) averaged later by the caller
    offs = (np.arange(ss) + 0.5) / ss - 0.5
    return offs
def ringmap(Hh, W, r0, c0, a, b, theta, prof, ss=1):
    R = 0.5 * (a + b)
    st, ct = math.sin(theta), math.cos(theta)
    acc = np.zeros((Hh, W))
    offs = (np.arange(ss) + 0.5) / ss - 0.5
    rr, cc = np.mgrid[0:Hh, 0:W].astype(np.float64)
    for oy in offs:
        for ox in offs:
            dr, dc = rr + oy - r0, cc + ox - c0
            u, v = dr * ct + dc * st, -dr * st + dc * ct
            rho = np.sqrt((u / a) ** 2 + (v / b) ** 2)
            acc += prof(rho, np.hypot(dr, dc), R)
    return acc / (ss * ss)
def gauss(s):
    return lambda rho, r, R: np.exp(-(((rho - 1.0) * R) ** 2) / (2 * s * s))
def with_neighbours(base, s, neigh):
    def f(rho, r, R):
        out = base(rho, r, R)
        for fac, amp in neigh:
            out = out + amp * np.exp(-(((rho - fac) * R) ** 2) / (2 * s * s))
        return out
    return f
def bgmap(kind, amp, Hh, W, r0, c0, R):
    rr, cc = np.mgrid[0:Hh, 0:W].astype(np.float64)
    r = np.maximum(np.hypot(rr - r0, cc - c0), 1.0)
    if kind == "none": return np.zeros((Hh, W))
    if kind == "const": return np.full((Hh, W), amp)
    if kind == "exp": return amp * np.exp(-(r - R) / 60.0)         # central-beam tail, amp at the ring
    if kind == "r2": return amp * (R / r) ** 2
    if kind == "r3": return amp * (R / r) ** 3
    if kind == "exp25": return amp * np.exp(-(r - R) / 25.0)
    if kind == "tilt": return amp * (cc / W) + 0.0 * rr             # linear gradient across the pattern, 0..amp
    raise ValueError(kind)
class Gen:
    def __init__(self, out, seed0):
        self.out, self.seed0, self.k, self.cases = out, seed0, 0, []
        os.makedirs(out, exist_ok=True)
    def add(self, tier, tag, Hh, W, R, eps, theta_deg, *, sigma=3.0, prof=None, gap=0.0, margin=20.0, m_in=None, m_out=None,
            noise=0.0, poisson=None, bg=("none", 0.0), ss=1):
        k = self.k; self.k += 1
        a, b = axes(R, eps); theta = None if eps == 0 else math.radians(theta_deg)
        r0, c0 = centre(Hh, W, k)
        pr = prof if prof is not None else gauss(sigma)
        ring = ringmap(Hh, W, r0, c0, a, b, theta or 0.0, pr, ss)
        rng = np.random.default_rng(self.seed0 + k)
        bgm = bgmap(bg[0], bg[1], Hh, W, r0, c0, R)
        if poisson is not None:                    # (ring amplitude above background in counts, base background counts)
            amp, base = poisson
            img = rng.poisson(amp * ring + base + bgm).astype(np.float64)
        else:
            img = ring + bgm
            if noise > 0: img = img + rng.normal(0.0, noise, img.shape)
        if gap > 0:
            rr, cc = np.mgrid[0:Hh, 0:W].astype(np.float64)
            ang = np.degrees(np.arctan2(cc - c0, rr - r0)) % 360.0
            img[((ang - (47.0 * k) % 360.0) % 360.0) < gap] = 0.0
        mi = margin if m_in is None else m_in; mo = margin if m_out is None else m_out
        name = "%s-%s-%03d" % (tier, tag, k)
        img.astype("<f4").tofile(os.path.join(self.out, name + ".in.f32"))
        self.cases.append(dict(name=name, file=name + ".in.f32", tier=tier, rows=Hh, cols=W, r0=r0, c0=c0, R=float(R), a=a, b=b,
                               theta=theta, eps=eps, noise=float(noise), gap_deg=float(gap), sigma=float(sigma),
                               inner=b - mi, outer=a + mo, guess_row=r0 + GUESS[0], guess_col=c0 + GUESS[1]))
    def done(self):
        json.dump({"cases": self.cases}, open(os.path.join(self.out, "planted.json"), "w"), indent=1)
        tiers = {}
        for c in self.cases: tiers[c["tier"]] = tiers.get(c["tier"], 0) + 1
        print("%d cases: %s" % (len(self.cases), tiers))
def theta_for(i): return THETAS[i % len(THETAS)]
def gen_P(out):
    g = Gen(out, 9_100_000); i = 0
    for rep in (1, 2):
        for R in (80, 140, 200):
            for eps in (0.01, 0.03):
                for gap in (0.0, 60.0):
                    for amp in (10, 20, 50, 200):
                        for bg in (("none", 0.0), ("const", 3.0), ("exp", 20.0), ("r2", 8.0), ("tilt", 8.0)):
                            tier = "P-a%d" % amp
                            g.add(tier, "R%d-e%g-g%d-%s%g" % (R, eps * 100, gap, bg[0], bg[1]), 512, 512, R, eps, theta_for(i),
                                  gap=gap, poisson=(amp, 2.0), bg=bg)
                            i += 1
    g.done()
def gen_N(out):
    g = Gen(out, 9_200_000); i = 0
    for R in (60, 120):
        for eps in (0.01, 0.03):
            for margin in (20.0, 8.0):
                for s in (0.25, 0.3, 0.35, 0.4, 0.5, 0.7, 1.0):
                    size = 256 if R == 60 else 512
                    for lab, kw in (("clean", {}), ("g1", dict(noise=0.01)), ("g3", dict(noise=0.03)),
                                    ("ss4", dict(ss=4)), ("pois", dict(poisson=(200, 2.0)))):
                        g.add("N-" + lab, "s%g-R%d-e%g-m%g" % (s, R, eps * 100, margin), size, size, R, eps, theta_for(i),
                              sigma=s, margin=margin, **kw)
                        i += 1
    g.done()
def gen_T(out):
    g = Gen(out, 9_300_000); i = 0
    R = 120
    def go(tier, tag, **kw):
        nonlocal i
        for eps in (0.01, 0.03):
            for noise in (0.03, 0.10):
                for th in (20.0, 112.5):
                    g.add(tier, "%s-e%g-n%g-t%g" % (tag, eps * 100, noise * 100, th), 512, 512, R, eps, th, noise=noise, **kw); i += 1
    # neighbour rings inside the annulus (fraction of R, amplitude relative to the main ring's 1)
    for fac, amp in ((1.155, 0.4), (1.155, 0.8), (1.155, 1.5), (1.10, 0.8), (1.07, 0.8), (0.87, 0.5), (0.87, 1.0), (0.90, 1.5), (0.87, 0.5, 1.155, 0.5)[:2]):
        go("T-neigh", "f%g-A%g" % (fac, amp), prof=with_neighbours(gauss(3.0), 3.0, [(fac, amp)]))
    go("T-neigh2", "both-0.5", prof=with_neighbours(gauss(3.0), 3.0, [(0.87, 0.5), (1.155, 0.5)]))
    # strong backgrounds / slopes
    for bg in (("r2", 1.0), ("r2", 2.0), ("r3", 1.0), ("r3", 2.0), ("exp25", 2.0), ("tilt", 1.0), ("tilt", 2.0), ("const", 1.0)):
        go("T-slope", "%s%g" % bg, bg=bg)
    for gap in (60.0, 90.0):
        go("T-gap", "g%d" % gap, gap=gap)
    for s in (6.0, 8.0, 10.0, 12.0, 14.0):
        go("T-wide", "s%g" % s, sigma=s)
    # ring near the annulus edge: (m_in, m_out) = distance from the ring (b, a) to the inner / outer edge
    for mi, mo in ((3, 37), (6, 34), (37, 3), (34, 6), (10, 10), (6, 6), (14, 14)):
        go("T-edge", "mi%d-mo%d" % (mi, mo), m_in=float(mi), m_out=float(mo))
    g.done()
if __name__ == "__main__":
    {"P": gen_P, "N": gen_N, "T": gen_T}[sys.argv[1]](sys.argv[2])
