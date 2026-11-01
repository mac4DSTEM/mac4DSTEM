"""py4DSTEM f050d207 get_beamstop_mask + get_origin_friedel + fit_origin on BeamStopOriginTests' planted cube.

The same cube as `BeamStopSource` (the same generator, drawn here in Python). Run with the py4DSTEM 0.14.19
environment: python beam_stop_origin_reference.py
"""
import math
import numpy as np
import py4DSTEM
from py4DSTEM.process.calibration.origin import get_origin_friedel, fit_origin

S, Q = 12, 64
M64 = (1 << 64) - 1
BRAGG = [(14.0, 5.0), (-4.0, 15.0), (11.0, -9.0)]


def truth(r, c):
    return 31.6 + 0.06 * c - 0.03 * r, 32.4 - 0.04 * c + 0.07 * r


def blocked(x, y):
    return math.hypot(x - 32, y - 32) <= 7.5 or (abs(y - 32) <= 2 and x >= 32)


def cube(stop=True, seed=11):
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

    out = np.zeros((S, S, Q, Q), dtype=np.float32)
    for r in range(S):
        for c in range(S):
            tx, ty = truth(r, c)
            for y in range(Q):
                for x in range(Q):
                    if stop and blocked(x, y):
                        continue
                    dx, dy = x - tx, y - ty
                    d = math.hypot(dx, dy)
                    lam = 1 + 3000 * min(1, max(0, 4.5 - d)) + 120 / (1 + (d / 5) * (d / 5))
                    for u, v in BRAGG:
                        lam += 400 * min(1, max(0, 3 - math.hypot(dx - u, dy - v)))
                        lam += 400 * min(1, max(0, 3 - math.hypot(dx + u, dy + v)))
                    out[r, c, y, x] = poisson(lam)
    return out


data = cube()
dc = py4DSTEM.DataCube(data=data)
mask = dc.get_beamstop_mask()
mask = np.asarray(getattr(mask, "data", mask), dtype=bool)
qx0, qy0 = get_origin_friedel(dc, mask=np.logical_not(mask))  # qx0 along detector axis 2 = row (the app's y)
fx, fy, rx, ry = fit_origin((qx0, qy0), fitfunction="plane")
tx = np.array([[truth(r, c)[0] for c in range(S)] for r in range(S)])
ty = np.array([[truth(r, c)[1] for c in range(S)] for r in range(S)])
fitted = float(np.max(np.hypot(fy - tx, fx - ty)))
rms = math.sqrt(np.mean(rx ** 2 + ry ** 2))
meas = math.sqrt(np.mean((qy0 - tx) ** 2 + (qx0 - ty) ** 2))
print(f"py4DSTEM Friedel: masked {mask.sum()} px, measured rms err {meas:.4f}, fitted max err {fitted:.4f}, "
      f"rms residual {rms:.4f}")
for i in [0, 5, 77, 143]:
    r, c = divmod(i, S)
    print(f"  position {i}: measured (x {qy0[r, c]:.4f}, y {qx0[r, c]:.4f}) fitted (x {fy[r, c]:.4f}, y {fx[r, c]:.4f}) "
          f"truth (x {tx[r, c]:.4f}, y {ty[r, c]:.4f})")
