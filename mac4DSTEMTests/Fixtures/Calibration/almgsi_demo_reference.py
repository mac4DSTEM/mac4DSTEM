"""py4DSTEM f050d207 reference numbers for the Al-Mg-Si demo: origin, CoM field, R-Q rotation, probe size.

Run with the py4DSTEM 0.14.19 environment: python almgsi_demo_reference.py AlMgSi_demo.h5 <out-dir> (needs ~4 GB).
Writes <out>/almgsi-demo-com-100x100.f32 (app layout: interleaved [cx, cy] per scan position, row-major over
(file axis 0 = scan row, file axis 1 = scan column); cx along detector file axis 3, cy along file axis 2)
and prints a JSON summary.
"""
import json, sys, time
import numpy as np
import h5py
from scipy.ndimage import gaussian_filter
import py4DSTEM
from py4DSTEM.process.calibration.origin import get_origin, fit_origin
from py4DSTEM.process.calibration.probe import get_probe_size

path, out = sys.argv[1], sys.argv[2]
with h5py.File(path, "r") as f:
    raw = f["4DSTEM_experiment/data/datacubes/datacube_0/data"][...]
data = raw.astype(np.float64)
Rx, Ry, Qx, Qy = data.shape
dc = py4DSTEM.DataCube(data=data)
summary = {"shape": list(data.shape)}

mean_dp = data.mean(axis=(0, 1))
max_dp = data.max(axis=(0, 1))
summary["probe_mean"] = [float(v) for v in get_probe_size(mean_dp)]
summary["probe_max"] = [float(v) for v in get_probe_size(max_dp)]

t = time.time()
qx0, qy0, _ = get_origin(dc)  # r from max pattern, the py4DSTEM default
summary["origin_seconds"] = time.time() - t
qx0_fit, qy0_fit, qx0_res, qy0_res = fit_origin((qx0, qy0), fitfunction="plane")
summary["origin_meas_mean"] = [float(qx0.mean()), float(qy0.mean())]
summary["origin_fit_corners"] = [[float(qx0_fit[i, j]), float(qy0_fit[i, j])] for i, j in [(0, 0), (0, Ry - 1), (Rx - 1, 0), (Rx - 1, Ry - 1)]]
summary["origin_residual_rms"] = [float(np.sqrt((qx0_res ** 2).mean())), float(np.sqrt((qy0_res ** 2).mean()))]
np.save(out + "/origin_meas.npy", np.stack([qx0, qy0]))
np.save(out + "/origin_fit.npy", np.stack([qx0_fit, qy0_fit]))

# Full-pattern centre of mass, float64 (py4DSTEM _calculate_intensities_center_of_mass, no mask), minus the fitted origin.
kx = np.arange(Qx, dtype=np.float64)
ky = np.arange(Qy, dtype=np.float64)
I = data.sum(axis=(-2, -1))
com_x = np.einsum("abij,i->ab", data, kx) / I
com_y = np.einsum("abij,j->ab", data, ky) / I
nx = com_x - qx0_fit
ny = com_y - qy0_fit


def curl_curve(cx_, cy_, angles_deg):
    a = np.deg2rad(np.asarray(angles_deg, dtype=np.float64))[:, None, None]
    out = []
    for X, Y in ((cx_, cy_), (cy_, cx_)):
        mx = np.cos(a) * X[None] - np.sin(a) * Y[None]
        my = np.sin(a) * X[None] + np.cos(a) * Y[None]
        gxy = mx[:, 1:-1, 2:] - mx[:, 1:-1, :-2]
        gyx = my[:, 2:, 1:-1] - my[:, :-2, 1:-1]
        out.append(np.mean(np.abs(gyx - gxy), axis=(-2, -1)))
    return out


grid = np.arange(-89.0, 90.0, 1.0)
c, ct = curl_curve(nx, ny, grid)
i, it = int(np.argmin(c)), int(np.argmin(ct))
transpose = not (c[i] <= ct[it])
best = float(grid[it if transpose else i])
best_val = float(ct[it] if transpose else c[i])
fine = [best - 1 + k * 0.1 for k in range(21)]
fc, fct = curl_curve(nx, ny, fine)
curve = fct if transpose else fc
refined = best
for d, v in zip(fine, curve):
    if v < best_val:
        best_val, refined = float(v), d
summary["f64_grid_deg"] = best
summary["f64_transpose"] = transpose
summary["f64_refined_deg"] = round(refined, 6)
order = np.argsort(curve)
summary["f64_fine_two_best"] = [[round(fine[k], 6), float(curve[k])] for k in order[:2]]
# The old Float rule: the same fine curve rounded to Float32, first strictly smaller wins.
c32 = np.float32(c[i] if not transpose else ct[it])
r32 = best
for d, v in reversed(list(zip(fine, curve.astype(np.float32)))):  # the app walks py4DSTEM angles downward
    if v < c32:
        c32, r32 = v, d
summary["f32_refined_deg"] = round(r32, 6)
fullfine = np.round(np.arange(-89.0, 90.0001, 0.1), 6)
ffc, ffct = curl_curve(nx, ny, fullfine)
summary["f64_fullfine_deg"] = float(fullfine[np.argmin(ffct if transpose else ffc)])

# py4DSTEM itself: DPC.preprocess (float32 inside) with the same origin as force_com_shifts, default 1 deg grid and 0.1 deg grid.
for name, angles in (("dpc_default", None), ("dpc_fine", fullfine)):
    dpc = py4DSTEM.process.phase.DPC(datacube=dc, energy=300e3, verbose=False)
    dpc.preprocess(force_com_shifts=(qx0_fit, qy0_fit), rotation_angles_deg=angles,
                   plot_center_of_mass=False, plot_rotation=False)
    summary[name + "_deg"] = round(float(np.rad2deg(dpc._rotation_best_rad)), 6)
    summary[name + "_transpose"] = bool(dpc._rotation_best_transpose)
dpc = py4DSTEM.process.phase.DPC(datacube=dc, energy=300e3, verbose=False)
dpc.preprocess(rotation_angles_deg=None, plot_center_of_mass=False, plot_rotation=False)
summary["dpc_planefit_deg"] = round(float(np.rad2deg(dpc._rotation_best_rad)), 6)
summary["dpc_planefit_transpose"] = bool(dpc._rotation_best_transpose)

field = np.empty((Rx, Ry, 2), dtype=np.float32)
field[..., 0] = ny  # app cx: along detector file axis 3 (py4DSTEM Qy)
field[..., 1] = nx  # app cy: along detector file axis 2 (py4DSTEM Qx)
field.tofile(out + "/almgsi-demo-com-100x100.f32")
print(json.dumps(summary, indent=1))
