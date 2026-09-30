#!/usr/bin/env python3
"""Convention check (diagnostic, never a gate; lane R1, 2026-09-30): what sign and frame does py4DSTEM's Parallax fit report for a probe
that py4DSTEM's own ComplexProbe built?  Synthetic weak-phase cube made FROM `ComplexProbe(...)`, run through the vendored `Parallax`
(References/py4DSTEM-dev), nothing from mac4DSTEM involved.

  PYTHONPATH=<repo>/References/py4DSTEM-dev python convention_check.py <defocus> <C12> <phi12_deg> [rot90 0..3] [C21 phi21_deg C23 phi23_deg]

PREDICTION (written before the first run, 2026-09-30): defocus=+500 (C10=-500) -> Parallax aberrations_C1 ~ +500 and C12a/C12b the
NEGATIVE of ComplexProbe's cartesian (a uniform flip).  REFUTED by the run: C1 came back -508.7 (-509.5 with coma added) and C12a/C12b with ComplexProbe's own
signs (73.9, 58.0 against 76.6, 64.3) - parallax's coefficients ARE ComplexProbe's (py4DSTEM builds `aberrations_dict_polar` with
ComplexProbe's symbols for exactly that), so the defocus a fit implies is -C1. The evidence is py4DSTEM's own forward model
(utils.py:159-160, C10 = -defocus) and this run, not "the tutorials": the gold-on-carbon notebooks use `defocus = -parallax.aberration_C1`,
but phase_retrieval_02 and the three ptycho02_MoS2 notebooks pass +C1 into the reconstruction (while printing -C1 as the "estimated
defocus", about 50 A, where the sign is nearly harmless).
A detector rotated by 180 deg flips the sign of every coefficient (C1 = +509.6, C12a/b = -73.4/-56.8) and the reported rotation folds
back to ~0: the ambiguity lives in (rotation, sign), so the sign is only meaningful beside the rotation the reconstruction uses.
The higher-order (coma) fit of this small synthetic cube is not reliable (C21/C23 came back ~0 or off); only C1, C12a, C12b are claimed.
"""
import sys, pathlib, warnings
import numpy as np
for n, v in [("float_", np.float64), ("int_", np.int64), ("bool_", np.bool_),
             ("object_", np.object_), ("str_", np.str_), ("complex_", np.complex128)]:
    if not hasattr(np, n):
        setattr(np, n, v)
repo = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "References/py4DSTEM-dev"))
import py4DSTEM
assert "References/py4DSTEM-dev" in py4DSTEM.__file__
from py4DSTEM.process.phase.utils import ComplexProbe
import builtins, importlib
# numpy 2.5 refuses float(<1-element ndarray>), which parallax.py and the ptychography modules use
# (e.g. parallax.py:1443). Shadow `float` inside the vendored phase modules; the vendored source is untouched.
def _float(x):
    return builtins.float(np.asarray(x).reshape(-1)[0]) if isinstance(x, np.ndarray) else builtins.float(x)
for _m in ("parallax", "singleslice_ptychography", "phase_base_class", "ptychographic_methods",
           "ptychographic_constraints", "utils"):
    setattr(importlib.import_module("py4DSTEM.process.phase." + _m), "float", _float)
from scipy.ndimage import gaussian_filter

warnings.filterwarnings("ignore")
args = sys.argv[1:]
defocus = float(args[0]); C12 = float(args[1]); phi12 = np.deg2rad(float(args[2]))
rot90 = int(args[3]) if len(args) > 3 else 0
C21 = float(args[4]) if len(args) > 4 else 0.0
phi21 = np.deg2rad(float(args[5])) if len(args) > 5 else 0.0
C23 = float(args[6]) if len(args) > 6 else 0.0
phi23 = np.deg2rad(float(args[7])) if len(args) > 7 else 0.0

energy = 80e3
N = 48                      # detector = probe grid
dr = 0.5                    # probe-grid sampling (A); reciprocal pixel q = 1/(N dr)
q = 1.0 / (N * dr)
semiangle = 20.0            # mrad
step_px = 3                 # scan step in object pixels (1.5 A)
scan = 40
rng = np.random.default_rng(7)
size = scan * step_px + N
obj_phase = gaussian_filter(rng.standard_normal((size, size)), 3.0)
obj_phase *= 0.25 / obj_phase.std()
obj = np.exp(1j * obj_phase)

probe = ComplexProbe(energy=energy, gpts=(N, N), sampling=(dr, dr), semiangle_cutoff=semiangle,
                     rolloff=2.0, defocus=defocus, C12=C12, phi12=phi12,
                     C21=C21, phi21=phi21, C23=C23, phi23=phi23).build()._array
probe_c = np.fft.fftshift(probe)
data = np.zeros((scan, scan, N, N), dtype=np.float32)
for i in range(scan):
    for j in range(scan):
        patch = obj[i*step_px:i*step_px+N, j*step_px:j*step_px+N]
        pattern = np.abs(np.fft.fft2(probe_c * patch)) ** 2
        data[i, j] = np.fft.fftshift(pattern)
data /= data.sum((2, 3)).mean()
if rot90:
    data = np.rot90(data, k=rot90, axes=(2, 3)).copy()

dc = py4DSTEM.DataCube(data)
dc.calibration.set_Q_pixel_size(q)
dc.calibration.set_Q_pixel_units("A^-1")
dc.calibration.set_R_pixel_size(step_px * dr)
dc.calibration.set_R_pixel_units("A")
from py4DSTEM.process.phase import Parallax
par = Parallax(datacube=dc, energy=energy, verbose=False, object_padding_px=(16, 16))
par = par.preprocess(plot_average_bf=False, edge_blend=8, threshold_intensity=0.5)
par = par.reconstruct(max_alignment_bin=None, plot_aligned_bf=False, plot_convergence=False,
                      progress_bar=False, cross_correlation_upsample_factor=8)
par = par.aberration_fit(plot_BF_shifts_comparison=False, plot_CTF_comparison=False)
print("inputs: defocus=%g C12=%g phi12=%g deg rot90=%d C21=%g phi21=%g C23=%g phi23=%g"
      % (defocus, C12, np.rad2deg(phi12), rot90, C21, np.rad2deg(phi21), C23, np.rad2deg(phi23)))
print("ComplexProbe cartesian (C10=-defocus): C12a=%.2f C12b=%.2f  C21a=%.2f C21b=%.2f  C23a=%.2f C23b=%.2f"
      % (C12*np.cos(2*phi12), C12*np.sin(2*phi12), C21*np.cos(phi21), C21*np.sin(phi21),
         C23*np.cos(3*phi23), C23*np.sin(3*phi23)))
print("py4DSTEM Parallax: C1=%.2f C12a=%.2f C12b=%.2f rotation_Q_to_R=%.3f deg transpose=%s"
      % (par.aberrations_C1, par.aberrations_C12a, par.aberrations_C12b,
         np.rad2deg(par.rotation_Q_to_R_rads), par.transpose))
print("fit dict (cartesian, recursive higher-order fit):")
for k, v in sorted(par.aberrations_dict_cartesian.items()):
    print("   %-6s %.2f" % (k, v))
print("polar:", {k: round(float(v), 4) for k, v in par.aberrations_dict_polar.items()})
