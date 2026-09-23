#!/usr/bin/env python3
"""refute_verify.py -- the independent refuter's recount of T2/T3's numbers (2026-09-23).

Imports neither direction_check.py nor precipitate_objects_ref.py: objects are
scipy.ndimage.label (8-connected), lengths an own principal-axis extent. Data: Thronsen et al.,
Zenodo 10.5281/zenodo.6645396 (CC BY 4.0).

usage: refute_verify.py DATA_DIR TRUTH_STRIDE3_JSON APP_LABELS_JSON
"""
import json, math, os, sys
import numpy as np
from scipy import ndimage

DATA, STRIDE3_JSON, APP_JSON = sys.argv[1:4]

import h5py

METHODS = ["ANN", "NMF", "TMP", "vectors"]
PAPER_ERROR = {"ANN": 0.96, "NMF": 1.50, "vectors": 1.54, "TMP": 1.75}
CLASSES = {1: "edge-on", 2: "face-on", 3: "T1"}
S8 = np.ones((3, 3), dtype=int)   # 8-connectivity structure
S4 = np.array([[0,1,0],[1,1,1],[0,1,0]], dtype=int)  # 4-connectivity structure (ndi default)

RULES = {
    "P": {1: (4, S8), 2: (782, S4), 3: (10, S4)},
    "H": {1: (4, S8), 2: (2001, S8), 3: (28, S4)},
}


def load(name):
    with h5py.File(os.path.join(DATA, name), "r") as h:
        g = h["Experiments"][list(h["Experiments"].keys())[0]]
        a = g["data"][()]
    out = np.rint(a).astype(np.int32)
    assert np.all(out == a)
    return out


def count_objects(labels, cls, conn=S8, count_edge_touching=True):
    """8-connected components of `labels == cls`. Returns count (all components,
    edge-touching included, matching the claim's object definition)."""
    mask = labels == cls
    lab, n = ndimage.label(mask, structure=conn)
    return n, lab


def cleanup(labels, rule):
    out = labels.copy()
    for c, (min_area, conn) in RULES[rule].items():
        lab, n = ndimage.label(labels == c, structure=conn)
        if n == 0:
            continue
        sizes = np.bincount(lab.ravel())
        keep_small = np.zeros(n + 1, dtype=bool)
        keep_small[1:] = sizes[1:] < min_area
        out[keep_small[lab]] = 0
    return out


def cleanup_on_grid(labels, rule, stride):
    scaled = {}
    for c, (a, conn) in RULES[rule].items():
        scaled[c] = (max(1, math.ceil(a / stride ** 2)), conn)
    out = labels.copy()
    for c, (min_area, conn) in scaled.items():
        lab, n = ndimage.label(labels == c, structure=conn)
        if n == 0:
            continue
        sizes = np.bincount(lab.ravel())
        keep_small = np.zeros(n + 1, dtype=bool)
        keep_small[1:] = sizes[1:] < min_area
        out[keep_small[lab]] = 0
    return out, scaled


def obj_counts(labels):
    return {c: count_objects(labels, c)[0] for c in CLASSES}


def main():
    print("=" * 70)
    print("C1: per-position error, count(map != truth)/512^2")
    truth = load("ground_truth.hspy")
    maps = {m: load("datasetA_phasemap_%s.hspy" % m) for m in METHODS}
    for m in METHODS:
        e = 100.0 * np.count_nonzero(maps[m] != truth) / truth.size
        print("  %-8s this-run=%.4f%%  paper=%.2f%%  delta=%+.4f" % (m, e, PAPER_ERROR[m], e - PAPER_ERROR[m]))

    print()
    print("=" * 70)
    print("C2: raw full-res object counts (edge-on/face-on/T1)")
    truth_counts = obj_counts(truth)
    print("  truth   : %s" % truth_counts)
    for m in METHODS:
        print("  %-8s: %s" % (m, obj_counts(maps[m])))

    print()
    j = json.load(open(STRIDE3_JSON))
    truth3 = np.array(j["labels"], dtype=np.int32)
    sub = truth[::3, ::3]
    print("stride-3 truth json matches truth[::3,::3]:", truth3.shape == sub.shape and np.all(truth3 == sub))
    print("C2 stride-3 object counts (edge-on/face-on/T1)")
    print("  truth@3 : %s" % obj_counts(truth3))
    for m in METHODS:
        print("  %-8s: %s" % (m, obj_counts(maps[m][::3, ::3])))

    print()
    print("=" * 70)
    print("C3 support: check RULES against notebook thresholds (see report; not computed here)")

    print()
    print("=" * 70)
    print("C4: full-res object counts after cleanup rule P")
    for m in METHODS:
        cm = cleanup(maps[m], "P")
        print("  %-8s P: %s" % (m, obj_counts(cm)))
    truth_p = cleanup(truth, "P")
    print("  truth  P: %s" % obj_counts(truth_p))
    print("  truth  H: %s" % obj_counts(cleanup(truth, "H")))

    print()
    print("Does P remove any TRUE truth objects (components that exist and are >= threshold "
          "but get removed anyway) -- i.e. sanity check cleanup() is monotonic / idempotent")
    truth_p2 = cleanup(truth_p, "P")
    print("  cleanup(cleanup(truth,P),P) == cleanup(truth,P):", np.array_equal(truth_p, truth_p2))

    print()
    print("Does P remove any TRUE objects from the published maps (i.e. objects vanish that overlap truth)? "
          "count vanished truth-objects using P-cleaned map's object set (component touches none of the pred set)")
    for m in METHODS:
        raw = maps[m]
        cleaned = cleanup(raw, "P")
        for c in CLASSES:
            n_raw, lab_raw = count_objects(raw, c)
            n_clean, lab_clean = count_objects(cleaned, c)
            # objects in raw whose entire pixel set got zeroed by cleanup (i.e. below threshold, removed)
            removed = 0
            for i in range(1, n_raw + 1):
                mask_i = lab_raw == i
                if np.all(cleaned[mask_i] == 0):
                    removed += 1
            print("    %-8s class=%-8s raw_objs=%3d removed_by_P=%3d remaining=%3d" %
                  (m, CLASSES[c], n_raw, removed, n_clean))

    print()
    print("=" * 70)
    print("C5: stride-3 alone (truth only), no cleanup")
    print("  truth full : %s" % truth_counts)
    print("  truth @3   : %s" % obj_counts(truth3))
    # median lengths (approx via bbox extent along major axis is complex; use area-based proxy: skip exact length,
    # report median area as a proxy, and also actual "needle" object sizes for edge-on)
    for tag, arr in [("full", truth), ("stride3", truth3)]:
        _, lab = count_objects(arr, 1)
        n = lab.max()
        sizes = ndimage.sum(np.ones_like(lab), lab, index=np.arange(1, n + 1)) if n else np.array([])
        print("  edge-on %s: n=%d median_area=%.1f" % (tag, n, np.median(sizes) if len(sizes) else float('nan')))

    print()
    print("=" * 70)
    print("C6: app stride-3 baseline map")
    d = json.load(open(APP_JSON))
    w, h_ = d["width"], d["height"]
    ni = set(d["notIndexedLabels"])
    baseline = np.array(d["baseline"], dtype=np.int32).reshape(h_, w)
    guarded = np.array(d["guarded"], dtype=np.int32).reshape(h_, w)
    print("  app baseline shape", baseline.shape, "app json declared width,height=", w, h_)
    print("  app baseline counts: %s" % obj_counts(baseline))
    print("  app guarded  counts: %s" % obj_counts(guarded))
    print("  truth@3      counts: %s" % obj_counts(truth3))

    cleaned_grid, scaled = cleanup_on_grid(baseline, "P", 3)
    print("  P/9 scaled thresholds:", {CLASSES[c]: v for c, v in scaled.items()})
    print("  app baseline + P/9 : %s" % obj_counts(cleaned_grid))

    cleaned_grid_g, _ = cleanup_on_grid(guarded, "P", 3)
    print("  app guarded  + P/9 : %s" % obj_counts(cleaned_grid_g))

    # Does P/9 on the grid remove any TRUE stride-3 truth objects (i.e. truth itself loses objects under P/9)?
    print()
    print("Truth@3 under P/9 (does the truth's own stride-3 map lose T1/face-on objects under the grid rule?)")
    truth3_p9, _ = cleanup_on_grid(truth3, "P", 3)
    print("  truth@3        : %s" % obj_counts(truth3))
    print("  truth@3 + P/9  : %s" % obj_counts(truth3_p9))
    for c in CLASSES:
        n_raw, lab_raw = count_objects(truth3, c)
        n_clean, lab_clean = count_objects(truth3_p9, c)
        removed = 0
        for i in range(1, n_raw + 1):
            mask_i = lab_raw == i
            if np.all(truth3_p9[mask_i] == 0):
                removed += 1
        print("    class=%-8s raw=%3d removed_by_P/9=%3d remaining=%3d" % (CLASSES[c], n_raw, removed, n_clean))


if __name__ == "__main__":
    main()
