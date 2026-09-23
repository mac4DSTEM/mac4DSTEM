#!/usr/bin/env python3
"""direction_check.py -- the Thronsen dataset-A published phase maps vs the
ground truth, at object level (T2) and the truth alone across sampling and
cleanup (T3). Brief: docs/cloud/2026-09-23-brief.md.

Data: Thronsen et al., Ultramicroscopy 255 (2024) 113861; Zenodo
10.5281/zenodo.6645396 (CC BY 4.0). Download the nine small files
(ground_truth.hspy, datasetA_phasemap_{ANN,NMF,TMP,vectors}.hspy,
datasetB_phase_map_ANN.hspy, datasetB_phasemap_{NMF,TMP,vectors}.hspy; < 1 MB
in all) into DATA_DIR and check each against the record's md5:

    python3 tools/cloud-analysis/direction_check.py fetch  DATA_DIR
    python3 tools/cloud-analysis/direction_check.py report DATA_DIR [TRUTH_STRIDE3_JSON]
    python3 tools/cloud-analysis/direction_check.py app LABELS_JSON TRUTH_STRIDE3_JSON

`app` reads the app's own stride-3 label map, written on a Mac by
    tools/thronsen-dataset/run.sh probe --rule known-variants --or \\
      --min-relative 0.001 --min-intensity 0 --object-table --dump-labels LABELS_JSON

Objects are the app's object definition via precipitate_objects_ref.py (a
Python transcription of PrecipitateSegmentation.classObjects: 8-connected
components per class, length = principal-axis centre span + 1). Object count
and median length follow tools/phase-map-probe's --object-table exactly:
count = every object of the class (edge-touching included), median =
sorted lengths [n // 2]. Quartiles here are [n // 4] and [(3 n) // 4].
Split / merge / vanished are the probe's definitions (main.swift:1616-1641):
a truth object touching >= 2 predicted objects of its class is split; a
predicted object touching >= 2 truth objects of its class is merged; a truth
object touching none is vanished. "Spurious" (added here) = a predicted
object touching no truth object of its class.

The cleanup rules are derived in the T2 report from create_ground_truth.ipynb
(read, not copied: that repository carries no licence). Removed pixels become
0 (Al), which is what happened to them when the truth was built.
"""
import hashlib
import json
import math
import os
import sys
import urllib.request

import h5py
import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import precipitate_objects_ref as ref  # noqa: E402

RECORD = "https://zenodo.org/api/records/6645396"
FILES = ["ground_truth.hspy"] + ["datasetA_phasemap_%s.hspy" % m for m in ("ANN", "NMF", "TMP", "vectors")] + \
        ["datasetB_phase_map_ANN.hspy"] + ["datasetB_phasemap_%s.hspy" % m for m in ("NMF", "TMP", "vectors")]
METHODS = ["ANN", "NMF", "TMP", "vectors"]
PAPER_ERROR = {"ANN": 0.96, "NMF": 1.50, "vectors": 1.54, "TMP": 1.75}  # % mislabelled, the paper / determine_accuracy
CLASSES = {1: "θ′ edge-on", 2: "θ′ face-on", 3: "T1"}
STRIDE = 3

# Cleanup rules: class -> (keep components with area >= min_area, connectivity).
# P = primary (median of the three annotators' cuts, the less aggressive where
# a class's median is ambiguous); H = the more aggressive bracket. Derivation
# and sources: docs/cloud/2026-09-23/T2-direction-check.md § The cleanup convention.
RULES = {
    "P": {1: (4, 8), 2: (782, 4), 3: (10, 4)},
    "H": {1: (4, 8), 2: (2001, 8), 3: (28, 4)},
}


def fetch(data_dir):
    os.makedirs(data_dir, exist_ok=True)
    record = json.load(urllib.request.urlopen(RECORD, timeout=60))
    for f in record["files"]:
        if f["key"] not in FILES:
            continue
        path = os.path.join(data_dir, f["key"])
        urllib.request.urlretrieve(f["links"]["self"], path)
        algo, want = f["checksum"].split(":")
        got = hashlib.new(algo, open(path, "rb").read()).hexdigest()
        print("%-32s %7d bytes %s %s" % (f["key"], f["size"], algo, "OK" if got == want else "MISMATCH " + got))
        if got != want:
            return 1
    return 0


def load(data_dir, name):
    with h5py.File(os.path.join(data_dir, name), "r") as h:
        g = h["Experiments"][list(h["Experiments"].keys())[0]]
        a = g["data"][()]
    out = np.rint(a).astype(np.int32)
    assert np.all(out == a), name + ": non-integer labels"
    return out


def cleanup(labels, rule):
    out = labels.copy()
    for c, (min_area, conn) in RULES[rule].items():
        structure = np.ones((3, 3), bool) if conn == 8 else ndimage.generate_binary_structure(2, 1)
        lab, n = ndimage.label(labels == c, structure=structure)
        if n == 0:
            continue
        sizes = np.bincount(lab.ravel())
        small = np.zeros(n + 1, bool)
        small[1:] = sizes[1:] < min_area
        out[small[lab]] = 0
    return out


def cleanup_on_grid(labels, rule, stride):
    """The same rule applied on a stride grid: each area threshold divided by stride**2, rounded up."""
    saved = RULES[rule]
    RULES["_grid"] = {c: (max(1, math.ceil(a / stride ** 2)), conn) for c, (a, conn) in saved.items()}
    try:
        return cleanup(labels, "_grid")
    finally:
        del RULES["_grid"]


def objects(labels, not_indexed):
    h, w = labels.shape
    r = ref.class_objects(labels.ravel().tolist(), w, h, precipitate={1, 2, 3}, matrix={0},
                          not_indexed=not_indexed, pixel_size=None, pixel_unit=None)
    return {c["label"]: c for c in r["classes"]}, r["analysed_pixels"]


def smv(truth_objs, pred_objs):
    pred_owner, truth_owner = {}, {}
    for o in pred_objs:
        for p in o.pixel_indices:
            pred_owner[p] = o.id
    for o in truth_objs:
        for p in o.pixel_indices:
            truth_owner[p] = o.id
    split = vanished = merge = spurious = 0
    for o in truth_objs:
        t = {pred_owner[p] for p in o.pixel_indices if p in pred_owner}
        vanished += not t
        split += len(t) > 1
    for o in pred_objs:
        t = {truth_owner[p] for p in o.pixel_indices if p in truth_owner}
        merge += len(t) > 1
        spurious += not t
    return split, merge, vanished, spurious


def lengths(objs):
    return sorted(float(o.length_px) for o in objs)


def q(s, num, den):
    return s[(num * len(s)) // den] if s else float("nan")


def row(tag, cls, truth_cls=None):
    objs = cls["objects"]
    s = lengths(objs)
    edge = sum(o.touches_edge for o in objs)
    af = cls["area_fraction"]
    cells = [tag, "%d" % len(objs), "%d" % edge, "%.2f" % q(s, 1, 2), "%.2f–%.2f" % (q(s, 1, 4), q(s, 3, 4)),
             "%.4f" % af if af is not None else "–"]
    if truth_cls is None:
        cells += ["–"] * 4
    else:
        cells += ["%d" % x for x in smv(truth_cls["objects"], objs)]
    return "| " + " | ".join(cells) + " |"


HEADER = ("| source | objects | edge | median len (px) | IQR len (px) | area frac | split | merge | vanished | spurious |\n"
          "|---|---|---|---|---|---|---|---|---|---|")


def per_position(truth, maps):
    print("## Per-position error (their definition: count_nonzero(map − truth) / 512², label 4 counted wrong)\n")
    print("| method | this run | paper | Δ (points) |\n|---|---|---|---|")
    for m in METHODS:
        e = 100.0 * np.count_nonzero(maps[m] != truth) / truth.size
        print("| %s | %.2f %% | %.2f %% | %+.2f |" % (m, e, PAPER_ERROR[m], e - PAPER_ERROR[m]))
    print()
    print("## Class coding check: per map, fraction of each truth class receiving the same label\n")
    print("| method | Al (0) | edge-on (1) | face-on (2) | T1 (3) | labels present |\n|---|---|---|---|---|---|")
    for m in METHODS:
        cells = []
        for c in range(4):
            sel = truth == c
            cells.append("%.3f" % np.mean(maps[m][sel] == c))
        print("| %s | %s | %s |" % (m, " | ".join(cells), sorted(np.unique(maps[m]).tolist())))
    print()


def summary_block(title, variants, truth_by_variant, ni_for):
    """variants: list of (source tag, labels, variant key). truth_by_variant[key] = truth labels for it."""
    print("## " + title + "\n")
    cache = {}
    for key, t in truth_by_variant.items():
        cache[key] = objects(t, set())
    rows = {c: [] for c in CLASSES}
    ratios = []
    for tag, labels, key in variants:
        classes, _ = objects(labels, ni_for(tag))
        tclasses, _ = cache[key]
        cells = []
        for c in CLASSES:
            rows[c].append(row(tag, classes[c], tclasses[c]))
            p, t = lengths(classes[c]["objects"]), lengths(tclasses[c]["objects"])
            cells += ["%.2f" % (len(p) / len(t)), "%.2f" % (q(p, 1, 2) / q(t, 1, 2)),
                      "%.3f" % (classes[c]["area_fraction"] / tclasses[c]["area_fraction"])]
        ratios.append("| %s | %s |" % (tag, " | ".join(cells)))
    for c, name in CLASSES.items():
        print("### %s\n" % name)
        print(HEADER)
        for key in truth_by_variant:
            print(row("truth · " + key, cache[key][0][c]))
        for r in rows[c]:
            print(r)
        print()
    print("### Ratios to truth (predicted / truth): object count, median length, area fraction\n")
    print("| source | " + " | ".join("%s count | %s median | %s area" % (n, n, n) for n in CLASSES.values()) + " |")
    print("|---|" + "---|" * (3 * len(CLASSES)))
    for r in ratios:
        print(r)
    print()
    return cache


def report(data_dir, truth_json=None):
    truth = load(data_dir, "ground_truth.hspy")
    maps = {m: load(data_dir, "datasetA_phasemap_%s.hspy" % m) for m in METHODS}
    print("# direction_check.py report\n")
    print("truth %s, labels %s\n" % (truth.shape, dict(zip(*[x.tolist() for x in np.unique(truth, return_counts=True)]))))
    for m in METHODS:
        print("%s %s, labels %s" % (m, maps[m].shape, dict(zip(*[x.tolist() for x in np.unique(maps[m], return_counts=True)]))))
    print()
    per_position(truth, maps)

    sub = truth[::STRIDE, ::STRIDE]
    if truth_json:
        j = np.array(json.load(open(truth_json))["labels"], dtype=np.int32)
        print("stride-%d truth vs %s: shape %s vs %s, identical: %s\n"
              % (STRIDE, os.path.basename(truth_json), sub.shape, j.shape, bool(j.shape == sub.shape and np.all(j == sub))))

    # Truth's own compliance with the rules: components the rule would remove.
    print("## The truth under the cleanup rules (pixels a rule would remove from the truth itself)\n")
    print("| rule | edge-on | face-on | T1 |\n|---|---|---|---|")
    for rule in RULES:
        if rule.startswith("_"):
            continue
        cl = cleanup(truth, rule)
        print("| %s | %s |" % (rule, " | ".join("%d" % np.count_nonzero((truth == c) & (cl != c)) for c in CLASSES)))
    print()

    ni = lambda tag: {4} if tag.startswith("vectors") else set()  # noqa: E731  vectors' label 4 = its not-indexed

    full = [(m, maps[m], "full") for m in METHODS] + \
           [("%s · P" % m, cleanup(maps[m], "P"), "full") for m in METHODS] + \
           [("%s · H" % m, cleanup(maps[m], "H"), "full") for m in METHODS]
    summary_block("Full resolution (512 × 512)", full, {"full": truth}, ni)

    s3 = [(m, maps[m][::STRIDE, ::STRIDE], "stride 3") for m in METHODS] + \
         [("%s · P then stride" % m, cleanup(maps[m], "P")[::STRIDE, ::STRIDE], "stride 3") for m in METHODS] + \
         [("%s · stride then P/9" % m, cleanup_on_grid(maps[m][::STRIDE, ::STRIDE], "P", STRIDE), "stride 3")
          for m in METHODS]
    summary_block("Stride 3 (every 3rd row and column from 0, as tools/thronsen-dataset/make_truth.py)",
                  s3, {"stride 3": sub}, ni)

    # T3: truth alone.
    print("## T3 — the truth alone across sampling and cleanup\n")
    variants = [("full", truth), ("full · P", cleanup(truth, "P")), ("full · H", cleanup(truth, "H"))]
    for k in (2, 3, 4):
        variants.append(("stride %d" % k, truth[::k, ::k]))
        variants.append(("stride %d · P/%d" % (k, k * k), cleanup_on_grid(truth[::k, ::k], "P", k)))
    print("| variant | " + " | ".join("%s objects | %s median len | %s area frac" % (n, n, n) for n in CLASSES.values()) + " |")
    print("|---|" + "---|" * (3 * len(CLASSES)))
    for tag, t in variants:
        classes, _ = objects(t, set())
        cells = []
        for c in CLASSES:
            s = lengths(classes[c]["objects"])
            cells += ["%d" % len(s), "%.2f" % q(s, 1, 2), "%.4f" % classes[c]["area_fraction"]]
        print("| %s | %s |" % (tag, " | ".join(cells)))
    print()
    # Stride-3 length in stride-3 pixels vs full-res length / 3 (sampling changes the unit).
    print("Lengths are in the sampled grid's own pixels: a full-resolution length L reads ≈ L / stride.\n")
    return 0


def app(labels_json, truth_json):
    """T3 on the app's own stride-3 map, dumped by tools/phase-map-probe --object-table --dump-labels."""
    d = json.load(open(labels_json))
    w, h = d["width"], d["height"]
    ni = set(d["notIndexedLabels"])
    truth = np.array(json.load(open(truth_json))["labels"], dtype=np.int32)
    assert truth.shape == (h, w), (truth.shape, (h, w))
    print("# direction_check.py app — the app's stride-3 map (known-variants baseline and guarded)\n")
    print("Python objects on the dumped labels, to compare line by line with the probe's own --object-table "
          "(count, median = sorted[n // 2], area fraction):\n")
    print("| class | source | objects | median len (px) | area frac |\n|---|---|---|---|---|")
    tclasses, _ = objects(truth, set())
    for c, name in CLASSES.items():
        s = lengths(tclasses[c]["objects"])
        print("| %s | truth | %d | %.2f | %.4f |" % (name, len(s), q(s, 1, 2), tclasses[c]["area_fraction"]))
        for key in ("baseline", "guarded"):
            lab = np.array(d[key], dtype=np.int32).reshape(h, w)
            classes, _ = objects(lab, ni)
            s = lengths(classes[c]["objects"])
            print("| %s | %s | %d | %.2f | %.4f |" % (name, key, len(s), q(s, 1, 2), classes[c]["area_fraction"]))
    print()
    variants = []
    for key in ("baseline", "guarded"):
        lab = np.array(d[key], dtype=np.int32).reshape(h, w)
        variants += [("app %s" % key, lab, "stride 3"),
                     ("app %s · P/9" % key, cleanup_on_grid(lab, "P", STRIDE), "stride 3"),
                     ("app %s · H/9" % key, cleanup_on_grid(lab, "H", STRIDE), "stride 3")]
    print("Per-position error of each variant (count(label != truth) / %d):\n" % truth.size)
    for tag, lab, _ in variants:
        print("- %s: %.2f %%" % (tag, 100.0 * np.count_nonzero(lab != truth) / truth.size))
    print()
    summary_block("The app's map at stride 3, raw and with the truth's convention on the grid",
                  variants, {"stride 3": truth}, lambda tag: ni)
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "fetch":
        return fetch(argv[2])
    if len(argv) >= 3 and argv[1] == "report":
        return report(argv[2], argv[3] if len(argv) > 3 else None)
    if len(argv) >= 4 and argv[1] == "app":
        return app(argv[2], argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
