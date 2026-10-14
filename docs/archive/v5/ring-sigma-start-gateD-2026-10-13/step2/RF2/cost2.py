#!/usr/bin/env python3
"""RF2 own cost model: the 11-parameter profile model of fitAmorphousRing (HEAD file, predictions()), same samples
(pixels with inner < hypot(row-guess_row, col-guess_col) < outer, finite), SSE and normalized residual sqrt(SSE/N)/dynamicRange.
Params p = [I0,I1,s0,s1,s2,c,x0,y0,a,b,theta] (x = row, y = col)."""
import json, numpy as np
from scipy.optimize import least_squares
RFD = "/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF/data"
_man = {}
def manifest(S):
    if S not in _man:
        m = json.load(open("%s/plants%s/planted.json" % (RFD, S)))
        _man[S] = {c["name"]: c for c in m["cases"]}
    return _man[S]
class Plant:
    def __init__(self, S, name):
        c = manifest(S)[name]; self.c = c; self.S = S; self.name = name
        px = np.fromfile("%s/plants%s/%s" % (RFD, S, c["file"]), dtype="<f4").reshape(c["rows"], c["cols"])
        rr, cc = np.mgrid[0:c["rows"], 0:c["cols"]]
        r = np.hypot(rr - c["guess_row"], cc - c["guess_col"])
        m = (r > c["inner"]) & (r < c["outer"]) & np.isfinite(px)
        self.x = rr[m].astype(float); self.y = cc[m].astype(float); self.v = px[m].astype(float)
        self.N = self.v.size
        self.dyn = self.v.max() - self.v.min(); self.vmin = self.v.min(); self.vmax = self.v.max()
        self.gmax = float(np.nanmax(px)); ringw = c["outer"] - c["inner"]
        self.inner = c["inner"]; self.outer = c["outer"]; self.ringw = ringw
        self.sigmaLimit = max(2, c["outer"] * 2); self.ilim = 5 * max(1, abs(self.gmax), self.dyn)
        self.bgLo = self.vmin - 2 * self.dyn; self.bgHi = self.vmax + 2 * self.dyn
        self.truth = np.array([c["r0"], c["c0"], c["a"], c["b"], (c["theta"] or 0.0)])
    def predict(self, p, idx=None):
        I0, I1, s0, s1, s2, cb, x0, y0, a, b, th = p
        st, ct = np.sin(th), np.cos(th); a2, b2 = a * a, b * b
        A = st * st / b2 + ct * ct / a2; B = 2 * (b2 - a2) * st * ct / (a2 * b2); C = ct * ct / b2 + st * st / a2
        rad = (a + b) / 2; A *= rad * rad; B *= rad * rad; C *= rad * rad
        dx = self.x - x0; dy = self.y - y0
        e2 = np.maximum(0, A * dx * dx + B * dx * dy + C * dy * dy)
        delta = np.sqrt(e2) - rad
        rs = np.where(delta < 0, 2 * s1 * s1, 2 * s2 * s2)
        return I0 * np.exp(-e2 / (2 * s0 * s0)) + I1 * np.exp(-(delta * delta) / rs) + cb
    def sse(self, p): d = self.predict(p) - self.v; return float(d @ d)
    def nres(self, p): return float(np.sqrt(self.sse(p) / self.N) / self.dyn)
    def fit_rest(self, geom, start, full=False):
        """optimise [I0,I1,s0,s1,s2,c] at fixed geometry geom=(x0,y0,a,b,theta); or all 11 if full (start is length 11)."""
        lo6 = [0, 0, 0.25, 0.25, 0.25, self.bgLo]; hi6 = [self.ilim, self.ilim, self.sigmaLimit, self.sigmaLimit, self.sigmaLimit, self.bgHi]
        if not full:
            f = lambda q: self.predict(np.concatenate([q, geom])) - self.v
            r = least_squares(f, np.clip(start[:6], lo6, hi6), bounds=(lo6, hi6), x_scale=np.array([self.dyn] * 2 + [10, 5, 5] + [self.dyn]), max_nfev=400)
            return np.concatenate([r.x, geom]), float(2 * r.cost)
        lo = lo6 + [0, 0, 1, 1, -10]; hi = hi6 + [1e4, 1e4, 1e4, 1e4, 10]
        lo[6] = start[6] - 20; hi[6] = start[6] + 20; lo[7] = start[7] - 20; hi[7] = start[7] + 20
        lo[8] = lo[9] = max(1, 0.5 * self.inner); hi[8] = hi[9] = max(0.5 * self.inner + 1, 1.5 * self.outer)
        xs = np.array([self.dyn] * 2 + [10, 5, 5] + [self.dyn] + [1, 1, start[8], start[9], 1])
        f = lambda q: self.predict(q) - self.v
        r = least_squares(f, np.clip(start, lo, hi), bounds=(lo, hi), x_scale=xs, max_nfev=400)
        return r.x, float(2 * r.cost)
def row_params(d):
    f = lambda k: float(d[k])
    return np.array([f("I0"), f("I1"), f("s0"), f("sin"), f("sout"), f("cbg"), f("cx"), f("cy"), f("fa"), f("fb"), f("fth")])
