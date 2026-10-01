"""Refuter (2026-10-01): the lane's own DM/GD loop (ref64.py's, verbatim operators) in float64/float32 with the truth scored at
checkpoints — is the DM collapse intrinsic to the single-pass DM_AP (joint probe), a float32 artefact, or cured by a true
projection (nm 0), a fixed probe, or AP (alpha 0)?"""
import sys, pathlib, numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from synth import load, score

def run(d, method, iterations, nm, clamp, dtype, alpha, fix_probe, step=0.5):
    cdt = np.complex128 if dtype == "float64" else np.complex64
    rdt = np.float64 if dtype == "float64" else np.float32
    det = d["probeShape"][0]; canvas = d["objectShape"][0]
    pos = d["_pos"].astype(np.float64); amp = d["_amp"].astype(rdt)
    probe = d["_probe"].astype(cdt); obj = np.ones((canvas, canvas), cdt)
    frac = pos - np.round(pos); cen = np.round(pos).astype(int)
    ky = np.fft.fftfreq(det)[:, None]; kx = np.fft.fftfreq(det)[None, :]; offs = np.fft.fftfreq(det, 1 / det).astype(int)
    ramp = np.exp(-2j * np.pi * (ky[None] * frac[:, 0, None, None] + kx[None] * frac[:, 1, None, None])).astype(cdt)
    rows = (cen[:, 0, None] + offs[None]) % canvas; cols = (cen[:, 1, None] + offs[None]) % canvas
    flat = (rows[:, :, None] * canvas + cols[:, None, :]).ravel()
    total = float((amp.astype(np.float64) ** 2).sum()); exitw = None; out = []
    for it in range(iterations):
        P = np.fft.ifft2(np.fft.fft2(probe)[None] * ramp)
        patches = obj[rows[:, :, None], cols[:, None, :]]
        overlap = P * patches
        if method == "gd":
            F = np.fft.fft2(overlap); err = float(np.sum((amp - np.abs(F)) ** 2)) / total
            E = np.fft.ifft2(amp * np.exp(1j * np.angle(F)) - F)
        else:
            pa, pb, pc = -alpha, 1.0, 1 + alpha; px, pyy = 1 - pa - pb, 1 - pc
            prev = overlap.copy() if exitw is None else exitw
            F = np.fft.fft2(pc * overlap + pyy * prev); err = float(np.sum((amp - np.abs(F)) ** 2)) / total
            E = px * prev + pa * overlap + pb * np.fft.ifft2(amp * np.exp(1j * np.angle(F))); exitw = E
        num = np.zeros(canvas * canvas, cdt); np.add.at(num, flat, (np.conj(P) * E).ravel())
        pn = np.zeros(canvas * canvas, rdt); np.add.at(pn, flat, (np.abs(P) ** 2).ravel())
        num = num.reshape(canvas, canvas); pn = pn.reshape(canvas, canvas)
        pinv = 1 / np.sqrt(1e-16 + ((1 - nm) * pn) ** 2 + (nm * pn.max()) ** 2)
        on = np.sum(np.abs(patches) ** 2, axis=0); oinv = 1 / np.sqrt(1e-16 + ((1 - nm) * on) ** 2 + (nm * on.max()) ** 2)
        pnum = np.sum(np.conj(patches) * E, axis=0)
        if method == "gd":
            obj = obj + step * num * pinv
            if not fix_probe: probe = probe + step * pnum * oinv
        else:
            obj = num * pinv
            if not fix_probe: probe = pnum * oinv
        if clamp: obj = np.minimum(np.abs(obj), 1.0) * np.exp(1j * np.angle(obj))
        if it + 1 in (1, 2, 4, 8, 16, 32, 64):
            s = score(obj, d["_truth"], d["_pos"]); out.append((it + 1, err, s["pearson"], s["rms_rad"]))
    return out

if __name__ == "__main__":
  for fx in sys.argv[1:]:
    d = load(fx)
    for label, kw in [
        ("DM a1 joint nm0.02 f32", dict(method="dm", nm=0.02, dtype="float32", alpha=1.0, fix_probe=0)),
        ("DM a1 joint nm0.02 f64", dict(method="dm", nm=0.02, dtype="float64", alpha=1.0, fix_probe=0)),
        ("DM a1 joint nm0    f64", dict(method="dm", nm=0.0, dtype="float64", alpha=1.0, fix_probe=0)),
        ("DM a1 fixP  nm0    f64", dict(method="dm", nm=0.0, dtype="float64", alpha=1.0, fix_probe=1)),
        ("DM a1 fixP  nm0.02 f64", dict(method="dm", nm=0.02, dtype="float64", alpha=1.0, fix_probe=1)),
        ("AP a0 joint nm0.02 f64", dict(method="dm", nm=0.02, dtype="float64", alpha=0.0, fix_probe=0)),
        ("AP a0 joint nm1    f64", dict(method="dm", nm=1.0, dtype="float64", alpha=0.0, fix_probe=0)),
        ("GD   joint nm1    f64", dict(method="gd", nm=1.0, dtype="float64", alpha=1.0, fix_probe=0)),
    ]:
        rows = run(d, iterations=64, clamp=1, **kw)
        print(pathlib.Path(fx).stem, label, " | ".join("it%d e=%.2e P=%.3f r=%.3f" % r for r in rows), flush=True)
