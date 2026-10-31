"""py4DSTEM f050d207 get_origin + fit_origin on NoisyOriginTests' cubes (the same generator, drawn here in Python).

Run with the py4DSTEM 0.14.19 environment: python noisy_origin_reference.py
"""
import math
import numpy as np
import py4DSTEM
from py4DSTEM.process.calibration.origin import get_origin, fit_origin
from py4DSTEM.process.calibration.probe import get_probe_size

S, Q = 24, 64
M64 = (1 << 64) - 1


def truth(r, c):
    return 31.7 + 0.04 * c - 0.02 * r, 32.2 - 0.03 * c + 0.05 * r


def cube(peak, background, seed):
    state = [(seed + 0x9E3779B97F4A7C15) & M64]

    def uniform():
        s = state[0]
        s ^= s >> 12; s ^= (s << 25) & M64; s ^= s >> 27
        state[0] = s
        return (((s * 2685821657736338717) & M64) >> 11) / 9007199254740992.0

    def poisson(lam):
        if lam <= 0:
            return 0.0
        if lam < 30:
            l = math.exp(-lam); k = 0.0; p = 1.0
            while True:
                k += 1; p *= uniform()
                if not p > l:
                    break
            return k - 1
        u1 = max(uniform(), 1e-300); u2 = uniform()
        z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        return max(0.0, round(lam + z * math.sqrt(lam)))

    out = np.zeros((S, S, Q, Q), dtype=np.float64)
    yy, xx = np.mgrid[0:Q, 0:Q].astype(np.float64)
    for r in range(S):
        for c in range(S):
            tx, ty = truth(r, c)
            edge = np.clip(4.5 - np.hypot(xx - tx, yy - ty), 0, 1)
            lam = peak * edge + background
            out[r, c] = [[poisson(v) for v in row] for row in lam]
    return out


for peak, bg in [(2000.0, 0.0), (50.0, 0.5), (10.0, 0.5), (3.0, 0.5), (1.0, 0.2)]:
    data = cube(peak, bg, 7)
    dc = py4DSTEM.DataCube(data=data)
    qx0, qy0, _ = get_origin(dc)  # qx0 along detector axis 2 = row (the app's y)
    fx, fy, rx, ry = fit_origin((qx0, qy0), fitfunction="plane")
    tx = np.array([[truth(r, c)[0] for c in range(S)] for r in range(S)])
    ty = np.array([[truth(r, c)[1] for c in range(S)] for r in range(S)])
    meas = math.sqrt(np.mean((qy0 - tx) ** 2 + (qx0 - ty) ** 2))
    fitted = float(np.max(np.hypot(fy - tx, fx - ty)))
    rms = math.sqrt(np.mean(rx ** 2 + ry ** 2))
    print(f"py4DSTEM peak {peak} bg {bg}: max r {get_probe_size(data.max(axis=(0, 1)))[0]:.4f} "
          f"mean r {get_probe_size(data.mean(axis=(0, 1)))[0]:.4f} measured rms err {meas:.4f} fitted max err {fitted:.4f} "
          f"rms residual {rms:.4f} mean fitted ({fy.mean():.3f}, {fx.mean():.3f}) truth mean ({tx.mean():.3f}, {ty.mean():.3f})")
