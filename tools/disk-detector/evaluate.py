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
import argparse, dataclasses, json, os, sys, time, warnings
import numpy as np
warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# The reference is the lock, not whatever py4DSTEM the interpreter has (decisions.md, 2026-09-07).
_LOCK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "References", "py4DSTEM-dev")
if os.path.exists(os.path.join(_LOCK, "py4DSTEM", "version.py")):
    sys.path.insert(0, os.path.abspath(_LOCK))
import simulate as sm

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = dict(minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, subpixel="poly", sigma_cc=2, maxNumPeaks=70)
BULLSEYE = "4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"
WS2 = "4DSTEM/datacube/data"


def real_inputs(cube_path, dataset, probe, probe_centre, stride, size=sm.S, positions=None, native_centre=None):
    """Yields (ry, rx, pattern, kernel) for every stride-th scan position (or the given `positions`),
    the pattern FIT to `size` around `native_centre` (`simulate.fit_to`: crops the 250-px bullseye
    frame down, pads a smaller frame like WS2's 128 up -- C7 2026-09-07; the old hardcoded bullseye
    constant is the fallback so an old caller that never passes `native_centre` keeps its exact old
    behaviour), and scaled into counts by the one rule (`simulate.to_counts`)."""
    import h5py
    if native_centre is None:
        native_centre = (124.76, 124.74)   # the bullseye probe's own centre of mass; C7's back-compat default
    with h5py.File(cube_path, "r") as f:
        d = f[dataset]
        kernel = sm.flat_kernel(probe, probe_centre)
        if positions is None:
            positions = [(ry, rx) for ry in range(0, d.shape[0], stride) for rx in range(0, d.shape[1], stride)]
        for ry, rx in positions:
            p = sm.to_counts(d[ry, rx].astype(np.float64))
            if p.shape[0] != size:
                p, _ = sm.fit_to(p, native_centre, size)
            yield ry, rx, p, kernel


def native_centre_for(ing, key):
    """The ingredient's NATIVE centre (C7 2026-09-07: computed once at `ingredients` build time, before
    any fit_to), from the ingredients npz; None for an older npz built before this field existed (the
    caller then falls back to the old hardcoded bullseye constant)."""
    k = f"{key}_native_centre"
    return tuple(ing[k]) if k in ing.files else None


def label_ingredient(L, ing, fallback):
    """The ingredients-npz key the labels' probe lives under. A labels file written by the app
    (DiskCentreLabelStore, C7 session 4) carries ingredient "app", which no npz has — `--ingredient`
    names the key then; a tool file's own ingredient wins when the npz has it (Gate B, 2026-09-08)."""
    key = L.get("ingredient")
    if f"{key}_probe" in ing:
        return key
    if fallback and f"{fallback}_probe" in ing:
        return fallback
    raise SystemExit(f"labels ingredient {key!r} is not in the ingredients npz — pass --ingredient bullseye|ws2")


def load_labels(path):
    """The frozen hand-labelled test set (label_centres.py): {cube, dataset, ingredient, frame:
    "native", positions: [{ry, rx, centres: [[row, col], ...]}]} in NATIVE pattern coordinates (C7
    2026-09-07). Never used for selection. Refuses an older labels file recorded in the model-frame
    convention rather than silently mis-scoring it."""
    L = json.load(open(path))
    if L.get("frame") != "native":
        raise SystemExit(f"labels file {path!r} has frame {L.get('frame')!r}, not 'native' — "
                          f"it was written by an older label_centres.py in the model-frame convention; "
                          f"re-label with the current tool rather than guessing the offset")
    return L, [(int(p["ry"]), int(p["rx"])) for p in L["positions"]]


def stage_net(a):
    """Detector env: heatmaps for the fixture and the real cubes -> <out>/net-*.npz. With `--asset`
    the heatmaps come from the EXPORTED Core AI asset (its `heatmap` output, Neural Engine preferred,
    in a subprocess as check_export does), so that step 3 judges what the app would run, not
    PyTorch (2026-09-07; the overnight numbers were PyTorch's)."""
    import torch, train as tr, export as ex
    model = ex.load_model(a.run).eval()
    def heat_torch(xs):
        with torch.no_grad():
            return np.concatenate([model(torch.from_numpy(np.stack(xs[i:i + 32]))).numpy()[:, 0] for i in range(0, len(xs), 32)])
    def heat_asset(xs):
        import check_export as ce
        x = np.stack(xs).astype(np.float32); B = a.asset_batch; n = len(x)
        if n % B: x = np.concatenate([x, np.zeros((B - n % B,) + x.shape[1:], np.float32)])
        work = os.path.join(a.out, "asset-work"); os.makedirs(work, exist_ok=True)
        xin = os.path.join(work, "x.npz")
        if os.path.exists(xin): os.remove(xin)          # run_coreai_subprocess reuses x.npz if present
        r = ce.run_coreai_subprocess(a.asset, x, "ane", a.asset_function, work)
        h = r["heatmap"]; h = h[:, 0] if h.ndim == 4 else h
        print(f"asset {os.path.basename(a.asset)} [ane]: load {r['load_s']:.2f} s, {np.median(r['times'][1:] if len(r['times']) > 1 else r['times']) / B * 1000:.3f} ms/pattern", flush=True)
        return h[:n].astype(np.float32)
    heat = heat_asset if a.asset else heat_torch
    size = a.size   # resolved once in main() from the run's config.json ("--size" overrides), C7 2026-09-07
    z = np.load(os.path.join(HERE, "fixture", "fixture.npz")); e = json.load(open(os.path.join(HERE, "fixture", "expected.json")))
    probe_centre = tuple(e["probe_centre"])
    xs = []
    for p in z["patterns"]:
        pf, probef, cf = sm.fit_fixture_to(p.astype(np.float64), z["probe"].astype(np.float64), probe_centre, size)
        xs.append(sm.model_inputs(pf, probef, sm.cross_correlation(pf, sm.flat_kernel(probef, cf))))
    np.savez_compressed(os.path.join(a.out, "net-fixture.npz"), heat=heat(xs))
    # the validation set (train.fixed_set, seed 999, 128 samples): the same simulated set the
    # trainer's recall/precision quote, now scored on the EXPORTED asset at the shipped threshold
    cfg_path = os.path.join(a.run, "config.json"); cfg = sm.SimConfig(**json.load(open(cfg_path))["config"]) if os.path.exists(cfg_path) else sm.SimConfig()
    cfg = dataclasses.replace(cfg, size=size)   # --size may override the run's own recorded size
    vx, _, vcen = tr.fixed_set(a.ingredients, cfg, 999, 128)
    vh = heat([x for x in vx.numpy()])
    np.savez_compressed(os.path.join(a.out, "net-validation.npz"), heat=vh, centres=np.array([c.reshape(-1, 2) for c in vcen], dtype=object), allow_pickle=True)
    ing = np.load(a.ingredients)
    cases = [("bullseye", a.bullseye, BULLSEYE, ing["bullseye_probe"].astype(np.float64), tuple(ing["bullseye_centre"]), None, "bullseye"),
             ("ws2", a.ws2, WS2, ing["ws2_probe"].astype(np.float64), tuple(ing["ws2_centre"]), None, "ws2")]
    if a.labels:
        L, lpos = load_labels(a.labels)
        lk = label_ingredient(L, ing, a.ingredient)
        cases.append(("labels", L["cube"], L["dataset"], ing[f"{lk}_probe"].astype(np.float64), tuple(ing[f"{lk}_centre"]), lpos, lk))
    for name, path, ds, probe, c, positions, ing_key in cases:
        native = native_centre_for(ing, ing_key)
        pos, xs = [], []
        for ry, rx, p, k in real_inputs(path, ds, probe, c, a.stride, size=size, positions=positions, native_centre=native):
            pos.append((ry, rx)); xs.append(sm.model_inputs(p, probe, sm.cross_correlation(p, k)))
        t0 = time.time(); h = heat(xs); dt = time.time() - t0
        np.savez_compressed(os.path.join(a.out, f"net-{name}.npz"), heat=h, positions=np.array(pos), seconds=dt)
        print(f"net {name}: {len(pos)} positions, {dt:.1f} s", flush=True)


def pick(heat, thr, top_k=70):
    from scipy.ndimage import maximum_filter
    mx = maximum_filter(heat, size=3, mode="constant")
    r, c = np.nonzero((heat == mx) & (heat > thr)); s = heat[r, c]; o = np.argsort(-s)[:top_k]
    return np.stack([r[o], c[o], s[o]], 1) if len(o) else np.zeros((0, 3))


def refine(cands, cc, sigma):
    """py4DSTEM's 'poly' sub-pixel refinement (get_maxima_2D, preprocess/utils.py) at each candidate's
    pixel on the sigma-smoothed correlation; the candidate is snapped to the correlation's local
    maximum within 2 px first (the net's peak is not the correlation's), and REJECTED if the snapped
    pixel is not an 8-neighbour local maximum (Gate B 2026-09-07: py4DSTEM only ever evaluates the
    parabola at a maximum; on a flank it fabricated positions up to 28 px off, and 10 of the
    fixture's 255 accepted peaks were such fabrications). Mirrors DiskDetector.refine in the app."""
    from scipy.ndimage import gaussian_filter
    ar = gaussian_filter(cc, sigma) if sigma > 0 else cc
    out = []
    for r, c, s in cands:
        r0, c0 = int(round(r)), int(round(c))
        rs, re = max(r0 - 2, 1), min(r0 + 3, ar.shape[0] - 1); cs, ce = max(c0 - 2, 1), min(c0 + 3, ar.shape[1] - 1)
        if rs >= re or cs >= ce: continue
        w = ar[rs:re, cs:ce]; i, j = np.unravel_index(w.argmax(), w.shape); r0, c0 = rs + i, cs + j
        if (ar[r0 - 1:r0 + 2, c0 - 1:c0 + 2] > ar[r0, c0]).any():   # not a local maximum: the correlation does not confirm it
            continue
        Ix1_, Ix0, Ix1 = ar[r0 - 1, c0], ar[r0, c0], ar[r0 + 1, c0]; Iy1_, Iy0, Iy1 = ar[r0, c0 - 1], ar[r0, c0], ar[r0, c0 + 1]
        with np.errstate(divide="ignore", invalid="ignore"):   # unguarded like py4DSTEM's get_maxima_2D and the app
            dx = float(np.float64(Ix1 - Ix1_) / np.float64(4 * Ix0 - 2 * Ix1 - 2 * Ix1_))
            dy = float(np.float64(Iy1 - Iy1_) / np.float64(4 * Iy0 - 2 * Iy1 - 2 * Iy1_))
        if not (np.isfinite(dx) and np.isfinite(dy)):   # the app's rule (DiskDetector.polyRefine): a non-finite shift is not applied
            dx = dy = 0.0
        out.append((r0 + dx, c0 + dy, float(Ix0), float(s)))
    return np.array(out).reshape(-1, 4)


def accept(ref, spacing, edge, size=sm.S):
    """The acceptance rule after refinement (2026-09-07; before it, refinement rejected nothing):
    (1) drop anything within `edge` px of the border (py4DSTEM's edgeBoundary), (2) greedy
    non-maximum suppression by NET score: a refined candidate closer than `spacing` px
    (py4DSTEM's minPeakSpacing, the same rule the classical side obeys) to an already accepted one
    is a duplicate -- two net maxima snapped to one correlation peak -- and is dropped. The net's
    own threshold is the only intensity rule; a correlation-relative cut is deliberately NOT
    reinstated (it is what drops the faint disks the net is for)."""
    if len(ref) == 0: return ref
    ok = (ref[:, 0] >= edge) & (ref[:, 0] < size - edge) & (ref[:, 1] >= edge) & (ref[:, 1] < size - edge); ref = ref[ok]
    order = np.argsort(-ref[:, 3]); keep = []
    for i in order:
        if all(np.hypot(ref[i, 0] - ref[j, 0], ref[i, 1] - ref[j, 1]) >= spacing for j in keep): keep.append(i)
    return ref[sorted(keep)]


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
    probe = z["probe"].astype(np.float64); probe_centre = tuple(e["probe_centre"])
    H = np.load(os.path.join(a.out, "net-fixture.npz"))["heat"]
    size = H.shape[-1]   # the frame stage_net actually built at (native 128, or padded through fit_to -- C7)
    r0, c0 = sm.fit_offset(probe_centre, size)   # native (128) truth -> this frame
    if size != sm.S:
        print(f"fixture scored PADDED to {size}px through fit_to (native 128, C7 2026-09-07): the rows "
              f"below are padded-fixture rows, not the native 128 fixture", flush=True)
    edge = SETTINGS["edgeBoundary"] + 2
    # fit every fixture pattern + its probe once, at this run's size (identical for every threshold below)
    fitted = []
    for i, t in enumerate(e["truth"]):
        patf, probef, cf = sm.fit_fixture_to(z["patterns"][i].astype(np.float64), probe, probe_centre, size)
        k = sm.flat_kernel(probef, cf)
        cen = np.array(t["centres"]).reshape(-1, 2) - [r0, c0]
        fitted.append((patf, k, sm.cross_correlation(patf, k), cen, np.array(t["visibility"])))
    # the classical detector against the SAME visible truth, so the fixture rows are comparable
    cl_hit = cl_tot = cl_pred = 0
    for patf, k, cc, cen_all, vis in fitted:
        cen = cen_all[(vis >= sm.VISIBLE_MIN) & (cen_all.min(1) >= edge) & (cen_all.max(1) < size - edge)]
        q = find_Bragg_disks(patf, k, **SETTINGS); cl = np.stack([q.data["qx"], q.data["qy"]], 1) if len(q.data) else np.zeros((0, 2))
        pr, _, _ = match(cen, cl, 1.5); cl_hit += len(pr); cl_tot += len(cen); cl_pred += len(cl)
    res["fixture_classical"] = dict(eligible_truth=int(cl_tot), predicted=int(cl_pred), recall=cl_hit / max(cl_tot, 1), precision=cl_hit / max(cl_pred, 1), settings=SETTINGS, size=size)
    print("fixture classical:", json.dumps(res["fixture_classical"]), flush=True)
    res["fixture_by_threshold"] = {}
    for thr in sorted({a.threshold, 0.3, 0.5, 0.7, 0.9}):
        tot = hit_raw = hit_ref = n_cand = n_acc = 0; res_raw, res_ref = [], []; fp = 0
        for i, (patf, k, cc, cen_all, vis) in enumerate(fitted):
            elig = (vis >= sm.VISIBLE_MIN) & (cen_all.min(1) >= edge) & (cen_all.max(1) < size - edge); cen = cen_all[elig]   # the one truth rule
            cand = pick(H[i], thr); ref = accept(refine(cand, cc, SETTINGS["sigma_cc"]), SETTINGS["minPeakSpacing"], SETTINGS["edgeBoundary"], size=size)
            pr, _, _ = match(cen, cand[:, :2], 1.5); pf, _, unm = match(cen, ref[:, :2], 1.5)
            tot += len(cen); hit_raw += len(pr); hit_ref += len(pf); n_cand += len(cand); n_acc += len(ref); fp += len(unm)
            res_raw += [d for _, _, d in pr]; res_ref += [d for _, _, d in pf]
        r = dict(eligible_truth=int(tot), candidates=int(n_cand), accepted=int(n_acc), recall_raw=hit_raw / tot, recall_refined=hit_ref / tot,
                 precision_accepted=(n_acc - fp) / max(n_acc, 1), residual_raw_median=float(np.median(res_raw)) if res_raw else None,
                 residual_raw_max=float(np.max(res_raw)) if res_raw else None, residual_refined_median=float(np.median(res_ref)) if res_ref else None,
                 residual_refined_max=float(np.max(res_ref)) if res_ref else None, size=size)
        res["fixture_by_threshold"][str(thr)] = r
        print(f"fixture @{thr}:", json.dumps(r), flush=True)
    res["fixture"] = res["fixture_by_threshold"][str(a.threshold)]
    # ---- validation set: raw picks at the shipped threshold vs the visible centres, 2 px, as train.py scores
    vpath = os.path.join(a.out, "net-validation.npz")
    if os.path.exists(vpath):
        V = np.load(vpath, allow_pickle=True); vh, vcen = V["heat"], V["centres"]
        vsize = vh.shape[-1]
        hit = tot = pred = 0
        for i in range(len(vh)):
            truth = np.asarray(vcen[i], dtype=np.float64).reshape(-1, 2); truth = truth[(truth.min(1) >= 4) & (truth.max(1) < vsize - 4)]
            picks = pick(vh[i], a.threshold)[:, :2]; pr, _, _ = match(truth, picks, 2.0)
            hit += len(pr); tot += len(truth); pred += len(picks)
        res["validation"] = dict(samples=int(len(vh)), threshold=a.threshold, size=vsize, visible_truth=int(tot), predicted=int(pred), recall=hit / max(tot, 1), precision=hit / max(pred, 1),
                                 note="raw picks (no refinement), 2 px, edge 4 — train.py's own scoring, on the exported asset when --asset was given")
        print("validation:", json.dumps(res["validation"]), flush=True)
    # ---- real cubes: net vs classical
    ing = np.load(a.ingredients)
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    # WS2 at minRelativeIntensity 0.05 yields one peak per position (the central beam dwarfs the disks —
    # the 2026-09-05 measurement in docs/status.md), so it is also compared at the app's 0.005 default.
    cases = [("bullseye", a.bullseye, BULLSEYE, "bullseye", SETTINGS), ("ws2", a.ws2, WS2, "ws2", SETTINGS),
             ("ws2-minrel0.005", a.ws2, WS2, "ws2", dict(SETTINGS, minRelativeIntensity=0.005))]
    for name, path, ds, ing_key, settings in cases:
        probe, c = ing[f"{ing_key}_probe"].astype(np.float64), tuple(ing[f"{ing_key}_centre"])
        native = native_centre_for(ing, ing_key)
        N = np.load(os.path.join(a.out, f"net-{ing_key}.npz")); H, pos = N["heat"], N["positions"]
        size = H.shape[-1]   # the frame stage_net actually built this cube's inputs at
        k = sm.flat_kernel(probe, c)
        counts, moved, disagree, examples, t_cl = [], [], 0, [], 0.0
        n_net = n_cl = matched = 0
        for i, (ry, rx, p, _) in enumerate(real_inputs(path, ds, probe, c, a.stride, size=size, native_centre=native)):
            t0 = time.time(); q = find_Bragg_disks(p, k, **settings); t_cl += time.time() - t0
            cl = np.stack([q.data["qx"], q.data["qy"]], 1) if len(q.data) else np.zeros((0, 2))
            cc = sm.cross_correlation(p, k); cand = pick(H[i], a.threshold)
            net = accept(refine(cand, cc, settings["sigma_cc"]), settings["minPeakSpacing"], settings["edgeBoundary"], size=size)[:, :2]
            pairs, un_cl, un_net = match(cl, net, 3.0)
            beyond = sum(1 for _, _, d in pairs if d > 0.5)
            counts.append(len(net) - len(cl)); moved.append(beyond); n_net += len(net); n_cl += len(cl); matched += len(pairs)
            dis = len(un_cl) + len(un_net) + beyond > 0
            disagree += dis
            if dis and len(examples) < a.examples: examples.append((ry, rx, p, cl, net, un_cl, un_net))
        n = len(pos); counts = np.array(counts)
        res[name] = dict(positions=n, settings=settings, size=size, classical_peaks=int(n_cl), net_peaks_refined=int(n_net), matched_within_3px=int(matched),
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
                axx.set_title(f"{name} ({ry},{rx}): classical-only {len(un_cl)}, net-only {len(un_net)}", fontsize=8); axx.legend(fontsize=7, loc="lower right")
                axx.set_xlim(-0.5, size - 0.5); axx.set_ylim(size - 0.5, -0.5); axx.set_axis_off()
            fig.tight_layout(); fig.savefig(os.path.join(a.out, f"disagree{a.tag}-{name}.png"), dpi=90); plt.close(fig)
    res["count_scaling"] = dict(rule="simulate.to_counts", nominal_beam_counts=sm.NOMINAL_BEAM_COUNTS)
    # ---- the frozen hand-labelled test set: net (exported asset at the shipped threshold) AND
    # classical, each against the same truth, so the comparison is against truth, not against each other.
    # Labels are recorded in NATIVE pattern coordinates (C7 2026-09-07); mapped into this run's model
    # frame with the SAME fit_offset real_inputs used to fit the pattern, so one labels file scores
    # both a 128-px and a 256-px asset.
    if a.labels:
        L, lpos = load_labels(a.labels)
        lk = label_ingredient(L, ing, a.ingredient)
        probe, c = ing[f"{lk}_probe"].astype(np.float64), tuple(ing[f"{lk}_centre"])
        native = native_centre_for(ing, lk)
        N = np.load(os.path.join(a.out, "net-labels.npz")); H = N["heat"]
        size = H.shape[-1]
        k = sm.flat_kernel(probe, c)
        lr0, lc0 = sm.fit_offset(native if native is not None else (124.76, 124.74), size)
        tol = a.label_tol; tally = {"net": [0, 0, 0], "classical": [0, 0, 0]}   # hit, truth, predicted
        # ELIGIBLE truth (2026-09-08): a native label that lands outside this frame, or inside its
        # edgeBoundary, is unreachable by either detector -- a 128-px frame of the 250-px bullseye
        # pattern holds ~40 % of the labels. recall_eligible is recall over those; `recall` stays
        # over every label so a 128-px and a 256-px row are read against the same 306.
        edge_l = SETTINGS["edgeBoundary"]; n_eligible = 0
        for i, ((ry, rx, p, _), lab) in enumerate(zip(real_inputs(L["cube"], L["dataset"], probe, c, 1, positions=lpos, size=size, native_centre=native), L["positions"])):
            truth = np.array(lab["centres"], dtype=np.float64).reshape(-1, 2) - [lr0, lc0]   # native -> model frame
            n_eligible += int(((truth.min(1) >= edge_l) & (truth.max(1) < size - edge_l)).sum()) if len(truth) else 0
            q = find_Bragg_disks(p, k, **SETTINGS)
            cl = np.stack([q.data["qx"], q.data["qy"]], 1) if len(q.data) else np.zeros((0, 2))
            cc = sm.cross_correlation(p, k)
            net = accept(refine(pick(H[i], a.threshold), cc, SETTINGS["sigma_cc"]), SETTINGS["minPeakSpacing"], SETTINGS["edgeBoundary"], size=size)[:, :2]
            for key, pred in (("net", net), ("classical", cl)):
                pairs, _, _ = match(truth, pred, tol)
                tally[key][0] += len(pairs); tally[key][1] += len(truth); tally[key][2] += len(pred)
        res["labels"] = dict(file=os.path.abspath(a.labels), sha256=L.get("sha256"), positions=len(lpos), truth_centres=tally["net"][1], truth_eligible=int(n_eligible),
                             match_tol_px=tol, net_threshold=a.threshold, size=size, net_source=("asset" if N.get("asset", None) is not None else "see stage net"))
        for key in ("net", "classical"):
            hit, tot, pred = tally[key]
            res["labels"][key] = dict(recall=hit / max(tot, 1), recall_eligible=hit / max(n_eligible, 1), precision=hit / max(pred, 1), predicted=int(pred), matched=int(hit))
        print("labels:", json.dumps(res["labels"]), flush=True)
    json.dump(res, open(os.path.join(a.out, f"evaluate{a.tag}.json"), "w"), indent=1); print("wrote", os.path.join(a.out, f"evaluate{a.tag}.json"))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--stage", choices=["net", "compare"], required=True)
    ap.add_argument("--run", required=True); ap.add_argument("--out", required=True); ap.add_argument("--ingredients", required=True)
    ap.add_argument("--bullseye", required=True); ap.add_argument("--ws2", required=True)
    ap.add_argument("--stride", type=int, default=8); ap.add_argument("--threshold", type=float, default=0.3); ap.add_argument("--examples", type=int, default=6)
    ap.add_argument("--tag", default="", help="suffix for evaluate<tag>.json and the PNGs (a second threshold, say)")
    ap.add_argument("--labels", help="the frozen hand-labelled test set (label_centres.py JSON): scores net and classical against it")
    ap.add_argument("--ingredient", default=None, help="the npz key for a labels file whose own ingredient is not in the npz (an app export says \"app\"): bullseye|ws2")
    ap.add_argument("--label-tol", type=float, default=2.0, help="match radius in px against the hand labels")
    ap.add_argument("--asset", help="stage net: a Core AI .aimodel whose `heatmap` output replaces PyTorch's (the exported runtime, ANE preferred)")
    ap.add_argument("--asset-function", default="heatmap"); ap.add_argument("--asset-batch", type=int, default=32)
    ap.add_argument("--size", type=int, default=None, help="the model size (default: read from --run's config.json; overrides it when given) — C7 2026-09-07")
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    # the run's own model size, --size overriding when given (only "net" needs the training run's
    # config.json to build the right-sized inputs; "compare" re-derives size per section from the
    # heatmap arrays stage_net wrote, so this is a convenience default there, not load-bearing)
    if a.size is None:
        cfg_path = os.path.join(a.run, "config.json")
        a.size = int(json.load(open(cfg_path)).get("config", {}).get("size", sm.S)) if os.path.exists(cfg_path) else sm.S
    stage_net(a) if a.stage == "net" else stage_compare(a)


if __name__ == "__main__":
    main()
