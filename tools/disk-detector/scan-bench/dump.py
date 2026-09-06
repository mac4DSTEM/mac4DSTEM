#!/usr/bin/env python
"""dump.py — the scan-bench inputs (detector env): every stride-th position of the bullseye cube as a
(ny, nx) scan, cropped to 128 px about the probe centre, plus the net's three-channel inputs for the
same patterns, so main.swift times the app's classical scan path and the exported Core AI asset on
IDENTICAL patterns. Writes cube.f32, probe.f32, inputs.f16, meta.json into --out (gitignored)."""
import argparse, json, os, sys
import numpy as np, h5py
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm

ap = argparse.ArgumentParser()
ap.add_argument("--bullseye", required=True); ap.add_argument("--ingredients", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--stride", type=int, default=2)
a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
ing = np.load(a.ingredients); probe, c = ing["bullseye_probe"].astype(np.float64), tuple(float(v) for v in ing["bullseye_centre"])
k = sm.flat_kernel(probe, c); R = sm.probe_radius(probe, c)
with h5py.File(a.bullseye, "r") as f:
    d = f["4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"]
    ys, xs = range(0, d.shape[0], a.stride), range(0, d.shape[1], a.stride)
    cube = np.zeros((len(ys), len(xs), sm.S, sm.S), np.float32); inputs = np.zeros((len(ys) * len(xs), 3, sm.S, sm.S), np.float16)
    for i, ry in enumerate(ys):
        for j, rx in enumerate(xs):
            p, _ = sm.centred_crop(d[ry, rx].astype(np.float64), (124.76, 124.74), sm.S)
            cube[i, j] = p; inputs[i * len(xs) + j] = sm.model_inputs(p, probe, sm.cross_correlation(p, k))
cube.tofile(os.path.join(a.out, "cube.f32")); probe.astype(np.float32).tofile(os.path.join(a.out, "probe.f32")); inputs.tofile(os.path.join(a.out, "inputs.f16"))
meta = dict(ny=len(ys), nx=len(xs), size=sm.S, stride=a.stride, probe_centre_row=c[0], probe_centre_col=c[1], probe_radius=float(R), cube=a.bullseye,
            settings=dict(sigmaCC=2, subpixel="poly", minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, maxNumPeaks=70))
json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1); print("dumped", cube.shape, "->", a.out)
