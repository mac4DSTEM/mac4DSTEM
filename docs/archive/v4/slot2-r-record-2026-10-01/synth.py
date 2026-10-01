#!/usr/bin/env python3
# Paths: REPO = the repo; fixtures fx/*.json from `synth.py make`; run from the lane directory.
"""R3 exploration: a synthetic single-slice cube with a KNOWN object and a DEFOCUSED probe; py4DSTEM's own class run on it; scoring
against truth (global phase offset + subpixel shift, then Pearson and offset-removed RMS on the position-bounds crop).

  python synth.py make  --seed 1 --defocus 400 --out fx/df400-s1.json           # fixture (float32 inputs, truth, settings)
  python synth.py py    fx/df400-s1.json --variant same|own --method gd|dm --iterations 32 --out out.json
  python synth.py score fx/df400-s1.json dump.json          # score the Swift dump tool's checkpoints with the same scorer
"""
import argparse, builtins, importlib, json, pathlib, sys, time, warnings
import numpy as np

REPO = pathlib.Path("/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM")
for _n, _v in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_), ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, _n):
        setattr(np, _n, _v)
sys.path.insert(0, str(REPO / "References/py4DSTEM-dev"))
warnings.filterwarnings("ignore")


def _float(x):
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)


def import_py4dstem():
    import py4DSTEM
    assert "References/py4DSTEM-dev" in py4DSTEM.__file__
    for m in ("parallax", "singleslice_ptychography", "phase_base_class", "ptychographic_methods", "ptychographic_constraints", "utils"):
        setattr(importlib.import_module("py4DSTEM.process.phase." + m), "float", _float)
    return py4DSTEM


def fmt(arr):
    """float32-exact JSON number list (9 significant digits round-trip float32)."""
    return "[" + ",".join(np.char.mod("%.9g", np.asarray(arr, dtype=np.float64).ravel())) + "]"


# ---------------------------------------------------------------- fixture
def make(args):
    py4DSTEM = import_py4dstem()
    from py4DSTEM.process.phase.utils import ComplexProbe
    rng = np.random.default_rng(args.seed)
    N, det, q = args.scan, args.det, args.q
    sampling = 1.0 / (q * det)
    step_px = args.step / sampling
    pad = det / 2
    i, j = np.mgrid[:N, :N]
    pos = np.stack([(i * step_px + pad).ravel(), (j * step_px + pad).ravel()], -1)
    canvas = int(np.round(pos.max() + pad))
    assert abs((N - 1) * step_px - round((N - 1) * step_px)) < 1e-9, "scan extent must be an integer number of px (no recentring)"
    yy, xx = np.mgrid[:canvas, :canvas]
    phase = np.zeros((canvas, canvas))
    lo, hi = pad - 6, canvas - pad + 6
    sigma_px = args.sigma / sampling
    for _ in range(args.atoms):
        cy, cx = rng.uniform(lo, hi, 2)
        amp = rng.uniform(0.2, 0.6)
        phase += amp * np.exp(-((yy - cy) ** 2 + (xx - cx) ** 2) / (2 * sigma_px ** 2))
    truth = np.exp(1j * phase)
    probe_unit = np.asarray(ComplexProbe(energy=args.energy, gpts=(det, det), sampling=(sampling, sampling),
                                         semiangle_cutoff=args.semiangle, rolloff=args.rolloff,
                                         parameters={"defocus": args.defocus}).build()._array, dtype=np.complex128)
    probe_sim = probe_unit * 1000.0
    frac = pos - np.round(pos)
    centers = np.round(pos).astype(int)
    ky = np.fft.fftfreq(det)[:, None]
    kx = np.fft.fftfreq(det)[None, :]
    offs = np.fft.fftfreq(det, 1 / det).astype(int)
    P = np.fft.fft2(probe_sim)
    intens = np.empty((N * N, det, det))
    for p in range(N * N):
        shifted = np.fft.ifft2(P * np.exp(-2j * np.pi * (ky * frac[p, 0] + kx * frac[p, 1])))
        rows = (centers[p, 0] + offs) % canvas
        cols = (centers[p, 1] + offs) % canvas
        intens[p] = np.abs(np.fft.fft2(shifted * truth[rows[:, None], cols[None, :]])) ** 2
    if args.noise > 0:   # Poisson at `noise` electrons per pattern total
        scale = args.noise / intens.mean(axis=(1, 2), keepdims=True).sum()
        intens = rng.poisson(intens * args.noise / intens.sum(axis=(1, 2), keepdims=True)) / (args.noise / intens.sum(axis=(1, 2), keepdims=True))
    intens32 = intens.astype(np.float32)
    amplitudes = np.sqrt(intens32).astype(np.float32)
    mean_intensity = float(intens32.astype(np.float64).sum() / (N * N))
    probe_scaled = (probe_unit * np.sqrt(mean_intensity / np.sum(np.abs(np.fft.fft2(probe_unit)) ** 2))).astype(np.complex64)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        f.write('{"name":%s,"seed":%d,"defocusAngstrom":%r,"energyEV":%r,"semiangleMrad":%r,"rolloffMrad":%r,'
                '"qSamplingInvAngstrom":%r,"scanSamplingAngstrom":%r,"objectSamplingAngstrom":%r,"noiseElectrons":%r,'
                '"scanShape":[%d,%d],"probeShape":[%d,%d],"objectShape":[%d,%d],"meanIntensity":%r,'
                % (json.dumps(out.stem), args.seed, args.defocus, args.energy, args.semiangle, args.rolloff, q, args.step, sampling,
                   args.noise, N, N, det, det, canvas, canvas, mean_intensity))
        f.write('"positions":' + fmt(pos.astype(np.float32)) + ',')
        f.write('"amplitudes":' + fmt(amplitudes) + ',')
        f.write('"probeReal":' + fmt(probe_scaled.real) + ',"probeImag":' + fmt(probe_scaled.imag) + ',')
        f.write('"truthReal":' + fmt(truth.real) + ',"truthImag":' + fmt(truth.imag) + ',')
        f.write('"truthPhase":' + fmt(phase) + '}\n')
    print("wrote", out, "canvas", canvas, "step_px", step_px, "mean_intensity", mean_intensity,
          "truth phase std on crop %.4f" % phase[int(pad):int(pad) + round((N - 1) * step_px), int(pad):int(pad) + round((N - 1) * step_px)].std())


def load(path):
    d = json.loads(pathlib.Path(path).read_text())
    N = d["scanShape"][0]; det = d["probeShape"][0]; canvas = d["objectShape"][0]
    d["_pos"] = np.asarray(d["positions"], dtype=np.float32).reshape(-1, 2)
    d["_amp"] = np.asarray(d["amplitudes"], dtype=np.float32).reshape(N * N, det, det)
    d["_probe"] = (np.asarray(d["probeReal"], dtype=np.float32) + 1j * np.asarray(d["probeImag"], dtype=np.float32)).astype(np.complex64).reshape(det, det)
    d["_truth"] = (np.asarray(d["truthReal"]) + 1j * np.asarray(d["truthImag"])).reshape(canvas, canvas)
    return d


# ---------------------------------------------------------------- scoring
def crop_bounds(pos):
    r0, c0 = np.floor(pos.min(0)).astype(int)
    r1, c1 = np.ceil(pos.max(0)).astype(int)
    return r0, r1, c0, c1


def pearson(a, b):
    a = a.ravel() - a.mean(); b = b.ravel() - b.mean()
    den = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / den) if den > 0 else float("nan")


def score(obj, truth, pos):
    """Register (subpixel shift of the truth onto the object, global phase offset), then Pearson and offset-removed RMS on the crop."""
    obj = np.asarray(obj, dtype=np.complex128)
    r0, r1, c0, c1 = crop_bounds(pos)
    canvas = obj.shape
    win = np.zeros(canvas); win[r0:r1, c0:c1] = 1
    a = np.angle(obj); t = np.angle(truth)
    aw = (a - a[r0:r1, c0:c1].mean()) * win
    tw = (t - t[r0:r1, c0:c1].mean()) * win
    cc = np.fft.ifft2(np.fft.fft2(aw) * np.conj(np.fft.fft2(tw))).real
    k = np.unravel_index(np.argmax(cc), cc.shape)
    shift = []
    for axis, kk in enumerate(k):
        n = canvas[axis]
        idx = [tuple((kk + dlt) % n if ax == axis else k[ax] for ax in range(2)) for dlt in (-1, 0, 1)]
        ym, y0, yp = (cc[i] for i in idx)
        den = ym - 2 * y0 + yp
        sub = 0.5 * (ym - yp) / den if den != 0 else 0.0
        s = kk + sub
        if s > n / 2: s -= n
        shift.append(float(s))
    ky = np.fft.fftfreq(canvas[0])[:, None]; kx = np.fft.fftfreq(canvas[1])[None, :]
    ts = np.fft.ifft2(np.fft.fft2(truth) * np.exp(-2j * np.pi * (ky * shift[0] + kx * shift[1])))
    oc = obj[r0:r1, c0:c1]; tc = ts[r0:r1, c0:c1]
    phi0 = np.angle(np.sum(oc * np.conj(tc)))
    d = np.angle(oc * np.conj(tc) * np.exp(-1j * phi0))
    rms = float(np.sqrt(np.mean((d - d.mean()) ** 2)))
    pr = pearson(np.angle(oc * np.exp(-1j * phi0)), np.angle(tc))
    amp_rms = float(np.sqrt(np.mean((np.abs(oc) - np.abs(tc)) ** 2)))
    return {"shift_rowcol_px": shift, "phase_offset_rad": float(phi0), "pearson": pr, "rms_rad": rms, "amplitude_rms": amp_rms,
            "truth_phase_std": float(np.angle(tc).std()), "object_phase_std": float(np.angle(oc).std())}


# ---------------------------------------------------------------- py4DSTEM
def run_py(args):
    py4DSTEM = import_py4dstem()
    d = load(args.fixture)
    N = d["scanShape"][0]; det = d["probeShape"][0]
    intens = (d["_amp"].astype(np.float32) ** 2).reshape(N, N, det, det)
    same = args.variant == "same"
    if not same:
        intens = np.fft.fftshift(intens, axes=(-2, -1))
    if args.perturb > 0:
        rng = np.random.default_rng(99)
        intens = (intens * (1 + args.perturb * rng.standard_normal(intens.shape))).astype(np.float32)
    dataset = py4DSTEM.DataCube(np.ascontiguousarray(intens))
    dataset.calibration.set_Q_pixel_size(d["qSamplingInvAngstrom"]); dataset.calibration.set_Q_pixel_units("A^-1")
    dataset.calibration.set_R_pixel_size(d["scanSamplingAngstrom"]); dataset.calibration.set_R_pixel_units("A")
    defocus = d["defocusAngstrom"] * (args.probe_sign)
    ptycho = py4DSTEM.process.phase.SingleslicePtychography(
        energy=d["energyEV"], datacube=dataset, semiangle_cutoff=d["semiangleMrad"], rolloff=d["rolloffMrad"],
        defocus=defocus, object_type="complex", device="cpu", verbose=False,
        initial_probe_guess=(d["_probe"] if (same and args.probe_sign == 1) else None))
    t0 = time.time()
    ptycho = ptycho.preprocess(
        plot_center_of_mass=False, plot_rotation=False, plot_probe_overlaps=False,
        force_com_rotation=0.0, force_com_transpose=False,
        force_com_shifts=((np.zeros((N, N), np.float32), np.zeros((N, N), np.float32)) if same else None),
        shifting_interpolation_order=(1 if same else 3), center_positions_in_fov=(not same), fit_function="plane")
    checks = {
        "positions_max_abs_delta_px": float(np.abs(np.asarray(ptycho._positions_px) - d["_pos"]).max()),
        "amplitudes_max_abs_delta": float(np.abs(np.asarray(ptycho._amplitudes) - d["_amp"]).max()),
        "amplitudes_max": float(d["_amp"].max()),
        "probe_max_abs_delta": float(np.abs(np.asarray(ptycho._probe) - d["_probe"]).max()),
        "probe_max_abs": float(np.abs(d["_probe"]).max()),
        "object_shape": list(ptycho._object.shape),
        "mean_diffraction_intensity": float(ptycho._mean_diffraction_intensity),
        "com_fitted_mean_rowcol": [float(np.mean(ptycho._com_fitted_x)), float(np.mean(ptycho._com_fitted_y))],
        "com_fitted_ptp_rowcol": [float(np.ptp(ptycho._com_fitted_x)), float(np.ptp(ptycho._com_fitted_y))],
    }
    ptycho = ptycho.reconstruct(
        num_iter=args.iterations, reconstruction_method=("gradient-descent" if args.method == "gd" else "DM_AP"),
        reconstruction_parameter=args.alpha, step_size=args.step, normalization_min=args.norm_min, max_batch_size=None,
        fix_probe_com=False, fix_probe=bool(args.fix_probe), butterworth_filter=False, gaussian_filter=False, tv_denoise=False,
        object_positivity=False, fix_potential_baseline=False, store_iterations=True, progress_bar=False)
    seconds = time.time() - t0
    errors = [float(e) for e in ptycho.error_iterations]
    per_iter = [score(o, d["_truth"], d["_pos"]) for o in ptycho.object_iterations]
    final = np.asarray(ptycho._object)
    cps = [{"iterations": k, "real": np.asarray(ptycho.object_iterations[k - 1]).real.astype(np.float32).ravel().tolist(),
            "imag": np.asarray(ptycho.object_iterations[k - 1]).imag.astype(np.float32).ravel().tolist()}
           for k in (1, 2, 4, 8, 16, 32) if k <= len(ptycho.object_iterations)]
    out = {"fixture": args.fixture, "variant": args.variant, "method": args.method, "iterations": args.iterations,
           "alpha": args.alpha, "step": args.step, "norm_min": args.norm_min, "probe_sign": args.probe_sign, "perturb": args.perturb, "fix_probe": args.fix_probe,
           "seconds": seconds, "checks": checks, "errors": errors, "truth_per_iteration": per_iter, "checkpoints": cps,
           "finalReal": final.real.astype(np.float32).ravel().tolist(), "finalImag": final.imag.astype(np.float32).ravel().tolist()}
    pathlib.Path(args.out).write_text(json.dumps(out))
    print("py4DSTEM %s %s %s: %.1fs; checks %s" % (args.variant, args.method, pathlib.Path(args.fixture).stem, seconds, json.dumps(checks)))
    print("  errors", ["%.6g" % e for e in errors])
    for it in (0, 1, 3, 7, 15, 31):
        if it < len(per_iter):
            s = per_iter[it]
            print("  it %2d: pearson %.4f rms %.4f shift %s amp_rms %.4f" % (it + 1, s["pearson"], s["rms_rad"], ["%.3f" % v for v in s["shift_rowcol_px"]], s["amplitude_rms"]))


def score_dump(args):
    d = load(args.fixture)
    dump = json.loads(pathlib.Path(args.dump).read_text())
    canvas = d["objectShape"][0]
    print("app dump", args.dump, "method", dump.get("method"), "clamp", dump.get("constrainObjectAmplitude"), "probe", dump.get("probe"))
    print("  errors", ["%.6g" % e for e in dump["errors"]])
    results = {}
    for cp in dump["checkpoints"]:
        obj = (np.asarray(cp["real"]) + 1j * np.asarray(cp["imag"])).reshape(canvas, canvas)
        s = score(obj, d["_truth"], d["_pos"])
        results[cp["iterations"]] = s
        print("  it %2d: pearson %.4f rms %.4f shift %s amp_rms %.4f" % (cp["iterations"], s["pearson"], s["rms_rad"], ["%.3f" % v for v in s["shift_rowcol_px"]], s["amplitude_rms"]))
    if args.py:
        py = json.loads(pathlib.Path(args.py).read_text())
        rel = [abs(a - p) / p for a, p in zip(dump["errors"], py["errors"])]
        print("  vs py4DSTEM %s: error rel diff per it" % args.py, ["%.2e" % r for r in rel], "max %.3e" % max(rel))
        final = (np.asarray(py["finalReal"]) + 1j * np.asarray(py["finalImag"])).reshape(canvas, canvas)
        r0, r1, c0, c1 = crop_bounds(d["_pos"])
        pycp = {c["iterations"]: c for c in py.get("checkpoints", [])}
        for cp in dump["checkpoints"]:
            if cp["iterations"] in pycp:
                o = (np.asarray(cp["real"]) + 1j * np.asarray(cp["imag"])).reshape(canvas, canvas)[r0:r1, c0:c1]
                q = (np.asarray(pycp[cp["iterations"]]["real"]) + 1j * np.asarray(pycp[cp["iterations"]]["imag"])).reshape(canvas, canvas)[r0:r1, c0:c1]
                print("  it %2d app vs py: max |dphase| %.3e rad, max |d amp| %.3e, max |d complex| %.3e (max |py| %.3f)" % (
                    cp["iterations"], np.abs(np.angle(o * np.conj(q))).max(), np.abs(np.abs(o) - np.abs(q)).max(), np.abs(o - q).max(), np.abs(q).max()))
        last = dump["checkpoints"][-1]
        obj = (np.asarray(last["real"]) + 1j * np.asarray(last["imag"])).reshape(canvas, canvas)
        if last["iterations"] == py["iterations"]:
            r0, r1, c0, c1 = crop_bounds(d["_pos"])
            dphi = np.angle(obj[r0:r1, c0:c1] * np.conj(final[r0:r1, c0:c1]))
            print("  final object vs py4DSTEM: max |dphase| %.3e rad, max |d amplitude| %.3e" % (np.abs(dphi).max(), np.abs(np.abs(obj) - np.abs(final))[r0:r1, c0:c1].max()))
    if args.out:
        pathlib.Path(args.out).write_text(json.dumps({"dump": args.dump, "py": args.py, "truth": results}, indent=1))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make"); m.add_argument("--seed", type=int, default=1); m.add_argument("--defocus", type=float, default=400.0)
    m.add_argument("--out", required=True); m.add_argument("--scan", type=int, default=16); m.add_argument("--det", type=int, default=64)
    m.add_argument("--q", type=float, default=0.025); m.add_argument("--step", type=float, default=2.0); m.add_argument("--energy", type=float, default=80e3)
    m.add_argument("--semiangle", type=float, default=20.0); m.add_argument("--rolloff", type=float, default=2.0)
    m.add_argument("--atoms", type=int, default=40); m.add_argument("--sigma", type=float, default=0.8); m.add_argument("--noise", type=float, default=0.0)
    r = sub.add_parser("py"); r.add_argument("fixture"); r.add_argument("--variant", choices=["same", "own"], default="same")
    r.add_argument("--method", choices=["gd", "dm"], default="gd"); r.add_argument("--iterations", type=int, default=32)
    r.add_argument("--alpha", type=float, default=1.0); r.add_argument("--step", type=float, default=0.5); r.add_argument("--norm-min", type=float, default=1.0)
    r.add_argument("--probe-sign", type=float, default=1.0); r.add_argument("--perturb", type=float, default=0.0); r.add_argument("--out", required=True)
    r.add_argument("--fix-probe", type=int, default=0)
    s = sub.add_parser("score"); s.add_argument("fixture"); s.add_argument("dump"); s.add_argument("--py", default=""); s.add_argument("--out", default="")
    a = p.parse_args()
    {"make": make, "py": run_py, "score": score_dump}[a.cmd](a)
