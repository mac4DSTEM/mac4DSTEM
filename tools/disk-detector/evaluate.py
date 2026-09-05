#!/usr/bin/env python
"""evaluate.py — step 3 numbers (§3a): does the learned detector earn its place? Numbers only; the verdict is the owner's.

Runs in the pinned py4DSTEM environment (it needs find_Bragg_disks and get_maxima_2D) and loads the
PyTorch net from the detector environment's torch? No — torch is not in the py4DSTEM env. So the net's
heatmaps are produced FIRST by the detector env (`--stage net`, writes .npz), then this script's
`--stage compare` (py4DSTEM env) refines and compares. run.sh evaluate drives both.

  fixture: net candidates + py4DSTEM's sub-pixel refinement (get_maxima_2D 'poly' on the flat-kernel
           correlation at the candidate's 3x3, standing in for the Metal engine) vs the drawn centres:
           recall, precision, residual before and after refinement.
  real cubes (bullseye, WS2, every --stride-th position): net vs the classical peak set at the
           2026-09-05 settings — per-position count difference, matched-position differences beyond
           0.5 px, the disagreement fraction; PNGs of a handful of disagreeing patterns with both overlays.
"""
from __future__ import annotations
import argparse, json, os, sys, time, warnings
import numpy as np
warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = dict(minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, subpixel="poly", sigma_cc=2, maxNumPeaks=70)
BULLSEYE = "4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"
WS2 = "4DSTEM/datacube/data"


def real_inputs(cube_path, dataset, probe, probe_centre, stride, size=sm.S):
    """Yields (ry, rx, pattern128, given probe, kernel) for every stride-th scan position, the pattern
    centre-cropped to 128 around the probe centre for the bullseye (250 px) and as-is for WS2 (128 px)."""
    import h5py
    with h5py.File(cube_path, "r") as f:
        d = f[dataset]
        kernel = sm.flat_kernel(probe, probe_centre)
        for ry in range(0, d.shape[0], stride):
            for rx in range(0, d.shape[1], stride):
                p = d[ry, rx].astype(np.float64)
                if p.shape[0] != size:
                    p, _ = sm.centred_crop(p, (124.76, 124.74), size)
                yield ry, rx, p, kernel


def stage_net(a):
    """Detector env: heatmaps for the fixture and the real cubes -> <out>/net-*.npz."""
    import torch, train as tr, export as ex
    model = ex.load_model(a.run).eval()
    def heat(xs):
        with torch.no_grad():
            return np.concatenate([model(torch.from_numpy(np.stack(xs[i:i + 32]))).numpy()[:, 0] for i in range(0, len(xs), 32)])
    z = np.load(os.path.join(HERE, "fixture", "fixture.npz")); e = json.load(open(os.path.join(HERE, "fixture", "expected.json")))
    probe = z["probe"].astype(np.float64); c = tuple(e["probe_centre"]); k = sm.flat_kernel(probe, c)
    xs = [sm.model_inputs(p.astype(np.float64), probe, sm.cross_correlation(p.astype(np.float64), k)) for p in z["patterns"]]
    np.savez_compressed(os.path.join(a.out, "net-fixture.npz"), heat=heat(xs))
    ing = np.load(a.ingredients)
    for name, path, ds, probe, c in [("bullseye", a.bullseye, BULLSEYE, ing["bullseye_probe"].astype(np.float64), tuple(ing["bullseye_centre"])),
                                     ("ws2", a.ws2, WS2, ing["ws2_probe"].astype(np.float64), tuple(ing["ws2_centre"]))]:
        pos, xs = [], []
        for ry, rx, p, k in real_inputs(path, ds, probe, c, a.stride):
            pos.append((ry, rx)); xs.append(sm.model_inputs(p, probe, sm.cross_correlation(p, k)))
        t0 = time.time(); h = heat(xs); dt = time.time() - t0
        np.savez_compressed(os.path.join(a.out, f"net-{name}.npz"), heat=h, positions=np.array(pos), seconds=dt)
        print(f"net {name}: {len(pos)} positions, {dt:.1f} s PyTorch CPU", flush=True)


def pick(heat, thr, top_k=70):
    from scipy.ndimage import maximum_filter
    mx = maximum_filter(heat, size=3, mode="constant")
    r, c = np.nonzero((heat == mx) & (heat > thr)); s = heat[r, c]; o = np.argsort(-s)[:top_k]
    return np.stack([r[o], c[o], s[o]], 1) if len(o) else np.zeros((0, 3))


def refine(cands, cc, sigma):
    """py4DSTEM's 'poly' sub-pixel refinement (get_maxima_2D, preprocess/utils.py) at each candidate's
    pixel on the sigma-smoothed correlation; the candidate is snapped to the correlation's local
    maximum within 2 px first (the net's peak is not the correlation's peak)."""
    from scipy.ndimage import gaussian_filter
    ar = gaussian_filter(cc, sigma) if sigma > 0 else cc
    out = []
    for r, c, s in cands:
        r0, c0 = int(round(r)), int(round(c))
        rs, re = max(r0 - 2, 1), min(r0 + 3, ar.shape[0] - 1); cs, ce = max(c0 - 2, 1), min(c0 + 3, ar.shape[1] - 1)
        if rs >= re or cs >= ce: continue
        w = ar[rs:re, cs:ce]; i, j = np.unravel_index(w.argmax(), w.shape); r0, c0 = rs + i, cs + j
        Ix1_, Ix0, Ix1 = ar[r0 - 1, c0], ar[r0, c0], ar[r0 + 1, c0]; Iy1_, Iy0, Iy1 = ar[r0, c0 - 1], ar[r0, c0], ar[r0, c0 + 1]
        dx = (Ix1 - Ix1_) / (4 * Ix0 - 2 * Ix1 - 2 * Ix1_) if (4 * Ix0 - 2 * Ix1 - 2 * Ix1_) != 0 else 0.0
        dy = (Iy1 - Iy1_) / (4 * Iy0 - 2 * Iy1 - 2 * Iy1_) if (4 * Iy0 - 2 * Iy1 - 2 * Iy1_) != 0 else 0.0
        out.append((r0 + dx, c0 + dy, float(Ix0)))
    return np.array(out).reshape(-1, 3)


def match(a_pts, b_pts, tol):
    """Greedy nearest matching; returns (pairs [(i,j,d)], unmatched_a, unmatched_b)."""
    used = np.zeros(len(b_pts), bool); pairs, ua = [], []
    for i, (r, c) in enumerate(a_pts):
        if len(b_pts) == 0: ua.append(i); continue
        d = np.hypot(b_pts[:, 0] - r, b_pts[:, 1] - c); d[used] = np.inf; j = int(np.argmin(d))
        if d[j] <= tol: pairs.append((i, j, d[j])); used[j] = True
        else: ua.append(i)
    return pairs, ua, list(np.nonzero(~used)[0])


def stage_compare(a):
    from py4DSTEM.braggvectors import find_Bragg_disks
    res = dict(threshold=a.threshold, settings=SETTINGS, stride=a.stride)
    # ---- fixture: net + refinement vs truth
    z = np.load(os.path.join(HERE, "fixture", "fixture.npz")); e = json.load(open(os.path.join(HERE, "fixture", "expected.json")))
    probe = z["probe"].astype(np.float64); c = tuple(e["probe_centre"]); k = sm.flat_kernel(probe, c)
    H = np.load(os.path.join(a.out, "net-fixture.npz"))["heat"]
    edge = SETTINGS["edgeBoundary"] + 2; tot = hit_raw = hit_ref = n_cand = 0; res_raw, res_ref = [], []; fp = 0
    for i, t in enumerate(e["truth"]):
        p = z["patterns"][i].astype(np.float64); cc = sm.cross_correlation(p, k)
        cen = np.array(t["centres"]).reshape(-1, 2); inten = np.array(t["intensities"])
        elig = (inten >= 0.10 * inten.max()) & (cen.min(1) >= edge) & (cen.max(1) < sm.S - edge); cen = cen[elig]
        cand = pick(H[i], a.threshold); ref = refine(cand, cc, SETTINGS["sigma_cc"])
        pr, _, _ = match(cen, cand[:, :2], 1.5); pf, _, unm = match(cen, ref[:, :2], 1.5)
        tot += len(cen); hit_raw += len(pr); hit_ref += len(pf); n_cand += len(cand); fp += len(unm)
        res_raw += [d for _, _, d in pr]; res_ref += [d for _, _, d in pf]
    res["fixture"] = dict(eligible_truth=int(tot), candidates=int(n_cand), recall_raw=hit_raw / tot, recall_refined=hit_ref / tot,
                          precision_refined=(n_cand - fp) / max(n_cand, 1), residual_raw_median=float(np.median(res_raw)), residual_raw_max=float(np.max(res_raw)),
                          residual_refined_median=float(np.median(res_ref)), residual_refined_max=float(np.max(res_ref)))
    print("fixture:", json.dumps(res["fixture"]), flush=True)
    # ---- real cubes: net vs classical
    ing = np.load(a.ingredients)
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    for name, path, ds, probe, c in [("bullseye", a.bullseye, BULLSEYE, ing["bullseye_probe"].astype(np.float64), tuple(ing["bullseye_centre"])),
                                     ("ws2", a.ws2, WS2, ing["ws2_probe"].astype(np.float64), tuple(ing["ws2_centre"]))]:
        N = np.load(os.path.join(a.out, f"net-{name}.npz")); H, pos = N["heat"], N["positions"]
        k = sm.flat_kernel(probe, c)
        counts, moved, disagree, examples, t_cl = [], [], 0, [], 0.0
        n_net = n_cl = matched = 0
        for i, (ry, rx, p, _) in enumerate(real_inputs(path, ds, probe, c, a.stride)):
            t0 = time.time(); q = find_Bragg_disks(p, k, **SETTINGS); t_cl += time.time() - t0
            cl = np.stack([q.data["qx"], q.data["qy"]], 1) if len(q.data) else np.zeros((0, 2))
            cc = sm.cross_correlation(p, k); cand = pick(H[i], a.threshold); net = refine(cand, cc, SETTINGS["sigma_cc"])[:, :2]
            pairs, un_cl, un_net = match(cl, net, 3.0)
            beyond = sum(1 for _, _, d in pairs if d > 0.5)
            counts.append(len(net) - len(cl)); moved.append(beyond); n_net += len(net); n_cl += len(cl); matched += len(pairs)
            dis = len(un_cl) + len(un_net) + beyond > 0
            disagree += dis
            if dis and len(examples) < a.examples: examples.append((ry, rx, p, cl, net, un_cl, un_net))
        n = len(pos); counts = np.array(counts)
        res[name] = dict(positions=n, classical_peaks=int(n_cl), net_peaks_refined=int(n_net), matched_within_3px=int(matched),
                         count_diff_net_minus_classical=dict(min=int(counts.min()), median=float(np.median(counts)), max=int(counts.max()), mean=float(counts.mean())),
                         matched_beyond_0p5px=int(sum(moved)), positions_with_any_disagreement=int(disagree), disagreement_fraction=disagree / n,
                         classical_seconds_py4dstem=t_cl, net_seconds_pytorch_cpu=float(N["seconds"]))
        print(name + ":", json.dumps(res[name]), flush=True)
        if examples:
            fig, ax = plt.subplots(1, len(examples), figsize=(4 * len(examples), 4.4))
            ax = np.atleast_1d(ax)
            for axx, (ry, rx, p, cl, net, un_cl, un_net) in zip(ax, examples):
                axx.imshow(np.log1p(np.maximum(p - p.min(), 0)), cmap="gray")
                if len(cl): axx.scatter(cl[:, 1], cl[:, 0], s=60, facecolors="none", edgecolors="cyan", label=f"classical {len(cl)}")
                if len(net): axx.scatter(net[:, 1], net[:, 0], s=20, marker="x", c="red", label=f"net+refine {len(net)}")
                axx.set_title(f"{name} ({ry},{rx}): classical-only {len(un_cl)}, net-only {len(un_net)}", fontsize=8); axx.legend(fontsize=7, loc="lower right"); axx.set_axis_off()
            fig.tight_layout(); fig.savefig(os.path.join(a.out, f"disagree-{name}.png"), dpi=90); plt.close(fig)
    json.dump(res, open(os.path.join(a.out, "evaluate.json"), "w"), indent=1); print("wrote", os.path.join(a.out, "evaluate.json"))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--stage", choices=["net", "compare"], required=True)
    ap.add_argument("--run", required=True); ap.add_argument("--out", required=True); ap.add_argument("--ingredients", required=True)
    ap.add_argument("--bullseye", required=True); ap.add_argument("--ws2", required=True)
    ap.add_argument("--stride", type=int, default=8); ap.add_argument("--threshold", type=float, default=0.3); ap.add_argument("--examples", type=int, default=6)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    stage_net(a) if a.stage == "net" else stage_compare(a)


if __name__ == "__main__":
    main()
