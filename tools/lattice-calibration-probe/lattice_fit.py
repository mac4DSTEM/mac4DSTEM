"""Lattice-based Q + detector-ellipse calibration, feasibility probe.

docs/archive/v4/lattice-calibration-feasibility-2026-09-24.md. `diagnostic`:
it reads peak dumps written by tools/matrix-orientation-probe --dump-peaks
(the app's own detection and descan correction) and measures whether one 2x2
map A (px per inverse angstrom) from a declared zone's reciprocal lattice to
the detected peaks recovers Q and the ellipse. numpy only.

Model: p = A g. Q = 1/sqrt|det A|; axis ratio = s1/s2 from A's singular
values; the major-axis angle is that of A's first left singular vector, in
the detector's (x = column, y = row) frame, folded into [0, 180).

Usage:
  lattice_fit.py PEAKS.json [--truth truth.json --grain N] [--quadrants]
                 [--a 4.0495] [--zones 001,011,...] [--expect Q,RATIO,ANGLE]
"""
import argparse
import json
import math
import sys

import numpy as np

ZONES_DEFAULT = "001,011,111,112,012,013,122,114"


def fcc_zone_vectors(uvw, a, gmax=3.0):
    """In-zone fcc reciprocal vectors as 2D coordinates (inverse angstrom).

    The basis is e1 = the shortest in-zone g, e2 = n x e1, so the 2D lattice
    is right-handed about the beam; A absorbs any mirror (det < 0 allowed).
    """
    u = np.array(uvw, dtype=float)
    n = u / np.linalg.norm(u)
    hmax = int(math.ceil(gmax * a))
    gs = []
    rng = range(-hmax, hmax + 1)
    for h in rng:
        for k in rng:
            for l in rng:
                if h == k == l == 0 or h * uvw[0] + k * uvw[1] + l * uvw[2] != 0:
                    continue
                parities = {h % 2, k % 2, l % 2}
                if len(parities) != 1:          # fcc: all even or all odd
                    continue
                g = np.array([h, k, l], dtype=float) / a
                if np.linalg.norm(g) <= gmax:
                    gs.append(g)
    gs = np.array(gs)
    lengths = np.linalg.norm(gs, axis=1)
    e1 = gs[np.argmin(lengths)]
    e1 = e1 / np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    return np.stack([gs @ e1, gs @ e2], axis=1)


def load(path, truth_path=None, grain=None, quadrant=None):
    d = json.load(open(path))
    ox, oy = d["origin"]
    cols, rows = d["cols"], d["rows"]
    keep = np.ones(rows * cols, dtype=bool)
    if truth_path is not None:
        t = json.load(open(truth_path))
        gl = np.array(t["grain_label_map"])
        pm = np.array(t["precipitate_map"])
        sm = np.array(t["stripe_mask"])
        stride = d["stride"]
        sub = lambda m: m[::stride, ::stride][:rows, :cols].ravel()
        keep &= (sub(gl) == grain) & (sub(pm) == 0) & (sub(sm) == 0)
    if quadrant is not None:
        r, c = np.divmod(np.arange(rows * cols), cols)
        qr, qc = divmod(quadrant, 2)
        keep &= ((r >= rows // 2) == bool(qr)) & ((c >= cols // 2) == bool(qc))
    pts = [pk for i, plist in enumerate(d["peaks"]) if keep[i] for pk in plist]
    xy = np.array([[p[0] - ox, p[1] - oy] for p in pts])
    r = np.hypot(xy[:, 0], xy[:, 1])
    inner = 2 * d["probe_radius_px"]
    half = min(d["detector"]) / 2 - 2
    xy = xy[(r > inner)]
    return xy, int(keep.sum()), inner, half


def density_image(xy, half, bin_px=0.25, sigma_px=1.0):
    n = int(math.ceil(2 * half / bin_px))
    img, _, _ = np.histogram2d(xy[:, 1], xy[:, 0], bins=n, range=[[-half, half], [-half, half]])
    k = np.arange(-int(3 * sigma_px / bin_px), int(3 * sigma_px / bin_px) + 1) * bin_px
    ker = np.exp(-0.5 * (k / sigma_px) ** 2)
    ker /= ker.sum()
    img = np.apply_along_axis(lambda v: np.convolve(v, ker, mode="same"), 0, img)
    img = np.apply_along_axis(lambda v: np.convolve(v, ker, mode="same"), 1, img)
    return img, bin_px


def sample(img, bin_px, half, p):
    """Density at points p (N x 2, px); 0 outside."""
    n = img.shape[0]
    ix = ((p[..., 0] + half) / bin_px).astype(int)
    iy = ((p[..., 1] + half) / bin_px).astype(int)
    ok = (ix >= 0) & (ix < n) & (iy >= 0) & (iy < n)
    out = np.zeros(p.shape[:-1])
    out[ok] = img[iy[ok], ix[ok]]
    return out


def fit_zone(xy, g2, inner, half):
    # Coarse similarity: scale from the strongest ring against each of the
    # first six shells, rotation in 0.5 deg steps.
    r = np.hypot(xy[:, 0], xy[:, 1])
    hist, edges = np.histogram(r, bins=int(half / 0.25), range=(0, half))
    r_ring = 0.5 * (edges[np.argmax(hist)] + edges[np.argmax(hist) + 1])
    shells = np.unique(np.round(np.linalg.norm(g2, axis=1), 6))[:6]
    img, bin_px = density_image(xy, half)
    thetas = np.radians(np.arange(0, 360, 0.5))
    rot = np.stack([np.stack([np.cos(thetas), -np.sin(thetas)], -1),
                    np.stack([np.sin(thetas), np.cos(thetas)], -1)], -2)   # T x 2 x 2
    best = (-1, None)
    for shell in shells:
        s0 = r_ring / shell
        for s in s0 * (1 + np.linspace(-0.04, 0.04, 17)):
            p = s * np.einsum("tij,gj->tgi", rot, g2)                      # T x G x 2
            inside = (np.abs(p[..., 0]) < half - 1) & (np.abs(p[..., 1]) < half - 1) \
                & (np.hypot(p[..., 0], p[..., 1]) > inner)
            score = (sample(img, bin_px, half, p) * inside).sum(axis=1) / np.maximum(inside.sum(axis=1), 1)
            t = int(np.argmax(score))
            if score[t] > best[0]:
                best = (score[t], s * rot[t])
    A = best[1]
    # Refine: weighted least squares on cluster centroids, radius 2 -> 1 px.
    for rho in (2.0, 1.75, 1.5, 1.25, 1.0, 1.0, 1.0):
        p = g2 @ A.T
        inside = (np.abs(p[:, 0]) < half - 1) & (np.abs(p[:, 1]) < half - 1) \
            & (np.hypot(p[:, 0], p[:, 1]) > inner)
        G, C, W = [], [], []
        for gi, pi in zip(g2[inside], p[inside]):
            m = np.hypot(xy[:, 0] - pi[0], xy[:, 1] - pi[1]) <= rho
            if m.sum() >= max(20, 0.001 * len(xy)):
                G.append(gi); C.append(xy[m].mean(axis=0)); W.append(m.sum())
        if len(G) < 3:
            return None
        G, C, W = np.array(G), np.array(C), np.array(W, dtype=float)
        if np.linalg.matrix_rank(G) < 2:
            return None
        Wd = np.diag(W)
        A = np.linalg.solve(G.T @ Wd @ G, G.T @ Wd @ C).T
    resid = np.hypot(*(G @ A.T - C).T)
    rms = math.sqrt(float((W * resid ** 2).sum() / W.sum()))
    p = g2 @ A.T
    inside = (np.abs(p[:, 0]) < half - 1) & (np.abs(p[:, 1]) < half - 1)
    d2 = np.min((xy[:, None, 0] - p[None, inside, 0]) ** 2 + (xy[:, None, 1] - p[None, inside, 1]) ** 2, axis=1)
    explained = float((d2 <= 1.0).mean())
    U, sv, _ = np.linalg.svd(A)
    ratio = sv[0] / sv[1]
    angle = math.degrees(math.atan2(U[1, 0], U[0, 0])) % 180
    q = 1 / math.sqrt(abs(np.linalg.det(A)))
    return dict(Q=q, ratio=ratio, angle=angle, rms=rms, explained=explained, clusters=len(G))


def angle_diff(a, b):
    d = abs(a - b) % 180
    return min(d, 180 - d)


def report(label, xy, npos, inner, half, zones, a, expect):
    print(f"\n== {label}: {npos} positions, {len(xy)} peaks outside {inner:.1f} px ==")
    rows = []
    for z in zones:
        uvw = tuple(int(c) for c in z)
        fit = fit_zone(xy, fcc_zone_vectors(uvw, a), inner, half)
        if fit is None:
            print(f"  [{z}]  no fit (fewer than 3 non-collinear clusters)")
            continue
        rows.append((z, fit))
        print(f"  [{z}]  explained {100 * fit['explained']:5.1f} %  RMS {fit['rms']:.3f} px  "
              f"({fit['clusters']} clusters)  Q {fit['Q']:.6f}  ratio {fit['ratio']:.4f}  "
              f"major {fit['angle']:5.1f}°")
    if not rows:
        return
    top = max(f["explained"] for _, f in rows)
    near = [(z, f) for z, f in rows if f["explained"] >= top - 0.05]
    z, f = min(near, key=lambda zf: zf[1]["ratio"])
    print(f"  → proposed zone [{z}]: least distortion among {len(near)} zone(s) within 5 points of "
          f"the best explained ({100 * top:.1f} %)")
    if expect:
        q, ratio, angle = expect
        print(f"    vs truth: Q {100 * (f['Q'] / q - 1):+.3f} %, ratio {f['ratio'] - ratio:+.4f}, "
              f"angle {angle_diff(f['angle'], angle):.1f}° off" if ratio > 1.0001 else
              f"    vs truth: Q {100 * (f['Q'] / q - 1):+.3f} %, ratio {f['ratio'] - ratio:+.4f} (no planted angle)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("peaks")
    ap.add_argument("--truth")
    ap.add_argument("--grain", type=int, action="append")
    ap.add_argument("--quadrants", action="store_true")
    ap.add_argument("--a", type=float, default=4.0495)
    ap.add_argument("--zones", default=ZONES_DEFAULT)
    ap.add_argument("--expect", help="Q,RATIO,ANGLE truth, printed as deltas")
    args = ap.parse_args()
    zones = args.zones.split(",")
    expect = tuple(float(v) for v in args.expect.split(",")) if args.expect else None
    if args.truth:
        for grain in args.grain or [0]:
            xy, npos, inner, half = load(args.peaks, args.truth, grain)
            report(f"grain {grain}", xy, npos, inner, half, zones, args.a, expect)
    elif args.quadrants:
        for qd in range(4):
            xy, npos, inner, half = load(args.peaks, quadrant=qd)
            report(f"quadrant {qd}", xy, npos, inner, half, zones, args.a, expect)
    else:
        xy, npos, inner, half = load(args.peaks)
        report("all positions", xy, npos, inner, half, zones, args.a, expect)


if __name__ == "__main__":
    sys.exit(main())
