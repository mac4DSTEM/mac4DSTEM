#!/usr/bin/env python3
"""py4DSTEM single-slice ptychography on the same float32 cube the app's reader produces (diagnostic, never a gate).

  PYTHONPATH=<repo>/References/py4DSTEM-dev python reference_ptycho.py <cube.h5> --out <dir> \
      [--defocus 600] [--c12 M --phi12-deg D] [--rotation-deg auto|X] [--transpose 0|1] \
      [--iterations 8] [--step 0.5] [--norm-min 1] [--semiangle 26.35] [--energy 80e3] [--q 0.025] [--r 5.0] [--method gd|dm]

The pair to tools/parallax-ptycho-real-probe/main.swift (the app's ptycho stage). Settings that make py4DSTEM the SAME algorithm
as the app's single-slice engine (record.md, 2026-09-30): complex object, full batch, no probe-COM pinning, no Fourier/TV/Gaussian
regularisation, no object positivity. What stays different (recorded as DEVIATIONs in PtychographyPreparation.swift): py4DSTEM
fits a per-pattern origin (`fit_function="plane"`), the app shifts every pattern by ONE mean origin.

`--defocus D` is py4DSTEM's `defocus` argument, i.e. ComplexProbe C10 = -D (phase_base_class.py:1806-1825, utils.py set_parameters).
Writes <out>/object_phase.npy (np.angle of object_cropped, float32), <out>/error_history.json, <out>/meta.json.
"""
import argparse
import builtins
import importlib
import json
import pathlib
import sys
import time
import warnings

import numpy as np

# numpy 2.5 refuses float(<1-element ndarray>); the vendored phase modules call it (e.g. parallax.py:1443). Shadow `float`
# inside them (module globals win over builtins); the vendored source is untouched. Older numpy: a no-op.
for _name, _value in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_),
                      ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, _name):
        setattr(np, _name, _value)

repo = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "References/py4DSTEM-dev"))
import h5py
import py4DSTEM

assert "References/py4DSTEM-dev" in py4DSTEM.__file__, py4DSTEM.__file__


def _float(x):
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)


for _module in ("parallax", "singleslice_ptychography", "phase_base_class", "ptychographic_methods",
                "ptychographic_constraints", "utils"):
    setattr(importlib.import_module("py4DSTEM.process.phase." + _module), "float", _float)
warnings.filterwarnings("ignore")

parser = argparse.ArgumentParser()
parser.add_argument("cube")
parser.add_argument("--out", required=True)
parser.add_argument("--dataset", default="ds")
parser.add_argument("--defocus", type=float, default=0.0)
parser.add_argument("--c12", type=float, default=0.0)
parser.add_argument("--phi12-deg", type=float, default=0.0)
parser.add_argument("--rotation-deg", default="auto")
parser.add_argument("--transpose", default="0")
parser.add_argument("--iterations", type=int, default=8)
parser.add_argument("--step", type=float, default=0.5)
parser.add_argument("--norm-min", type=float, default=1.0)
parser.add_argument("--semiangle", type=float, default=26.35)
parser.add_argument("--rolloff", type=float, default=2.0)
parser.add_argument("--energy", type=float, default=80e3)
parser.add_argument("--q", type=float, default=0.025)
parser.add_argument("--r", type=float, default=5.0)
parser.add_argument("--method", choices=["gd", "dm"], default="gd")
parser.add_argument("--scan-crop", type=int, default=0, help="central N x N scan crop (0 = the whole scan)")
parser.add_argument("--object-type", choices=["complex", "potential"], default="complex")
args = parser.parse_args()

out = pathlib.Path(args.out)
out.mkdir(parents=True, exist_ok=True)
with h5py.File(args.cube, "r") as handle:
    data = np.asarray(handle[args.dataset], dtype=np.float32)
if args.scan_crop > 0:
    top = (data.shape[0] - args.scan_crop) // 2
    left = (data.shape[1] - args.scan_crop) // 2
    data = np.ascontiguousarray(data[top:top + args.scan_crop, left:left + args.scan_crop])
print("cube", data.shape, data.dtype, flush=True)
dataset = py4DSTEM.DataCube(data)
dataset.calibration.set_Q_pixel_size(args.q)
dataset.calibration.set_Q_pixel_units("A^-1")
dataset.calibration.set_R_pixel_size(args.r)
dataset.calibration.set_R_pixel_units("A")

polar = {}
if args.c12 != 0.0:
    polar = {"C12": args.c12, "phi12": float(np.deg2rad(args.phi12_deg))}
ptycho = py4DSTEM.process.phase.SingleslicePtychography(
    energy=args.energy, datacube=dataset, semiangle_cutoff=args.semiangle, rolloff=args.rolloff,
    defocus=args.defocus, polar_parameters=polar, object_type=args.object_type,
    device="cpu", verbose=True,
)
started = time.time()
rotation = None if args.rotation_deg == "auto" else float(args.rotation_deg)
transpose = None if args.rotation_deg == "auto" else (args.transpose == "1")
ptycho = ptycho.preprocess(
    plot_center_of_mass=False, plot_rotation=False, plot_probe_overlaps=False,
    force_com_rotation=rotation, force_com_transpose=transpose,
)
print("preprocess s: %.1f" % (time.time() - started), flush=True)
found_rotation = float(np.rad2deg(ptycho._rotation_best_rad)) if hasattr(ptycho, "_rotation_best_rad") else None
found_transpose = bool(ptycho._rotation_best_transpose) if hasattr(ptycho, "_rotation_best_transpose") else None
print("COM rotation (deg):", found_rotation, " transpose:", found_transpose, flush=True)
started = time.time()
ptycho = ptycho.reconstruct(
    num_iter=args.iterations,
    reconstruction_method="gradient-descent" if args.method == "gd" else "DM_AP",
    reconstruction_parameter=1.0,
    step_size=args.step, normalization_min=args.norm_min,
    max_batch_size=None, seed_random=None,
    fix_probe_com=False, fix_probe=False,
    butterworth_filter=False, gaussian_filter=False, tv_denoise=False,
    object_positivity=False, fix_potential_baseline=False,
    store_iterations=False, progress_bar=False,
)
print("reconstruct s: %.1f" % (time.time() - started), flush=True)
phase = np.angle(ptycho.object_cropped) if args.object_type == "complex" else np.asarray(ptycho.object_cropped)
np.save(out / "object_phase.npy", np.asarray(phase, dtype=np.float32))
errors = [float(e) for e in ptycho.error_iterations]
(out / "error_history.json").write_text(json.dumps(errors))
(out / "meta.json").write_text(json.dumps({
    "cube": args.cube, "defocus": args.defocus, "c12": args.c12, "phi12_deg": args.phi12_deg,
    "rotation_deg_forced": rotation, "transpose_forced": transpose,
    "com_rotation_deg_found": found_rotation, "com_transpose_found": found_transpose,
    "iterations": args.iterations, "step": args.step, "norm_min": args.norm_min,
    "semiangle_mrad": args.semiangle, "rolloff_mrad": args.rolloff, "method": args.method,
    "object_type": args.object_type, "object_shape": list(np.asarray(phase).shape),
    "phase_min": float(np.min(phase)), "phase_max": float(np.max(phase)), "phase_std": float(np.std(phase)),
    "py4dstem": py4DSTEM.__version__,
}, indent=1))
print("errors:", errors)
print("phase range %.4f .. %.4f, std %.4f, shape %s" % (np.min(phase), np.max(phase), np.std(phase), np.asarray(phase).shape))
