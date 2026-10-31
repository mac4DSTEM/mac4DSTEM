"""A 40x40 CoM field whose 0.1-degree refinement is decided below Float32 resolution.

py4DSTEM f050d207 objective (the curl of _solve_for_center_of_mass_relative_rotation, transcribed, float64) on the
float32 field; the planted angle is scanned upward from 37.20 degrees until the float64 and the Float32 rule disagree
(here the two best fine angles differ by 7.6e-8 relative, under one Float32 ulp), with the one
later in the app's iteration order (lower py4DSTEM angle) the smaller in float64 but equal in float32.
Writes the field (app layout, interleaved [cx, cy], row-major) to argv[1] and prints the reference:
python rotation_float_tie.py float-tie-40x40.f32 gives planted 37.256835, py4DSTEM 41.1 (float64), Float rule 41.2.
"""
import json, sys
import numpy as np

W = H = 40
rng = np.random.default_rng(20261031)
noise_c = rng.normal(0, 1, (H, W))
noise_r = rng.normal(0, 1, (H, W))


def field(theta_deg, amp=1.0, sd=0.6):
    y, x = np.mgrid[0:H, 0:W].astype(np.float64)
    gx = np.cos(x / 6) * np.cos(y / 5) / 6
    gy = -np.sin(x / 6) * np.sin(y / 5) / 5
    t = np.deg2rad(theta_deg)
    cx = amp * (np.cos(t) * gx - np.sin(t) * gy) + sd * noise_c * 0.1
    cy = amp * (np.sin(t) * gx + np.cos(t) * gy) + sd * noise_r * 0.1
    return cx.astype(np.float32), cy.astype(np.float32)


def curl_curve(com_x, com_y, angles):
    com_x = com_x.astype(np.float64); com_y = com_y.astype(np.float64)
    a = np.deg2rad(np.asarray(angles, dtype=np.float64))[:, None, None]
    res = []
    for X, Y in ((com_x, com_y), (com_y, com_x)):
        mx = np.cos(a) * X[None] - np.sin(a) * Y[None]
        my = np.sin(a) * X[None] + np.cos(a) * Y[None]
        gxy = mx[:, 1:-1, 2:] - mx[:, 1:-1, :-2]
        gyx = my[:, 2:, 1:-1] - my[:, :-2, 1:-1]
        res.append(np.mean(np.abs(gyx - gxy), axis=(-2, -1)))
    return res


def solve(theta):
    cx, cy = field(theta)
    com_x, com_y = cy, cx  # file-faithful: py4DSTEM com_x is the app's cy
    grid = np.arange(-89.0, 90.0, 1.0)
    c, ct = curl_curve(com_x, com_y, grid)
    i, it = int(np.argmin(c)), int(np.argmin(ct))
    transpose = not (c[i] <= ct[it])
    g = float(grid[it if transpose else i])
    gv = float(ct[it] if transpose else c[i])
    # app order: app angles ascending = py4DSTEM angles descending
    fine_py = [-(-g - 1 + k * 0.1) for k in range(21)]
    fc, fct = curl_curve(com_x, com_y, fine_py)
    cur = fct if transpose else fc
    b64, v64 = g, gv
    for d, v in zip(fine_py, cur):
        if v < v64: b64, v64 = d, v
    b32, v32 = g, np.float32(gv)
    for d, v in zip(fine_py, cur.astype(np.float32)):
        if v < v32: b32, v32 = d, v
    return dict(cx=cx, cy=cy, grid=g, transpose=transpose, b64=round(b64, 6), b32=round(b32, 6), fine=fine_py, cur=cur)


# scan the planted angle near a fine midpoint and keep the first that splits the two rules
best = None
for theta in np.linspace(37.20, 37.30, 20001):
    r = solve(theta)
    if r["b64"] != r["b32"]:
        best = (theta, r)
        break
if best is None:
    print("no split found"); sys.exit(1)
theta, r = best
k = sorted(range(21), key=lambda j: r["cur"][j])[:3]
out = np.empty((H, W, 2), dtype=np.float32)
out[..., 0] = r["cx"]; out[..., 1] = r["cy"]
out.tofile(sys.argv[1])
fullfine = np.round(np.arange(-89.0, 90.0001, 0.1), 6)
c, ct = curl_curve(r["cy"], r["cx"], fullfine)
cc = ct if r["transpose"] else c
print(json.dumps(dict(planted=float(theta), grid=r["grid"], transpose=r["transpose"], py4dstem_f64_refined=r["b64"],
                      float_rule=r["b32"], py4dstem_fullfine=float(fullfine[int(np.argmin(cc))]),
                      best3=[(round(r["fine"][j], 6), float(r["cur"][j])) for j in k])))
