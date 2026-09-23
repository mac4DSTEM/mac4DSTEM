#!/usr/bin/env python3
"""null_maps.py -- does the cleaned object count certify a classifier? (T2/T3 refutation, 2026-09-23)

Written by the independent refuter of docs/cloud/2026-09-23/T2-direction-check.md and
T3-gap-decomposition.md; it deliberately imports neither direction_check.py nor
precipitate_objects_ref.py (objects = scipy.ndimage.label, 8-connected). It builds null maps from
the Thronsen truth (Zenodo 10.5281/zenodo.6645396, CC BY 4.0) -- random Al flips at the app's
false-call rate, boundary erosion/dilation, one object deleted, two merged, 5 % label noise --
and applies the truth's cleanup rule P to each. Seeded (20260923): the output is reproducible.

usage: refute_null_maps.py DATA_DIR TRUTH_STRIDE3_JSON APP_LABELS_JSON
  (DATA_DIR from `direction_check.py fetch`; APP_LABELS_JSON from the probe's --dump-labels)
"""
import json, math, os, sys
import numpy as np
from scipy import ndimage

DATA, STRIDE3_JSON, APP_JSON = sys.argv[1:4]
import h5py

CLASSES = {1: "edge-on", 2: "face-on", 3: "T1"}
S8 = np.ones((3, 3), dtype=int)
S4 = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=int)
RULES = {
    "P": {1: (4, S8), 2: (782, S4), 3: (10, S4)},
}


def load(name):
    with h5py.File(os.path.join(DATA, name), "r") as h:
        g = h["Experiments"][list(h["Experiments"].keys())[0]]
        a = g["data"][()]
    out = np.rint(a).astype(np.int32)
    return out


def cleanup(labels, rule, thresholds=None):
    out = labels.copy()
    rules = thresholds if thresholds is not None else RULES[rule]
    for c, (min_area, conn) in rules.items():
        lab, n = ndimage.label(labels == c, structure=conn)
        if n == 0:
            continue
        sizes = np.bincount(lab.ravel())
        keep_small = np.zeros(n + 1, dtype=bool)
        keep_small[1:] = sizes[1:] < min_area
        out[keep_small[lab]] = 0
    return out


def scaled_rule(rule, stride):
    return {c: (max(1, math.ceil(a / stride ** 2)), conn) for c, (a, conn) in RULES[rule].items()}


def obj_counts(labels):
    out = {}
    for c in CLASSES:
        _, n = ndimage.label(labels == c, structure=S8)
        out[c] = n
    return out


def pct_err(a, b):
    return 100.0 * np.count_nonzero(a != b) / a.size


def report_variant(name, arr, truth_ref, rng_note=""):
    raw = obj_counts(arr)
    cleaned = cleanup(arr, "P")
    cleaned_counts = obj_counts(cleaned)
    err = pct_err(arr, truth_ref)
    print("  %-38s err=%6.2f%%  raw=%-22s P-cleaned=%-22s" %
          (name, err, raw, cleaned_counts))
    return raw, cleaned_counts, err


def main():
    truth = load("ground_truth.hspy")
    truth_counts = obj_counts(truth)
    truth_p_counts = obj_counts(cleanup(truth, "P"))
    print("Reference: truth raw = %s ; truth+P = %s\n" % (truth_counts, truth_p_counts))

    rng = np.random.default_rng(20260923)

    print("=" * 78)
    print("(a) truth with random Al pixels flipped to face-on/T1 at the app's false-call rate")
    # app's false-positive rate on Al pixels, from stride-3 baseline vs truth3
    j = json.load(open(STRIDE3_JSON))
    truth3 = np.array(j["labels"], dtype=np.int32)
    d = json.load(open(APP_JSON))
    w, h_ = d["width"], d["height"]
    baseline = np.array(d["baseline"], dtype=np.int32).reshape(h_, w)
    al_mask3 = truth3 == 0
    n_al = np.count_nonzero(al_mask3)
    fp_face = np.count_nonzero((truth3 == 0) & (baseline == 2)) / n_al
    fp_t1 = np.count_nonzero((truth3 == 0) & (baseline == 3)) / n_al
    print("  app's Al->face-on rate = %.5f, Al->T1 rate = %.5f (from stride-3 baseline vs truth)" % (fp_face, fp_t1))

    for trial in range(3):
        noisy = truth.copy()
        al = np.flatnonzero(truth.ravel() == 0)
        rr = rng.random(len(al))
        flip_face = al[rr < fp_face]
        flip_t1 = al[(rr >= fp_face) & (rr < fp_face + fp_t1)]
        flat = noisy.ravel()
        flat[flip_face] = 2
        flat[flip_t1] = 3
        noisy = flat.reshape(truth.shape)
        report_variant("random Al->{2,3} flips trial %d" % trial, noisy, truth)

    print()
    print("=" * 78)
    print("(b) truth with random erosion/dilation of precipitate boundaries (structuring elt radius 1, 50% each)")
    for trial in range(3):
        out = truth.copy()
        for c in CLASSES:
            mask = truth == c
            if rng.random() < 0.5:
                new = ndimage.binary_erosion(mask, structure=S8)
            else:
                new = ndimage.binary_dilation(mask, structure=S8)
            # apply: clear old class pixels, set class where new mask true (avoid clobbering other classes ownership)
            out[mask & ~new] = 0
            # only claim newly dilated pixels if they are currently background 0
            newly = new & ~mask & (out == 0)
            out[newly] = c
        report_variant("erode/dilate trial %d" % trial, out, truth)

    print()
    print("=" * 78)
    print("(c) truth with one real T1 object deleted, and two T1 objects merged")
    lab_t1, n_t1 = ndimage.label(truth == 3, structure=S8)
    sizes = ndimage.sum(np.ones_like(lab_t1), lab_t1, index=np.arange(1, n_t1 + 1))
    # delete a mid-sized object (not the largest, not the smallest, to be a "real" object)
    order = np.argsort(sizes)
    victim = order[len(order) // 2] + 1
    deleted = truth.copy()
    deleted[lab_t1 == victim] = 0
    report_variant("T1 object #%d (size %d) deleted" % (victim, sizes[victim - 1]), deleted, truth)

    # merge two nearby T1 objects: dilate one until it touches a neighboring object, or just bridge via a thin line
    # find two objects and connect with a straight pixel bridge along the line between centroids
    centroids = ndimage.center_of_mass(np.ones_like(lab_t1), lab_t1, index=np.arange(1, n_t1 + 1))
    centroids = np.array(centroids)
    # pick the two closest-centroid objects among the middle-sized ones (avoid degenerate)
    from scipy.spatial import distance_matrix
    dm = distance_matrix(centroids, centroids)
    np.fill_diagonal(dm, np.inf)
    i, jx = np.unravel_index(np.argmin(dm), dm.shape)
    merged = truth.copy()
    r0, c0 = centroids[i]
    r1, c1 = centroids[jx]
    n_steps = int(max(abs(r1 - r0), abs(c1 - c0))) + 1
    for t in np.linspace(0, 1, n_steps):
        rr = int(round(r0 + t * (r1 - r0)))
        cc = int(round(c0 + t * (c1 - c0)))
        merged[rr, cc] = 3
    report_variant("T1 objects #%d & #%d bridged (dist=%.1f px)" % (i + 1, jx + 1, dm[i, jx]), merged, truth)

    print()
    print("=" * 78)
    print("(d) 5%% random label noise (uniform over {0,1,2,3}) over the whole 512x512 truth")
    for trial in range(3):
        noisy = truth.copy().ravel()
        idx = rng.choice(noisy.size, size=int(0.05 * noisy.size), replace=False)
        noisy[idx] = rng.integers(0, 4, size=len(idx))
        noisy = noisy.reshape(truth.shape)
        report_variant("5%% noise trial %d" % trial, noisy, truth)

    print()
    print("=" * 78)
    print("Cross-check: apply the SAME grid rule (P/9) to truth@3 itself vs to a null map at stride 3")
    truth3_p9 = cleanup(truth3, "P", scaled_rule("P", 3))
    print("  truth@3 raw    = %s" % obj_counts(truth3))
    print("  truth@3 + P/9  = %s" % obj_counts(truth3_p9))
    # null: truth3 with same-rate Al flips at stride 3 directly (not resampled from full flip)
    al3 = np.flatnonzero(truth3.ravel() == 0)
    rr = rng.random(len(al3))
    noisy3 = truth3.copy().ravel()
    noisy3[al3[rr < fp_face]] = 2
    noisy3[al3[(rr >= fp_face) & (rr < fp_face + fp_t1)]] = 3
    noisy3 = noisy3.reshape(truth3.shape)
    noisy3_p9 = cleanup(noisy3, "P", scaled_rule("P", 3))
    print("  null3 (Al flips) raw   = %s  err=%.2f%%" % (obj_counts(noisy3), pct_err(noisy3, truth3)))
    print("  null3 (Al flips) + P/9 = %s" % obj_counts(noisy3_p9))


if __name__ == "__main__":
    main()
