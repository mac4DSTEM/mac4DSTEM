#!/usr/bin/env python3
"""tools/acom-groundtruth/demo-cube.py — feed the demo cube's own peaks to the
ACOM harness and score the answers against its truth.

WHY HERE: main.swift says it exists "so a Python driver can feed it"; until
2026-09-14 no driver was checked in, and the first question the demo cube
raised (does the app's ACOM put the [011] and [111] grains where truth puts
them?) was answered with a throw-away script. This is that script, kept.
Diagnostic, like the harness: needs References/demo-dataset/AlMgSi_demo.h5
(tools/demo-dataset/run.sh) and a Python with h5py + numpy.

  python3 tools/acom-groundtruth/demo-cube.py build  > input.json
  tools/acom-groundtruth/run.sh input.json           > output.json
  python3 tools/acom-groundtruth/demo-cube.py score output.json

Peaks are 5×5 local maxima above 1500 counts at integer pixels (the cube's
background is ~492 counts, its weakest Al spot ~2 800), including the direct
beam, at three positions per grain. Plan parameters mirror the app's call
(App/AppState.swift, OrientationPlan.generate: kMax 1.2, 200 templates, the
generate() defaults for intensityPower/radialKernel/distinct, no wavelength
because the cube carries no accelerating voltage).
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CUBE = os.path.join(ROOT, "References", "demo-dataset", "AlMgSi_demo.h5")
DATA = "/4DSTEM_experiment/data/datacubes/datacube_0/data"
POSITIONS = {  # (row, column) — truth.json: A = [001], B = [011], C = [111]
    "A": [(15, 35), (25, 45), (45, 10)],
    "B": [(15, 70), (30, 85), (40, 60)],
    "C": [(60, 70), (75, 85), (90, 60)],
}
TRUTH = {"A": (0, 0, 1), "B": (0, 1, 1), "C": (1, 1, 1)}
LABELS = [f"{g} r{r} c{c}" for g, pl in POSITIONS.items() for r, c in pl]


def local_maxima(img, k=2):
    p = np.pad(img, k, mode="constant", constant_values=-1)
    out = img.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            out = np.maximum(out, p[k + dy:k + dy + img.shape[0], k + dx:k + dx + img.shape[1]])
    return img == out


def build():
    import h5py
    d = h5py.File(CUBE, "r")[DATA]
    patterns = []
    for g, pl in POSITIONS.items():
        for r, c in pl:
            img = d[r, c].astype(np.float64)
            ys, xs = np.nonzero(local_maxima(img) & (img > 1500))
            patterns.append([{"x": float(x), "y": float(y), "intensity": float(img[y, x])}
                             for x, y in zip(xs, ys)])
    json.dump({
        "cellAAngstrom": 4.0495,
        "siteFractional": [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]],
        "siteAtomicNumbers": [13, 13, 13, 13],
        "kMaxInvAngstrom": 1.2, "zoneAxisCount": 200, "symmetry": "cubic",
        "invAngstromPerPixel": 0.012, "originX": 63.5, "originY": 63.5,
        "intensityPower": 0.25, "radialKernelInvAngstrom": 0.08,
        "distinctOrientationDeg": 10, "patterns": patterns,
    }, sys.stdout)


def family_angle(a, b):
    """Angle between two directions after m-3m reduction (|x|,|y|,|z| sorted)."""
    fa, fb = (np.sort(np.abs(np.asarray(v, float))) for v in (a, b))
    fa, fb = fa / np.linalg.norm(fa), fb / np.linalg.norm(fb)
    return float(np.degrees(np.arccos(np.clip(fa @ fb, -1, 1))))


def score(path):
    out = json.load(open(path))
    print(f"{out['templateCount']} templates; first three axes:",
          [np.round(a, 3).tolist() for a in out["zoneAxes"][:3]])
    for label, res in zip(LABELS, out["results"]):
        z = res["zoneAxis"]
        print(f"{label:10s} template {res['templateIndex']:3d}  "
              f"to truth {family_angle(z, TRUTH[label[0]]):5.1f}°  "
              f"to 001/101/111 {family_angle(z, (0, 0, 1)):4.1f}/"
              f"{family_angle(z, (1, 0, 1)):4.1f}/{family_angle(z, (1, 1, 1)):4.1f}°  "
              f"reliability {res['reliability']:.2f}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "build":
        build()
    elif len(sys.argv) == 3 and sys.argv[1] == "score":
        score(sys.argv[2])
    else:
        sys.exit(__doc__)
