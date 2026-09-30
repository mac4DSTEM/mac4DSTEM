#!/usr/bin/env python3
"""Compare the app's single-slice ptychography with py4DSTEM's on the same cube (diagnostic, never a gate).

  python compare_ptycho.py --app <app-out-dir> --py <py-out-dir> [--name label] [--json out.json]

  <app-out-dir>: the probe's `--out` directory (run.sh <cube> ptycho gd ... --out <dir>) holding app_ptycho_<gd|dmap>_objectPhase.npy
                 and app_ptycho_<gd|dmap>.json (error history).
  <py-out-dir> : reference_ptycho.py's `--out` directory (object_phase.npy, error_history.json, meta.json).

The metrics are the ones docs/archive/v4/parallax-ptycho-graphene-2026-09-30/compare_ptycho.json carries, stated here so they can
be re-derived:
  * common crop: both phase maps centre-cropped to the smaller shape, then 64 px trimmed on every side
    (`pearson_no_registration`: Pearson of the two flattened crops, no shift applied);
  * registration: the translation of the app map onto py4DSTEM's by subpixel phase cross-correlation (skimage, 1/20 px), the app
    map shifted by it (cubic spline), both cropped to the region valid after the shift (`pearson_after_registration`);
  * `rms_diff_offset_removed_rad`: RMS of (app - mean(app)) - (py - mean(py)) over that region;
  * the supplementary pair: the same two numbers after a Gaussian low-pass of sigma 4 px (1.25 A at 0.3125 A/px).
Error histories are compared per iteration (relative difference to py4DSTEM's).
"""
import argparse
import glob
import json
import pathlib
import sys

import numpy as np
from scipy import ndimage
from skimage.registration import phase_cross_correlation

TRIM = 64
SIGMA_PX = 4.0


def center_crop(array, shape):
    top = (array.shape[0] - shape[0]) // 2
    left = (array.shape[1] - shape[1]) // 2
    return array[top:top + shape[0], left:left + shape[1]]


def pearson(a, b):
    a = a.astype(np.float64).ravel() - a.mean()
    b = b.astype(np.float64).ravel() - b.mean()
    denominator = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / denominator) if denominator > 0 else float("nan")


def rms_difference(a, b):
    difference = (a - a.mean()) - (b - b.mean())
    return float(np.sqrt((difference ** 2).mean()))


def compare(app_phase, py_phase):
    shape = (min(app_phase.shape[0], py_phase.shape[0]), min(app_phase.shape[1], py_phase.shape[1]))
    app = center_crop(app_phase, shape).astype(np.float64)
    py = center_crop(py_phase, shape).astype(np.float64)
    a = app[TRIM:-TRIM, TRIM:-TRIM]
    p = py[TRIM:-TRIM, TRIM:-TRIM]
    result = {"app_shape": list(app_phase.shape), "py_shape": list(py_phase.shape),
              "app_phase_std": float(np.std(a)), "py_phase_std": float(np.std(p)),
              "pearson_no_registration_centred_common_crop_trim64": pearson(a, p)}
    # translation that moves the app map onto py4DSTEM's (phase_cross_correlation(reference, moving) returns the shift to apply
    # to `moving`)
    shift, _, _ = phase_cross_correlation(p, a, upsample_factor=20, normalization=None)
    result["registration_shift_rowcol_px(app->py)"] = [float(shift[0]), float(shift[1])]
    moved = ndimage.shift(a, shift, order=3, mode="nearest")
    margin = int(np.ceil(np.abs(shift).max())) + 2
    am = moved[margin:-margin, margin:-margin]
    pm = p[margin:-margin, margin:-margin]
    result["compared_shape"] = list(am.shape)
    result["pearson_after_registration"] = pearson(am, pm)
    result["rms_diff_offset_removed_rad"] = rms_difference(am, pm)
    result["rms_app_offset_removed"] = float(np.std(am))
    result["rms_py_offset_removed"] = float(np.std(pm))
    low_a = ndimage.gaussian_filter(am, SIGMA_PX)
    low_p = ndimage.gaussian_filter(pm, SIGMA_PX)
    result["SUPPLEMENTARY_pearson_after_registration_gaussian_sigma4px_lowpass"] = pearson(low_a, low_p)
    result["SUPPLEMENTARY_rms_diff_lowpass_rad"] = rms_difference(low_a, low_p)
    return result


def error_history(app_dir, method):
    path = pathlib.Path(app_dir) / f"app_ptycho_{method}.json"
    return [float(v) for v in json.loads(path.read_text())["errorHistory"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True)
    parser.add_argument("--py", required=True)
    parser.add_argument("--method", default="gd")
    parser.add_argument("--name", default="")
    parser.add_argument("--json", default="")
    args = parser.parse_args()
    app_path = glob.glob(str(pathlib.Path(args.app) / f"app_ptycho_{args.method}_objectPhase.npy"))
    if not app_path:
        sys.exit(f"no app_ptycho_{args.method}_objectPhase.npy in {args.app}")
    app_phase = np.load(app_path[0])
    py_phase = np.load(pathlib.Path(args.py) / "object_phase.npy")
    result = {"name": args.name, "app": args.app, "py": args.py}
    result.update(compare(app_phase, py_phase))
    app_errors = error_history(args.app, args.method)
    py_errors = [float(v) for v in json.loads((pathlib.Path(args.py) / "error_history.json").read_text())]
    result["app_errors"] = app_errors
    result["py_errors"] = py_errors
    if len(app_errors) == len(py_errors):
        relative = [abs(a - p) / p for a, p in zip(app_errors, py_errors)]
        result["error_relative_difference_per_iteration"] = relative
        result["error_relative_difference_max"] = max(relative)
    text = json.dumps(result, indent=1)
    if args.json:
        pathlib.Path(args.json).write_text(text)
    keys = ["app_shape", "py_shape", "app_phase_std", "py_phase_std",
            "pearson_no_registration_centred_common_crop_trim64", "registration_shift_rowcol_px(app->py)",
            "pearson_after_registration", "rms_diff_offset_removed_rad", "compared_shape",
            "SUPPLEMENTARY_pearson_after_registration_gaussian_sigma4px_lowpass", "error_relative_difference_max"]
    print(args.name or args.app)
    for key in keys:
        if key in result:
            value = result[key]
            print("  %-70s %s" % (key, ("%.5g" % value) if isinstance(value, float) else value))
    print("  app errors", ["%.6g" % v for v in app_errors])
    print("  py  errors", ["%.6g" % v for v in py_errors])


if __name__ == "__main__":
    main()
