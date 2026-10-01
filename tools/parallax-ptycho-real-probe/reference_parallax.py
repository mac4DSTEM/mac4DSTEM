#!/usr/bin/env python3
"""py4DSTEM Parallax on the same float32 cube the app reads (diagnostic, never a gate; lane R4, 2026-10-01).

  PYTHONPATH=<repo>/References/py4DSTEM-dev python reference_parallax.py <cube.h5> --out <dir> [--q 0.025 --r 5.0 --energy 80e3]
      [--padding 32] [--edge-blend 16] [--inject-shifts <npy of app pixel shifts, [N,2] in py4DSTEM's xy_shifts order>]

Pair to main.swift's `align` stage. Writes <out>/py_parallax.json (rotation, C1, C12a/b, every coefficient of the recursive fit with
py4DSTEM's own gradient basis, rms of the fit residual) and <out>/py_shifts.npz (xy_shifts [px], probe_angles [rad], xy_inds,
region_of_interest_shape, recon_BF). With --inject-shifts the measured shifts are replaced by the app's BEFORE aberration_fit, so
py4DSTEM's FITTER runs on the app's MEASUREMENT (the cross-feed that separates "different shifts" from "different fit").
"""
import argparse, builtins, importlib, json, pathlib, sys, warnings
import numpy as np
for _n, _v in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_), ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, _n):
        setattr(np, _n, _v)
repo = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "References/py4DSTEM-dev"))
import h5py, py4DSTEM
assert "References/py4DSTEM-dev" in py4DSTEM.__file__, py4DSTEM.__file__

def _float(x):
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)
for _m in ("parallax", "singleslice_ptychography", "phase_base_class", "ptychographic_methods", "ptychographic_constraints", "utils"):
    setattr(importlib.import_module("py4DSTEM.process.phase." + _m), "float", _float)
warnings.filterwarnings("ignore")

ap = argparse.ArgumentParser()
ap.add_argument("cube"); ap.add_argument("--out", required=True); ap.add_argument("--dataset", default="ds")
ap.add_argument("--q", type=float, default=0.025); ap.add_argument("--r", type=float, default=5.0)
ap.add_argument("--energy", type=float, default=80e3)
ap.add_argument("--padding", type=int, default=32); ap.add_argument("--edge-blend", type=float, default=16.0)
ap.add_argument("--inject-shifts", default=None)
ap.add_argument("--fit-method", default="recursive")
args = ap.parse_args()
out = pathlib.Path(args.out); out.mkdir(parents=True, exist_ok=True)
with h5py.File(args.cube, "r") as h:
    data = np.asarray(h[args.dataset], dtype=np.float32)
dc = py4DSTEM.DataCube(data)
dc.calibration.set_Q_pixel_size(args.q); dc.calibration.set_Q_pixel_units("A^-1")
dc.calibration.set_R_pixel_size(args.r); dc.calibration.set_R_pixel_units("A")
p = py4DSTEM.process.phase.Parallax(energy=args.energy, datacube=dc, object_padding_px=(args.padding, args.padding), verbose=False, device="cpu")
p = p.preprocess(edge_blend=args.edge_blend, plot_average_bf=False)
_flat = np.asarray(p._stack_BF_shifted).ravel()
print("stack_mean (py4DSTEM, float32 pairwise) %.6f | sequential float32 sum / n = %.6f (n=%d)" % (
    float(p._stack_mean), float(np.cumsum(_flat, dtype=np.float32)[-1]) / _flat.size, _flat.size), flush=True)
del _flat
p = p.reconstruct(progress_bar=False, plot_aligned_bf=False, plot_convergence=False)
if args.inject_shifts:
    inj = np.load(args.inject_shifts).astype(np.float32)
    assert inj.shape == p._xy_shifts.shape, (inj.shape, p._xy_shifts.shape)
    p._xy_shifts = inj
p = p.aberration_fit(fit_method=args.fit_method)
res = {"rotation_deg": float(np.rad2deg(p.rotation_Q_to_R_rads)), "C1": float(p.aberrations_C1), "C12a": float(p.aberrations_C12a),
       "C12b": float(p.aberrations_C12b), "mn": p._aberrations_mn.tolist(), "coefs": [float(c) for c in p._aberrations_coefs],
       "dict_polar": {k: float(v) for k, v in p.aberrations_dict_polar.items()}}
(out / "py_parallax.json").write_text(json.dumps(res, indent=1))
np.savez(out / "py_shifts.npz", xy_shifts=np.asarray(p._xy_shifts), probe_angles=np.asarray(p._probe_angles), xy_inds=np.asarray(p._xy_inds),
         roi=np.asarray(p._region_of_interest_shape), scan_sampling=np.asarray(p._scan_sampling),
         recon_BF=np.asarray(p._recon_BF), wavelength=np.asarray(p._wavelength), recip=np.asarray(p._reciprocal_sampling))
print(json.dumps(res, indent=1))
print("recon_BF", p._recon_BF.shape, "xy_shifts", p._xy_shifts.shape)
