#!/usr/bin/env python
"""dump.py — the scan-bench inputs (detector env): every stride-th position of the bullseye cube as an
(ny, nx) scan of RAW h5 frames — no crop: the 256-px Core ML frame covers this cube's native 250 px in
one window (C7, 2026-09-08) — plus the probe on a canvas of the same size, its own centre landing on
BULLSEYE_CENTRE (simulate.py's fixed crop centre for this cube), so `probe_centre_row/col` in
meta.json is one coordinate frame for both files. main.swift times the app's classical scan path and
the learned path on IDENTICAL patterns. Writes cube.f32, probe.f32, meta.json into --out (gitignored)."""
import argparse, json, os, sys
import numpy as np, h5py
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm

BULLSEYE_CENTRE = (124.76, 124.74)  # simulate.py's own crop centre for calibrationData_bullseyeProbe.h5
DATASET = "4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"

ap = argparse.ArgumentParser()
ap.add_argument("--bullseye", required=True); ap.add_argument("--ingredients", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--stride", type=int, default=4)
a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
ing = np.load(a.ingredients); probe, c = ing["bullseye_probe"].astype(np.float64), tuple(float(v) for v in ing["bullseye_centre"])
R = sm.probe_radius(probe, c)
with h5py.File(a.bullseye, "r") as f:
    d = f[DATASET]
    size = int(d.shape[2]); assert d.shape[2] == d.shape[3], d.shape
    ys, xs = range(0, d.shape[0], a.stride), range(0, d.shape[1], a.stride)
    cube = np.zeros((len(ys), len(xs), size, size), np.float32)
    for i, ry in enumerate(ys):
        for j, rx in enumerate(xs):
            cube[i, j] = d[ry, rx]
# the (smaller) probe array embedded in a canvas of the frame size, its centre on BULLSEYE_CENTRE
probe_canvas = np.zeros((size, size), np.float64)
r0, c0 = int(round(BULLSEYE_CENTRE[0] - c[0])), int(round(BULLSEYE_CENTRE[1] - c[1]))
probe_canvas[r0:r0 + probe.shape[0], c0:c0 + probe.shape[1]] = probe
cube.tofile(os.path.join(a.out, "cube.f32")); probe_canvas.astype(np.float32).tofile(os.path.join(a.out, "probe.f32"))
meta = dict(ny=len(ys), nx=len(xs), size=size, stride=a.stride, probe_centre_row=BULLSEYE_CENTRE[0], probe_centre_col=BULLSEYE_CENTRE[1],
            probe_radius=float(R), cube=a.bullseye,
            settings=dict(sigmaCC=2, subpixel="poly", minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, maxNumPeaks=70))
json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1); print("dumped", cube.shape, "->", a.out)
