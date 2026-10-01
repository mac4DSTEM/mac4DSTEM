#!/usr/bin/env python3
"""R3 (2026-10-01): a synthetic single-slice cube with a KNOWN object and a DEFOCUSED probe, and py4DSTEM's own
SingleslicePtychography run on it, so the Swift harness can score the app's gradient descent and difference map against the
truth AND against py4DSTEM on bit-identical inputs. Prints one JSON document to stdout (run.sh -> $WORK/truth.json).

The cube: 16 x 16 scan at 2.0 A (3.2 object px), 64 x 64 detector, q 0.025 1/A per px (0.625 A object sampling), 80 keV, semiangle
20 mrad, rolloff 2 mrad, canvas 112 x 112, pure-phase object of 40 Gaussian "atoms" (0.2-0.6 rad, sigma 0.8 A), noiseless, the
forward model both engines assume (fractional Fourier shift of the probe, periodic object patch, |fft2|^2). Three fixtures: defocus
200 / 400 / 600 A, seed 1. The scan extent is an integer number of pixels so py4DSTEM's `center_positions_in_fov` is a no-op and its
positions equal the app's; py4DSTEM gets the corner-centred amplitudes with forced zero origin shifts (order-1 shift = identity),
rotation 0, no transpose, and the SAME float32 probe as `initial_probe_guess` (it is not rescaled). The float32 inputs round-trip
JSON exactly (%.9g).

What py4DSTEM does that the app exposes as an option: `_object_constraints` (ptychographic_constraints.py) applies
`_object_threshold_constraint` - |object| <= 1 - on EVERY iteration for a complex object; the app's `constrainObjectAmplitude`
must be ON for parity (the harness turns it on; off, the GD error histories differ by 27 %: lane R report, 2026-10-01).

Scoring (the same in main.swift): subpixel shift of the truth onto the object by FFT cross-correlation of the mean-removed phase
maps on the position-bounds crop (parabolic peak), global phase offset = arg sum(obj conj(truth)) on the crop, then Pearson of the
phases and the RMS of the offset-removed wrapped phase difference on the crop.
"""
import builtins, importlib, json, pathlib, sys, warnings
import numpy as np

repo = pathlib.Path(__file__).resolve().parents[2]
constraints = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/ptychographic_constraints.py").read_text()
methods = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/ptychographic_methods.py").read_text()
for contract in (
    'if self._object_type == "complex":\n            current_object = self._object_threshold_constraint(',
    "amplitude = xp.minimum(xp.abs(current_object), 1.0)",
):
    if contract not in constraints:
        raise SystemExit(f"py4DSTEM object-threshold contract changed: {contract}")
for contract in (
    "if exit_waves is None:\n            exit_waves = overlap.copy()",
    "self._exit_waves = None",
):
    if contract not in methods:
        raise SystemExit(f"py4DSTEM DM exit-wave contract changed: {contract}")

for _n, _v in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_), ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, _n):      # numpy 2 removed the aliases the vendored py4DSTEM still imports
        setattr(np, _n, _v)
sys.path.insert(0, str(repo / "References/py4DSTEM-dev"))
warnings.filterwarnings("ignore")
import py4DSTEM  # noqa: E402
from py4DSTEM.process.phase.utils import ComplexProbe  # noqa: E402
assert "References/py4DSTEM-dev" in py4DSTEM.__file__, py4DSTEM.__file__


def _float(x):   # numpy 2.5 refuses float(<1-element ndarray>); the vendored phase modules call it
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)


for _m in ("singleslice_ptychography", "phase_base_class", "ptychographic_methods", "ptychographic_constraints", "utils"):
    setattr(importlib.import_module("py4DSTEM.process.phase." + _m), "float", _float)

ENERGY, SEMIANGLE, ROLLOFF, Q, STEP_A, SCAN, DET, ATOMS, SIGMA_A = 80e3, 20.0, 2.0, 0.025, 2.0, 16, 64, 40, 0.8
FIXTURES = [(1, 200.0), (1, 400.0), (1, 600.0)]
GD_ITERATIONS, DM_ITERATIONS = 32, 8
DM_NORMALIZATION_MINIMA = (1.0, 0.02)


def fmt(arr):
    """float32-exact JSON numbers (9 significant digits round-trip float32). Values below float32's normal range (1e-37) become 0:
    the harness decodes every array as [Float] and Foundation refuses a number Float cannot hold ("not representable"), which the
    truth's Gaussian tails (sin of exp(-700) ~ 1e-300) are."""
    values = np.asarray(arr, dtype=np.float64).ravel().copy()
    values[np.abs(values) < 1e-37] = 0.0
    return [builtins.float(v) for v in np.char.mod("%.9g", values)]


def crop_bounds(pos):
    r0, c0 = np.floor(pos.min(0)).astype(int)
    r1, c1 = np.ceil(pos.max(0)).astype(int)
    return r0, r1, c0, c1


def pearson(a, b):
    a = a.ravel() - a.mean(); b = b.ravel() - b.mean()
    den = np.sqrt((a * a).sum() * (b * b).sum())
    return builtins.float((a * b).sum() / den) if den > 0 else builtins.float("nan")


def score(obj, truth, pos):
    obj = np.asarray(obj, dtype=np.complex128)
    r0, r1, c0, c1 = crop_bounds(pos)
    canvas = obj.shape
    win = np.zeros(canvas); win[r0:r1, c0:c1] = 1
    a = np.angle(obj); t = np.angle(truth)
    cc = np.fft.ifft2(np.fft.fft2((a - a[r0:r1, c0:c1].mean()) * win) * np.conj(np.fft.fft2((t - t[r0:r1, c0:c1].mean()) * win))).real
    k = np.unravel_index(np.argmax(cc), cc.shape)
    shift = []
    for axis, kk in enumerate(k):
        n = canvas[axis]
        idx = [tuple((kk + dlt) % n if ax == axis else k[ax] for ax in range(2)) for dlt in (-1, 0, 1)]
        ym, y0, yp = (cc[i] for i in idx)
        den = ym - 2 * y0 + yp
        s = kk + (0.5 * (ym - yp) / den if den != 0 else 0.0)
        if s > n / 2: s -= n
        shift.append(builtins.float(s))
    ky = np.fft.fftfreq(canvas[0])[:, None]; kx = np.fft.fftfreq(canvas[1])[None, :]
    ts = np.fft.ifft2(np.fft.fft2(truth) * np.exp(-2j * np.pi * (ky * shift[0] + kx * shift[1])))
    oc = obj[r0:r1, c0:c1]; tc = ts[r0:r1, c0:c1]
    phi0 = np.angle(np.sum(oc * np.conj(tc)))
    d = np.angle(oc * np.conj(tc) * np.exp(-1j * phi0))
    def tidy(x):   # Foundation's JSON reader refuses denormal doubles ("not representable"); a parabolic peak can land on 1e-313
        return 0.0 if abs(x) < 1e-300 else builtins.float(x)
    return {"shiftRow": tidy(shift[0]), "shiftColumn": tidy(shift[1]), "phaseOffset": tidy(phi0),
            "pearson": tidy(pearson(np.angle(oc * np.exp(-1j * phi0)), np.angle(tc))),
            "rms": tidy(np.sqrt(np.mean((d - d.mean()) ** 2)))}


def make(seed, defocus):
    rng = np.random.default_rng(seed)
    sampling = 1.0 / (Q * DET)
    step_px = STEP_A / sampling
    pad = DET / 2
    i, j = np.mgrid[:SCAN, :SCAN]
    pos = np.stack([(i * step_px + pad).ravel(), (j * step_px + pad).ravel()], -1)
    canvas = int(np.round(pos.max() + pad))
    assert abs((SCAN - 1) * step_px - round((SCAN - 1) * step_px)) < 1e-9
    yy, xx = np.mgrid[:canvas, :canvas]
    phase = np.zeros((canvas, canvas))
    lo, hi = pad - 6, canvas - pad + 6
    sigma_px = SIGMA_A / sampling
    for _ in range(ATOMS):
        cy, cx = rng.uniform(lo, hi, 2)
        phase += rng.uniform(0.2, 0.6) * np.exp(-((yy - cy) ** 2 + (xx - cx) ** 2) / (2 * sigma_px ** 2))
    truth = np.exp(1j * phase)
    probe_unit = np.asarray(ComplexProbe(energy=ENERGY, gpts=(DET, DET), sampling=(sampling, sampling), semiangle_cutoff=SEMIANGLE,
                                         rolloff=ROLLOFF, parameters={"defocus": defocus}).build()._array, dtype=np.complex128)
    frac = pos - np.round(pos); centers = np.round(pos).astype(int)
    ky = np.fft.fftfreq(DET)[:, None]; kx = np.fft.fftfreq(DET)[None, :]; offs = np.fft.fftfreq(DET, 1 / DET).astype(int)
    P = np.fft.fft2(probe_unit * 1000.0)
    intens = np.empty((SCAN * SCAN, DET, DET))
    for p in range(SCAN * SCAN):
        shifted = np.fft.ifft2(P * np.exp(-2j * np.pi * (ky * frac[p, 0] + kx * frac[p, 1])))
        rows = (centers[p, 0] + offs) % canvas; cols = (centers[p, 1] + offs) % canvas
        intens[p] = np.abs(np.fft.fft2(shifted * truth[rows[:, None], cols[None, :]])) ** 2
    intens32 = intens.astype(np.float32)
    amplitudes = np.sqrt(intens32).astype(np.float32)
    mean_intensity = builtins.float(intens32.astype(np.float64).sum() / (SCAN * SCAN))
    probe = (probe_unit * np.sqrt(mean_intensity / np.sum(np.abs(np.fft.fft2(probe_unit)) ** 2))).astype(np.complex64)
    return dict(seed=seed, defocusAngstrom=defocus, sampling=sampling, canvas=canvas, pos=pos.astype(np.float32), amplitudes=amplitudes,
                probe=probe, probePristine=probe.copy(), truth=truth, meanIntensity=mean_intensity)


def run_py4dstem(fx, method, iterations, normalization_min):
    intens = (fx["amplitudes"] ** 2).reshape(SCAN, SCAN, DET, DET)
    dataset = py4DSTEM.DataCube(np.ascontiguousarray(intens))
    dataset.calibration.set_Q_pixel_size(Q); dataset.calibration.set_Q_pixel_units("A^-1")
    dataset.calibration.set_R_pixel_size(STEP_A); dataset.calibration.set_R_pixel_units("A")
    # `.copy()`: py4DSTEM keeps `initial_probe_guess` by reference (`xp.asarray(initial_probe, dtype=complex64)` returns the same
    # array) and updates `self._probe` IN PLACE, so without the copy the first run would rewrite the fixture's probe for the next
    # one and for the JSON (found 2026-10-01: the DM runs started from the GD-refined probe and the stored probe was its final one).
    ptycho = py4DSTEM.process.phase.SingleslicePtychography(
        energy=ENERGY, datacube=dataset, semiangle_cutoff=SEMIANGLE, rolloff=ROLLOFF, defocus=fx["defocusAngstrom"],
        object_type="complex", device="cpu", verbose=False, initial_probe_guess=fx["probe"].copy())
    zeros = np.zeros((SCAN, SCAN), np.float32)
    ptycho = ptycho.preprocess(plot_center_of_mass=False, plot_rotation=False, plot_probe_overlaps=False,
                               force_com_rotation=0.0, force_com_transpose=False, force_com_shifts=(zeros, zeros),
                               shifting_interpolation_order=1, center_positions_in_fov=False)
    # the inputs really are the fixture's, bit for bit
    assert np.abs(np.asarray(ptycho._positions_px) - fx["pos"]).max() == 0.0
    assert np.abs(np.asarray(ptycho._amplitudes) - fx["amplitudes"]).max() == 0.0
    assert np.abs(np.asarray(ptycho._probe) - fx["probe"]).max() == 0.0
    assert tuple(ptycho._object.shape) == (fx["canvas"], fx["canvas"])
    ptycho = ptycho.reconstruct(num_iter=iterations, reconstruction_method=("gradient-descent" if method == "gd" else "DM_AP"),
                                reconstruction_parameter=1.0, step_size=0.5, normalization_min=normalization_min, max_batch_size=None,
                                fix_probe_com=False, fix_probe=False, butterworth_filter=False, gaussian_filter=False, tv_denoise=False,
                                object_positivity=False, fix_potential_baseline=False, store_iterations=False, progress_bar=False)
    final = np.asarray(ptycho._object)
    assert np.abs(fx["probe"] - fx["probePristine"]).max() == 0.0, "the fixture's probe was mutated by the run"
    return {"method": method, "iterations": iterations, "normalizationMinimum": normalization_min,
            "errors": [builtins.float(e) for e in ptycho.error_iterations],
            "finalReal": fmt(final.real.astype(np.float32)), "finalImag": fmt(final.imag.astype(np.float32)),
            "truth": score(final, fx["truth"], fx["pos"])}


fixtures = []
for seed, defocus in FIXTURES:
    fx = make(seed, defocus)
    runs = [run_py4dstem(fx, "gd", GD_ITERATIONS, 1.0)] + [run_py4dstem(fx, "dm", DM_ITERATIONS, nm) for nm in DM_NORMALIZATION_MINIMA]
    fixtures.append({
        "name": f"defocus {defocus:g} A, seed {seed}", "seed": seed, "defocusAngstrom": defocus, "energyEV": ENERGY,
        "semiangleMrad": SEMIANGLE, "rolloffMrad": ROLLOFF, "qSamplingInvAngstrom": Q, "scanSamplingAngstrom": STEP_A,
        "objectSamplingAngstrom": fx["sampling"], "scanShape": [SCAN, SCAN], "probeShape": [DET, DET],
        "objectShape": [fx["canvas"], fx["canvas"]], "meanIntensity": fx["meanIntensity"],
        "positions": fmt(fx["pos"]), "amplitudes": fmt(fx["amplitudes"]),
        "probeReal": fmt(fx["probe"].real), "probeImag": fmt(fx["probe"].imag),
        "truthReal": fmt(fx["truth"].real), "truthImag": fmt(fx["truth"].imag),
        "py4dstem": runs,
    })
json.dump({"fixtures": fixtures, "py4dstemVersion": py4DSTEM.__version__}, sys.stdout, separators=(",", ":"))
print()
