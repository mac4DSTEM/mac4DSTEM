import numpy as np
from py4DSTEM.process.diffraction import Crystal
import json, itertools
_ALIAS = {"float_": np.float64, "complex_": np.complex128, "int_": np.int64,
          "unicode_": np.str_, "bool_": np.bool_}
for _n, _t in _ALIAS.items():
    if not hasattr(np, _n): setattr(np, _n, _t)
_orig_asarray, _orig_array, _orig_zeros, _orig_dtype = np.asarray, np.array, np.zeros, np.dtype
def _fix(d):
    return _ALIAS.get(d, d) if isinstance(d, str) else d
np.asarray = lambda a, dtype=None, **k: _orig_asarray(a, dtype=_fix(dtype), **k)
np.array   = lambda a, dtype=None, **k: _orig_array(a, dtype=_fix(dtype), **k)
np.zeros   = lambda s, dtype=float, **k: _orig_zeros(s, dtype=_fix(dtype), **k)
np.dtype   = lambda d, **k: _orig_dtype(_fix(d), **k)


a = 4.08
pos = np.array([[0,0,0],[0,.5,.5],[.5,0,.5],[.5,.5,0]])
cry = Crystal(pos, [79]*4, np.array([a,a,a,90,90,90]))
cry.calculate_structure_factors(1.2)
cry.setup_diffraction(200e3)   # 200 kV
print("wavelength (A):", cry.wavelength)

sigma = 0.03/np.sqrt(2)
tol = 0.1/sigma
scale, ox, oy = 0.008, 256.0, 256.0

rng = np.random.default_rng(7)
cases = []
for i in range(40):
    # a generic zone axis and a generic in-plane x axis, both in CARTESIAN crystal coords
    za = rng.normal(size=3); za /= np.linalg.norm(za)
    px = rng.normal(size=3); px -= px@za*za; px /= np.linalg.norm(px)
    M = cry.parse_orientation(zone_axis_cartesian=za, proj_x_cartesian=px)
    bp = cry.generate_diffraction_pattern(orientation_matrix=M,
                                          sigma_excitation_error=sigma,
                                          tol_excitation_error_mult=tol,
                                          tol_intensity=1e-6, k_max=1.2)
    qx = bp.data['qx']; qy = bp.data['qy']; I = bp.data['intensity']
    peaks = [{"x": float(ox + qy[j]/scale), "y": float(oy + qx[j]/scale),
              "intensity": float(I[j])} for j in range(len(qx))]
    cases.append((M, peaks))
    print(f"case {i}: {len(peaks)} peaks, zone axis (lab z col) = {M[:,2]}")

inp = {"cellAAngstrom": a,
       "siteFractional": pos.tolist(), "siteAtomicNumbers": [79]*4,
       "kMaxInvAngstrom": 1.2, "zoneAxisCount": 600, "symmetry": "cubic",
       "invAngstromPerPixel": scale, "originX": ox, "originY": oy,
       "wavelengthAngstrom": float(cry.wavelength),
       "intensityPower": 0.25, "radialKernelInvAngstrom": 0.08,
       "distinctOrientationDeg": 10,
       "patterns": [c[1] for c in cases]}
json.dump(inp, open('py4-input.json','w'))
np.save('py4-truth.npy', np.stack([c[0] for c in cases]))
print("written py4-input.json / py4-truth.npy")
