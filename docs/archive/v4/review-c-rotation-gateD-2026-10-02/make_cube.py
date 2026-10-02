#!/usr/bin/env python3
"""Lane C b1 Gate D (2026-10-02): one synthetic weak-phase cube with a planted detector rotation, run through py4DSTEM's
DPC rotation solve and its Parallax fit; the same cube is written to cube.h5 for the app-side harness (main.swift).
Built after tools/parallax-ptycho-real-probe/convention_check.py (same probe, object and shims).
  python make_cube.py <rot_deg> <defocus_A> <out.h5>
"""
import sys, pathlib, warnings
import numpy as np
for n, v in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_),
             ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, n):
        setattr(np, n, v)
repo = pathlib.Path("/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM")
sys.path.insert(0, str(repo / "References/py4DSTEM-dev"))
import py4DSTEM
assert "References/py4DSTEM-dev" in py4DSTEM.__file__
from py4DSTEM.process.phase.utils import ComplexProbe
import builtins, importlib
def _float(x):
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)
for _m in ("parallax", "dpc", "phase_base_class", "utils"):
    setattr(importlib.import_module("py4DSTEM.process.phase." + _m), "float", _float)
from scipy.ndimage import gaussian_filter, rotate
import h5py
warnings.filterwarnings("ignore")

rot_deg = float(sys.argv[1]); defocus = float(sys.argv[2]); out = sys.argv[3]
energy = 80e3; N = 48; dr = 0.5; q = 1.0 / (N * dr); semiangle = 20.0; step_px = 3; scan = 40
rng = np.random.default_rng(7)
size = scan * step_px + N
obj_phase = gaussian_filter(rng.standard_normal((size, size)), 3.0)
obj_phase *= 0.25 / obj_phase.std()
obj = np.exp(1j * obj_phase)
probe = ComplexProbe(energy=energy, gpts=(N, N), sampling=(dr, dr), semiangle_cutoff=semiangle,
                     rolloff=2.0, defocus=defocus).build()._array
probe_c = np.fft.fftshift(probe)
data = np.zeros((scan, scan, N, N), dtype=np.float32)
for i in range(scan):
    for j in range(scan):
        patch = obj[i*step_px:i*step_px+N, j*step_px:j*step_px+N]
        pattern = np.fft.fftshift(np.abs(np.fft.fft2(probe_c * patch)) ** 2)
        # planted detector rotation: scipy rotate in the (Qx, Qy) = (axis 0, axis 1) plane about the array centre
        data[i, j] = rotate(pattern, rot_deg, axes=(0, 1), reshape=False, order=1, mode="constant") if rot_deg else pattern
data /= data.sum((2, 3)).mean()
with h5py.File(out, "w") as f:
    f.create_dataset("datacube", data=data)

def cube():
    dc = py4DSTEM.DataCube(data.copy())
    dc.calibration.set_Q_pixel_size(q); dc.calibration.set_Q_pixel_units("A^-1")
    dc.calibration.set_R_pixel_size(step_px * dr); dc.calibration.set_R_pixel_units("A")
    return dc
from py4DSTEM.process.phase import DPC, Parallax
dpc = DPC(datacube=cube(), energy=energy, verbose=False).preprocess(plot_center_of_mass=None, plot_rotation=False)
dpc_div = DPC(datacube=cube(), energy=energy, verbose=False).preprocess(plot_center_of_mass=None, plot_rotation=False, maximize_divergence=True)
par = Parallax(datacube=cube(), energy=energy, verbose=False, object_padding_px=(16, 16))
par = par.preprocess(plot_average_bf=False, edge_blend=8, threshold_intensity=0.5)
par = par.reconstruct(max_alignment_bin=None, plot_aligned_bf=False, plot_convergence=False,
                      progress_bar=False, cross_correlation_upsample_factor=8)
par = par.aberration_fit(plot_BF_shifts_comparison=False, plot_CTF_comparison=False)
print("PLANTED rot_deg=%g (scipy.ndimage.rotate on (Qx,Qy)) defocus=%g A; q %.6f 1/A per px; R %.3f A per px; %g kV"
      % (rot_deg, defocus, q, step_px * dr, energy / 1e3))
print("PY4DSTEM DPC curl:       rotation %.3f deg transpose %s" % (np.rad2deg(dpc._rotation_best_rad), dpc._rotation_best_transpose))
print("PY4DSTEM DPC divergence: rotation %.3f deg transpose %s" % (np.rad2deg(dpc_div._rotation_best_rad), dpc_div._rotation_best_transpose))
print("PY4DSTEM Parallax: rotation_Q_to_R %.3f deg transpose %s C1 %.2f C12a %.2f C12b %.2f"
      % (np.rad2deg(par.rotation_Q_to_R_rads), par.transpose, par.aberrations_C1, par.aberrations_C12a, par.aberrations_C12b))
print("QPIX %.8f RPIX %.6f KV %g" % (q, step_px * dr, energy / 1e3))
