"""Independent refuter for W4 (v3 lattice-calibration multi-start), 2026-09-25.

Part 3 of docs/archive/v4/lattice-calibration-feasibility-2026-09-24.md cites
its explained-fraction and OCCUPANCY numbers. Usage: occupancy_check.py DIR,
where DIR holds D1.json..D3.json (matrix-orientation-probe --dump-peaks) and
D1/..D3/truth.json (make_demo.py --distort). `diagnostic`, like lattice_fit.py.

Written from scratch against the physics description in
docs/archive/v4/lattice-calibration-feasibility-2026-09-24.md and the task
brief. Does NOT import tools/lattice-calibration-probe/lattice_fit.py.
numpy only.
"""
import json
import math
import sys

import numpy as np

A_LATTICE = 4.0495  # Al fcc, angstrom


def zone_reflections(uvw, a, gmax=3.0):
    """fcc-allowed (all-even or all-odd hkl) reflections in the zone
    perpendicular to uvw, as 2D coords (1/Angstrom) in a right-handed
    (e1, n x e1) in-zone basis, e1 = shortest g."""
    u = np.array(uvw, dtype=float)
    n = u / np.linalg.norm(u)
    hmax = int(math.ceil(gmax * a)) + 1
    hs = np.arange(-hmax, hmax + 1)
    H, K, L = np.meshgrid(hs, hs, hs, indexing="ij")
    H = H.ravel(); K = K.ravel(); L = L.ravel()
    zone_eq = H * uvw[0] + K * uvw[1] + L * uvw[2]
    nonzero = ~((H == 0) & (K == 0) & (L == 0))
    par = ((H % 2 == K % 2) & (K % 2 == L % 2))
    keep = (zone_eq == 0) & nonzero & par
    hkl = np.stack([H[keep], K[keep], L[keep]], axis=1).astype(float)
    g = hkl / a
    glen = np.linalg.norm(g, axis=1)
    keep2 = glen <= gmax
    g = g[keep2]; glen = glen[keep2]
    e1 = g[np.argmin(glen)]
    e1 = e1 / np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    return np.stack([g @ e1, g @ e2], axis=1)


def load_peaks(peaks_json, truth_json, grain, stripe_ok=False):
    d = json.load(open(peaks_json))
    ox, oy = d["origin"]
    cols, rows, stride = d["cols"], d["rows"], d["stride"]
    t = json.load(open(truth_json))
    gl = np.array(t["grain_label_map"])
    pm = np.array(t["precipitate_map"])
    sm = np.array(t["stripe_mask"])
    sub = lambda m: m[::stride, ::stride][:rows, :cols].ravel()
    keep = (sub(gl) == grain) & (sub(pm) == 0)
    if not stripe_ok:
        keep &= (sub(sm) == 0)
    pts = []
    for i, plist in enumerate(d["peaks"]):
        if keep[i]:
            pts.extend(plist)
    xy = np.array([[p[0] - ox, p[1] - oy] for p in pts])
    r = np.hypot(xy[:, 0], xy[:, 1])
    inner = 2.0 * d["probe_radius_px"]
    half = min(d["detector"]) / 2.0 - 2.0
    xy = xy[r > inner]
    return xy, int(keep.sum()), inner, half


def density_grid(xy, half, bin_px=0.2, sigma_px=0.8):
    n = int(math.ceil(2 * half / bin_px))
    H, xe, ye = np.histogram2d(xy[:, 0], xy[:, 1], bins=n, range=[[-half, half], [-half, half]])
    k = np.arange(-int(3 * sigma_px / bin_px), int(3 * sigma_px / bin_px) + 1)
    ker = np.exp(-0.5 * (k * bin_px / sigma_px) ** 2)
    ker /= ker.sum()
    H = np.apply_along_axis(lambda v: np.convolve(v, ker, mode="same"), 0, H)
    H = np.apply_along_axis(lambda v: np.convolve(v, ker, mode="same"), 1, H)
    return H, bin_px


def sample_grid(img, bin_px, half, pts):
    ix = ((pts[..., 0] + half) / bin_px).astype(int)
    iy = ((pts[..., 1] + half) / bin_px).astype(int)
    n = img.shape[0]
    ok = (ix >= 0) & (ix < n) & (iy >= 0) & (iy < n)
    out = np.zeros(pts.shape[:-1])
    out[ok] = img[ix[ok], iy[ok]]
    return out


def best_rotation(xy, g2, q_guess, inner, half):
    """Independent coarse search: fix scale s = 1/q_guess, grid-search
    rotation to maximize density-weighted overlap with predicted spots."""
    s = 1.0 / q_guess
    img, bpx = density_grid(xy, half)
    thetas = np.radians(np.arange(0, 360, 0.25))
    cs, sn = np.cos(thetas), np.sin(thetas)
    # rotate g2 by theta for every theta: T x G x 2
    gx = g2[:, 0]; gy = g2[:, 1]
    px = s * (cs[:, None] * gx[None, :] - sn[:, None] * gy[None, :])
    py = s * (sn[:, None] * gx[None, :] + cs[:, None] * gy[None, :])
    rad = np.hypot(px, py)
    inside = (np.abs(px) < half - 1) & (np.abs(py) < half - 1) & (rad > inner)
    pts = np.stack([px, py], axis=-1)
    dens = sample_grid(img, bpx, half, pts)
    score = (dens * inside).sum(axis=1) / np.maximum(inside.sum(axis=1), 1)
    t = int(np.argmax(score))
    return thetas[t]


def refine(A0, xy, g2, inner, half):
    """Own iterative weighted-LSQ refinement. The capture radius starts
    proportional to the predicted spot's distance from the origin (so it
    can bridge the several-px offset a planted ellipse causes at large
    radius before the anisotropic scale is known) and then shrinks to a
    fixed sub-pixel radius, per the method description in the feasibility
    doc (coarse->tight capture schedule)."""
    A = A0.copy()
    G = C = W = None
    # (fraction of |p|, floor px) for the proportional stages, then fixed px.
    stages = [(0.12, 3.0), (0.12, 3.0), (0.08, 2.0), (0.06, 1.5), (0.06, 1.5),
              1.25, 1.0, 1.0, 1.0]
    for stage in stages:
        p = g2 @ A.T
        rad = np.hypot(p[:, 0], p[:, 1])
        inside = (np.abs(p[:, 0]) < half - 1) & (np.abs(p[:, 1]) < half - 1) & (rad > inner)
        if isinstance(stage, tuple):
            frac, floor = stage
            rhos = np.maximum(floor, frac * rad)
        else:
            rhos = np.full_like(rad, float(stage))
        Gl, Cl, Wl = [], [], []
        for gi, pi, rho in zip(g2[inside], p[inside], rhos[inside]):
            d = np.hypot(xy[:, 0] - pi[0], xy[:, 1] - pi[1])
            m = d <= rho
            if m.sum() >= max(20, int(0.001 * len(xy))):
                Gl.append(gi); Cl.append(xy[m].mean(axis=0)); Wl.append(m.sum())
        if len(Gl) < 3:
            return None
        G = np.array(Gl); C = np.array(Cl); W = np.array(Wl, dtype=float)
        if np.linalg.matrix_rank(G) < 2:
            return None
        Wd = np.diag(W)
        A = np.linalg.solve(G.T @ Wd @ G, G.T @ Wd @ C).T
    resid = np.hypot(*(G @ A.T - C).T)
    rms = math.sqrt(float((W * resid ** 2).sum() / W.sum()))
    return A, len(G), rms


def score_candidate(A, xy, g2, inner, half):
    """Independent explained-fraction + occupancy computation (spec, not
    lattice_fit.py's code path)."""
    p = g2 @ A.T
    rad = np.hypot(p[:, 0], p[:, 1])
    inside = (np.abs(p[:, 0]) < half - 1) & (np.abs(p[:, 1]) < half - 1) & (rad > inner)
    spots = p[inside]
    if len(spots) == 0:
        return dict(explained=0.0, occupied=0, n_spots=0, occupancy=0.0)
    # explained: each peak within 1.0 px of ANY predicted spot
    d2 = ((xy[:, None, 0] - spots[None, :, 0]) ** 2 + (xy[:, None, 1] - spots[None, :, 1]) ** 2)
    near = d2 <= 1.0 ** 2
    explained = float(near.any(axis=1).mean())
    counts = near.sum(axis=0)  # peaks within 1px of each predicted spot
    occ_mask = counts >= 20
    occupancy = float(occ_mask.mean())
    U, sv, _ = np.linalg.svd(A)
    ratio = sv[0] / sv[1]
    ang = math.degrees(math.atan2(U[1, 0], U[0, 0])) % 180
    q = 1.0 / math.sqrt(abs(np.linalg.det(A)))
    return dict(explained=explained, n_spots=int(inside.sum()), occupied=int(occ_mask.sum()),
                occupancy=occupancy, Q=q, ratio=ratio, angle=ang, n_peaks=len(xy),
                n_explained=int(near.any(axis=1).sum()))


def fit_and_score(xy, g2, q_guess, inner, half, label):
    theta = best_rotation(xy, g2, q_guess, inner, half)
    s = 1.0 / q_guess
    A0 = s * np.array([[math.cos(theta), -math.sin(theta)], [math.sin(theta), math.cos(theta)]])
    out = refine(A0, xy, g2, inner, half)
    if out is None:
        print(f"  {label}: NO FIT from independent refinement")
        return None
    A, nclust, rms = out
    sc = score_candidate(A, xy, g2, inner, half)
    print(f"  {label}: Q={sc['Q']:.6f} ratio={sc['ratio']:.4f} angle={sc['angle']:.1f} "
          f"clusters={nclust} rms={rms:.4f}px explained={100*sc['explained']:.4f}% "
          f"({sc['n_explained']}/{sc['n_peaks']} peaks)  spots_in_detector={sc['n_spots']} "
          f"occupied(>=20)={sc['occupied']} occupancy={100*sc['occupancy']:.4f}%")
    return sc


def run_grain(fixture_dir, peaks_json, grain, uvw, q_guesses, label):
    xy, npos, inner, half = load_peaks(peaks_json, f"{fixture_dir}/truth.json", grain)
    print(f"\n== {label}: grain {grain} zone {uvw}, {npos} positions, {len(xy)} peaks outside {inner:.2f}px, half={half:.1f} ==")
    g2 = zone_reflections(uvw, A_LATTICE)
    print(f"     zone has {len(g2)} allowed reflections up to gmax=3.0/A")
    results = {}
    for qg in q_guesses:
        results[qg] = fit_and_score(xy, g2, qg, inner, half, f"Q~{qg:.6f}")
    return results


if __name__ == "__main__":
    S = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: occupancy_check.py DUMP_DIR")

    print("### C1: D1 grain A [001] -- right Q=0.012 vs runner-up Q=0.012*sqrt2 ###")
    run_grain(f"{S}/D1", f"{S}/D1.json", 0, (0, 0, 1), [0.012, 0.012 * math.sqrt(2)], "D1 A [001]")

    print("\n### C1: D1 grain C [111] -- right Q=0.012 vs runner-up Q=0.012*sqrt3 ###")
    run_grain(f"{S}/D1", f"{S}/D1.json", 2, (1, 1, 1), [0.012, 0.012 * math.sqrt(3)], "D1 C [111]")

    print("\n### C2: D2 grain A [001] -- right Q=0.012 vs chosen-wrong Q=0.012*sqrt2 ###")
    run_grain(f"{S}/D2", f"{S}/D2.json", 0, (0, 0, 1), [0.012, 0.012 * math.sqrt(2)], "D2 A [001]")

    print("\n### C2: D2 grain C [111] -- right Q=0.012 vs chosen-wrong Q=0.012*sqrt3 ###")
    run_grain(f"{S}/D2", f"{S}/D2.json", 2, (1, 1, 1), [0.012, 0.012 * math.sqrt(3)], "D2 C [111]")

    print("\n### C2: D3 grain C [111] -- right Q=0.012 vs chosen-wrong Q=0.012*sqrt3 ###")
    run_grain(f"{S}/D3", f"{S}/D3.json", 2, (1, 1, 1), [0.012, 0.012 * math.sqrt(3)], "D3 C [111]")

    print("\n### Angle-frame / truth cross-check: D1 grain A [001], right candidate only ###")
    print("Planted truth D1: ratio 1.085, angle 69.6 deg (row/col frame per generator).")
