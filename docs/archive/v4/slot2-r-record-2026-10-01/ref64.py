#!/usr/bin/env python3
# Paths: REPO = the repo; fixtures fx/*.json from `synth.py make`; run from the lane directory.
"""Float64 numpy re-derivation of ONE/TWO GD (or DM) iterations on a synth.py fixture — the arbiter when the app and py4DSTEM differ.
   python ref64.py fx/df400-s1.json --method gd --iterations 2 --norm-min 1 --clamp 1 --app out/app-gd-c1-df400.json --py out2/py-same-gd-df400.json"""
import argparse, json, pathlib, sys
import numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from synth import load, crop_bounds

p = argparse.ArgumentParser(); p.add_argument("fixture"); p.add_argument("--method", default="gd"); p.add_argument("--iterations", type=int, default=2)
p.add_argument("--norm-min", type=float, default=1.0); p.add_argument("--clamp", type=int, default=1); p.add_argument("--step", type=float, default=0.5)
p.add_argument("--alpha", type=float, default=1.0); p.add_argument("--app", default=""); p.add_argument("--py", default=""); p.add_argument("--dtype", default="float64"); p.add_argument("--mask-eps", type=float, default=0.0); p.add_argument("--fix-probe", type=int, default=0); p.add_argument("--save", default="")
a = p.parse_args()
d = load(a.fixture)
cdt = np.complex128 if a.dtype == "float64" else np.complex64
rdt = np.float64 if a.dtype == "float64" else np.float32
N = d["scanShape"][0]; det = d["probeShape"][0]; canvas = d["objectShape"][0]
pos = d["_pos"].astype(np.float64); amp = d["_amp"].astype(rdt)
probe = d["_probe"].astype(cdt); obj = np.ones((canvas, canvas), cdt)
frac = pos - np.round(pos); cen = np.round(pos).astype(int)
ky = np.fft.fftfreq(det)[:, None]; kx = np.fft.fftfreq(det)[None, :]; offs = np.fft.fftfreq(det, 1 / det).astype(int)
ramp = np.exp(-2j * np.pi * (ky[None] * frac[:, 0, None, None] + kx[None] * frac[:, 1, None, None])).astype(cdt)
rows = (cen[:, 0, None] + offs[None]) % canvas; cols = (cen[:, 1, None] + offs[None]) % canvas
flat = (rows[:, :, None] * canvas + cols[:, None, :]).ravel()
total = float((amp.astype(np.float64) ** 2).sum())
exitw = None
r0, r1, c0, c1 = crop_bounds(d["_pos"])
app = json.loads(pathlib.Path(a.app).read_text()) if a.app else None
py = json.loads(pathlib.Path(a.py).read_text()) if a.py else None
def cp(src, k):
    for c in src["checkpoints"]:
        if c["iterations"] == k:
            return (np.asarray(c["real"]) + 1j * np.asarray(c["imag"])).reshape(canvas, canvas)
for it in range(a.iterations):
    P = np.fft.ifft2(np.fft.fft2(probe)[None] * ramp)
    patches = obj[rows[:, :, None], cols[:, None, :]]
    overlap = P * patches
    if a.method == "gd":
        F = np.fft.fft2(overlap); err = float(np.sum((amp - np.abs(F)) ** 2)) / total
        ph = np.angle(F)
        if a.mask_eps > 0: ph = np.where(np.abs(F) < a.mask_eps * np.abs(F).max(axis=(1, 2), keepdims=True), 0.0, ph)
        E = np.fft.ifft2(amp * np.exp(1j * ph) - F)
    else:
        pa, pb, pc = -a.alpha, 1.0, 1 + a.alpha; px, pyy = 1 - pa - pb, 1 - pc
        prev = overlap.copy() if exitw is None else exitw
        F = np.fft.fft2(pc * overlap + pyy * prev); err = float(np.sum((amp - np.abs(F)) ** 2)) / total
        E = px * prev + pa * overlap + pb * np.fft.ifft2(amp * np.exp(1j * np.angle(F))); exitw = E
    num = np.zeros(canvas * canvas, cdt); np.add.at(num, flat, (np.conj(P) * E).ravel())
    pn = np.zeros(canvas * canvas, rdt); np.add.at(pn, flat, (np.abs(P) ** 2).ravel())
    num = num.reshape(canvas, canvas); pn = pn.reshape(canvas, canvas)
    pinv = 1 / np.sqrt(1e-16 + ((1 - a.norm_min) * pn) ** 2 + (a.norm_min * pn.max()) ** 2)
    on = np.sum(np.abs(patches) ** 2, axis=0); oinv = 1 / np.sqrt(1e-16 + ((1 - a.norm_min) * on) ** 2 + (a.norm_min * on.max()) ** 2)
    pnum = np.sum(np.conj(patches) * E, axis=0)
    if a.method == "gd":
        obj = obj + a.step * num * pinv
        if not a.fix_probe: probe = probe + a.step * pnum * oinv
    else:
        obj = num * pinv
        if not a.fix_probe: probe = pnum * oinv
    if a.clamp:
        obj = np.minimum(np.abs(obj), 1.0) * np.exp(1j * np.angle(obj))
    line = "it %d (%s): error %.6g" % (it + 1, a.dtype, err)
    for name, src in (("app", app), ("py", py)):
        if src is not None and (o := cp(src, it + 1)) is not None:
            dd = (obj - o)[r0:r1, c0:c1]
            line += "; vs %s max |d| %.3e (pad region %.3e)" % (name, np.abs(dd).max(), np.abs(obj - o).max())
    print(line)
if a.save: np.save(a.save, obj)
