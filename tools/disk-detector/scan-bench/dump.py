#!/usr/bin/env python
"""dump.py — the scan-bench inputs (detector env). Two modes; both write cube.f32, probe.f32, meta.json into --out.

(1) BULLSEYE (unchanged): every stride-th position of the bullseye cube as an (ny, nx) scan of RAW h5 frames — no
    crop: the 256-px Core ML frame covers this cube's native 250 px in one window (C7, 2026-09-08) — plus the
    probe on a canvas of the same size, its own centre landing on BULLSEYE_CENTRE (simulate.py's fixed crop centre
    for this cube), so `probe_centre_row/col` in meta.json is one coordinate frame for both files.
      dump.py --bullseye <h5> --ingredients <npz> --out <dir> [--stride 4]

(2) GENERIC (2026-09-30): any 4D h5 cube, no ingredients file.
      dump.py --h5 <file> --dataset <path> --out <dir> [--stride N] [--max-positions N]
    Every stride-th position (if the strided scan still exceeds --max-positions the stride is raised until it
    fits). The probe is BUILT FROM THE DATA, by this rule, and is a bench probe for comparing compute units on
    IDENTICAL inputs — it is NOT the app's probe and no calibration claim rests on it:
      mean pattern over the dumped positions; centre_0 = argmax of its 5-px box mean; R_0 = simulate.probe_radius of
      the mean pattern zeroed outside a window of min(qy,qx)/4 px about centre_0; then twice: zero the mean pattern
      outside 1.6 x R about the centre, centre = intensity centroid of what is left, R = simulate.probe_radius of it.
      The probe canvas is the mean pattern zeroed outside 1.6 x R (final) about the final centre, at the detector's own size.
    meta.json carries qy, qx (and `size` when the detector is square, as before), so the Swift side takes a
    non-square detector; old dumps with only `size` still read."""
import argparse, json, os, sys
import numpy as np, h5py
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm

BULLSEYE_CENTRE = (124.76, 124.74)  # simulate.py's own crop centre for calibrationData_bullseyeProbe.h5
DATASET = "4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"
SETTINGS = dict(sigmaCC=2, subpixel="poly", minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, maxNumPeaks=70)

def disk_within(mean, centre, R, factor=1.6):
    rr, cc = np.indices(mean.shape, dtype=np.float64)
    return np.where(np.hypot(rr - centre[0], cc - centre[1]) <= factor * R, mean, 0.0), (rr, cc)

def build_probe(mean):
    """The generic-mode bench probe rule (module docstring). Returns canvas, (row, col), radius."""
    k = np.ones(5) / 5  # separable 5-px box mean
    sm_ = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 0, mean)
    sm_ = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 1, sm_)
    c = tuple(float(v) for v in np.unravel_index(np.argmax(sm_), mean.shape))
    win, _ = disk_within(mean, c, min(mean.shape) / 4, factor=1.0)
    R = sm.probe_radius(win, c)
    for _ in range(2):
        masked, (rr, cc) = disk_within(mean, c, R)
        s = masked.sum(); assert s > 0, "empty central disk"
        c = (float((masked * rr).sum() / s), float((masked * cc).sum() / s))
        masked, _ = disk_within(mean, c, R)
        R = sm.probe_radius(masked, c)
    canvas, _ = disk_within(mean, c, R)
    return canvas, c, R

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True); ap.add_argument("--stride", type=int, default=None)
ap.add_argument("--bullseye"); ap.add_argument("--ingredients")
ap.add_argument("--h5"); ap.add_argument("--dataset"); ap.add_argument("--max-positions", type=int, default=None)
a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)

if a.bullseye:
    assert a.ingredients, "--bullseye needs --ingredients"
    stride = a.stride or 4
    ing = np.load(a.ingredients); probe, c = ing["bullseye_probe"].astype(np.float64), tuple(float(v) for v in ing["bullseye_centre"])
    R = sm.probe_radius(probe, c)
    with h5py.File(a.bullseye, "r") as f:
        d = f[DATASET]
        size = int(d.shape[2]); assert d.shape[2] == d.shape[3], d.shape
        ys, xs = range(0, d.shape[0], stride), range(0, d.shape[1], stride)
        cube = np.zeros((len(ys), len(xs), size, size), np.float32)
        for i, ry in enumerate(ys):
            for j, rx in enumerate(xs):
                cube[i, j] = d[ry, rx]
    # the (smaller) probe array embedded in a canvas of the frame size, its centre on BULLSEYE_CENTRE
    probe_canvas = np.zeros((size, size), np.float64)
    r0, c0 = int(round(BULLSEYE_CENTRE[0] - c[0])), int(round(BULLSEYE_CENTRE[1] - c[1]))
    probe_canvas[r0:r0 + probe.shape[0], c0:c0 + probe.shape[1]] = probe
    meta = dict(ny=len(ys), nx=len(xs), qy=size, qx=size, size=size, stride=stride, probe_centre_row=BULLSEYE_CENTRE[0], probe_centre_col=BULLSEYE_CENTRE[1],
                probe_radius=float(R), cube=a.bullseye, settings=SETTINGS)
else:
    assert a.h5 and a.dataset, "give --bullseye/--ingredients or --h5/--dataset"
    stride = a.stride or 1
    with h5py.File(a.h5, "r") as f:
        d = f[a.dataset]; assert d.ndim == 4, d.shape
        if a.max_positions:
            while len(range(0, d.shape[0], stride)) * len(range(0, d.shape[1], stride)) > a.max_positions: stride += 1
        cube = np.ascontiguousarray(d[::stride, ::stride]).astype(np.float32)
    ny, nx, qy, qx = cube.shape
    mean = cube.reshape(-1, qy, qx).astype(np.float64).mean(axis=0)
    probe_canvas, (pr, pc), R = build_probe(mean)
    meta = dict(ny=ny, nx=nx, qy=qy, qx=qx, stride=stride, probe_centre_row=pr, probe_centre_col=pc, probe_radius=float(R), cube=a.h5,
                dataset=a.dataset, probe_rule="mean pattern zeroed outside 1.6 x central-disk radius, centroid centre (dump.py docstring); bench probe only",
                settings=SETTINGS)
    if qy == qx: meta["size"] = qy
cube.tofile(os.path.join(a.out, "cube.f32")); probe_canvas.astype(np.float32).tofile(os.path.join(a.out, "probe.f32"))
json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1); print("dumped", cube.shape, "stride", stride, "->", a.out,
      "| probe centre (%.2f, %.2f) radius %.1f" % (meta["probe_centre_row"], meta["probe_centre_col"], meta["probe_radius"]))
