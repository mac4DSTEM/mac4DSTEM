#!/usr/bin/env python
"""dump.py — the scan-bench inputs (detector env): every stride-th position of the bullseye cube as a
(ny, nx) scan, cropped to 128 px about the probe centre, plus the net's three-channel inputs for the
same patterns, so main.swift times the app's classical scan path and the exported Core AI asset on
IDENTICAL patterns. Writes cube.f32, probe.f32, inputs.f16, meta.json into --out (gitignored).

--size (2026-09-07, tiling): the default (sm.S, 128) is this cube's fixed pattern crop, unchanged.
Any other size — the owner's bullseye cube is natively 250 px, `sm.S` on this cube uses a crop
centred on BULLSEYE_CENTRE that sits inside it (simulate.py's own fixed crop centre for this cube) —
skips the pattern crop (the raw h5 frame is dumped as-is) and does not write inputs.f16: main.swift's
learned section calls LearnedDiskDetector.detectAll(cube:...) directly, which tiles a >128 px detector
itself and needs no precomputed net inputs. The probe is still placed by a crop, into a canvas of
--size aligned so the probe's own centre lands on BULLSEYE_CENTRE — the same point a >128 px cube's
patterns are dumped around uncropped, so `probe_centre_row/col` in meta.json is one coordinate frame
for both files."""
import argparse, json, os, sys
import numpy as np, h5py
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm

BULLSEYE_CENTRE = (124.76, 124.74)  # simulate.py's own crop centre for calibrationData_bullseyeProbe.h5

ap = argparse.ArgumentParser()
ap.add_argument("--bullseye", required=True); ap.add_argument("--ingredients", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--stride", type=int, default=2)
ap.add_argument("--size", type=int, default=sm.S, help="pattern size to dump (default: sm.S, the fixed 128 px crop); "
                 "any other value skips the pattern crop (raw h5 frame, e.g. this cube's native 250 px) and omits inputs.f16")
a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
ing = np.load(a.ingredients); probe, c = ing["bullseye_probe"].astype(np.float64), tuple(float(v) for v in ing["bullseye_centre"])
k = sm.flat_kernel(probe, c); R = sm.probe_radius(probe, c)
native = a.size == sm.S
if native:
    probe_canvas, probe_centre = probe, c
else:
    # embed the (smaller) probe array into a --size canvas so probe.f32 matches cube.f32's
    # pattern size, its own centre landing on BULLSEYE_CENTRE — the same frame the uncropped
    # patterns are already in, so probe_centre_row/col below is one coordinate system for both.
    probe_canvas = np.zeros((a.size, a.size), np.float64)
    r0, c0 = int(round(BULLSEYE_CENTRE[0] - c[0])), int(round(BULLSEYE_CENTRE[1] - c[1]))
    probe_canvas[r0:r0 + probe.shape[0], c0:c0 + probe.shape[1]] = probe
    probe_centre = BULLSEYE_CENTRE
with h5py.File(a.bullseye, "r") as f:
    d = f["4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"]
    ys, xs = range(0, d.shape[0], a.stride), range(0, d.shape[1], a.stride)
    cube = np.zeros((len(ys), len(xs), a.size, a.size), np.float32)
    inputs = np.zeros((len(ys) * len(xs), 3, sm.S, sm.S), np.float16) if native else None
    for i, ry in enumerate(ys):
        for j, rx in enumerate(xs):
            raw = d[ry, rx].astype(np.float64)
            p = sm.centred_crop(raw, BULLSEYE_CENTRE, sm.S)[0] if native else raw
            cube[i, j] = p
            if inputs is not None:
                inputs[i * len(xs) + j] = sm.model_inputs(p, probe, sm.cross_correlation(p, k))
cube.tofile(os.path.join(a.out, "cube.f32")); probe_canvas.astype(np.float32).tofile(os.path.join(a.out, "probe.f32"))
if inputs is not None: inputs.tofile(os.path.join(a.out, "inputs.f16"))
meta = dict(ny=len(ys), nx=len(xs), size=a.size, stride=a.stride, probe_centre_row=probe_centre[0], probe_centre_col=probe_centre[1],
            probe_radius=float(R), cube=a.bullseye,
            settings=dict(sigmaCC=2, subpixel="poly", minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, maxNumPeaks=70))
json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1); print("dumped", cube.shape, "->", a.out)
