"""The py4DSTEM oracle for the app's crystal presets (2026-10-15, macTEM's refuter finding: a family check compares
against pymatgen or py4DSTEM, never the Swift against itself).

Run from the repo root with the pinned py4DSTEM (References/py4DSTEM-dev at f050d207, tools/lib/fetch-py4dstem.sh):

    ~/miniconda3/envs/py4dstem/bin/python -I mac4DSTEMTests/Fixtures/py4dstem_preset_reflections.py

(the suite's memory watchdog, 8 GB, owner's rule 2026-10-15; a process cannot cap itself on macOS 27).

It writes mac4DSTEMTests/Fixtures/py4dstem-preset-reflections.json: for each preset, py4DSTEM's
Crystal.calculate_structure_factors(k_max, tol_structure_factor=1e-4) kept set as [h, k, l, |g|, Re F, Im F] with
|g| <= K (the zero beam dropped). The sites below are typed from Core/Crystal/Crystal.swift's presets, not computed by
any Swift. py4DSTEM tiles hkl from the shortest reciprocal vector, which falls short in an oblique cell (Crystal.swift's
note), so it is run at 1.5 K and cut to K here. Its structure factor is complex64: F agrees with a float64 sum to about
1e-7 relative, and a reflection whose |F| lies within 1e-6 of the 1e-4 cut is listed under "borderline" so a consumer
test can tell a float32 cut decision from a real disagreement.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "References", "py4DSTEM-dev"))

import numpy as np  # noqa: E402
import py4DSTEM  # noqa: E402
from py4DSTEM.process.diffraction.crystal import Crystal  # noqa: E402

assert os.path.realpath(py4DSTEM.__file__).startswith(os.path.realpath(os.path.join(ROOT, "References"))), \
    "not the pinned py4DSTEM: " + py4DSTEM.__file__

K = 1.2
CUT = 1e-4


def fcc(a, z):
    return [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]], [z] * 4, [a, a, a, 90, 90, 90]


def bcc(a, z):
    return [[0, 0, 0], [0.5, 0.5, 0.5]], [z] * 2, [a, a, a, 90, 90, 90]


def diamond(a, z):
    base = [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]
    pos = base + [[p[0] + 0.25, p[1] + 0.25, p[2] + 0.25] for p in base]
    return pos, [z] * 8, [a, a, a, 90, 90, 90]


def hcp(a, c, z):
    return [[0, 0, 0], [2.0 / 3.0, 1.0 / 3.0, 0.5]], [z] * 2, [a, a, c, 90, 90, 120]


def beta_double_prime():
    def four_i(z, x, zc):
        return [[x, 0, zc], [-x, 0, -zc], [x + 0.5, 0.5, zc], [-x + 0.5, 0.5, -zc]], [z] * 4
    pos, num = [[0, 0, 0], [0.5, 0.5, 0]], [12, 12]
    for z, x, zc in [(12, 0.3459, 0.089), (12, 0.430, 0.652), (14, 0.0565, 0.649), (14, 0.1885, 0.224),
                     (14, 0.2171, 0.617)]:
        p, n = four_i(z, x, zc)
        pos += p
        num += n
    return pos, num, [15.16, 4.05, 6.74, 90, 105.3, 90]


def ws2():
    zs = 0.6225
    pos = [[1 / 3, 2 / 3, 0.25], [2 / 3, 1 / 3, 0.75], [1 / 3, 2 / 3, zs], [1 / 3, 2 / 3, 1.5 - zs],
           [2 / 3, 1 / 3, 1.0 - zs], [2 / 3, 1 / 3, zs - 0.5]]
    return pos, [74, 74, 16, 16, 16, 16], [3.1532, 3.1532, 12.323, 90, 90, 120]


PRESETS = {
    "aluminum": fcc(4.0495, 13), "gold": fcc(4.0782, 79), "nickel": fcc(3.5240, 28), "copper": fcc(3.6149, 29),
    "iron": bcc(2.8665, 26), "silicon": diamond(5.4309, 14), "magnesium": hcp(3.2094, 5.2108, 12),
    "betaDoublePrime": beta_double_prime(), "tungstenDisulfide": ws2(),
}

out = {"py4dstem": "f050d207 (References/py4DSTEM-dev)", "kMax": K, "cut": CUT, "presets": {}}
for name, (pos, num, cell) in PRESETS.items():
    c = Crystal(np.array(pos, dtype=float), np.array(num), np.array(cell, dtype=float))
    c.calculate_structure_factors(k_max=1.5 * K, tol_structure_factor=CUT)
    rows, border = [], []
    for i in range(c.hkl.shape[1]):
        g = float(c.g_vec_leng[i])
        h, k, l = (int(round(v)) for v in c.hkl[:, i])
        if g == 0 or g > K:
            continue
        f = complex(c.struct_factors[i])
        rows.append([h, k, l, g, f.real, f.imag])
        if abs(abs(f) - CUT) < 1e-6:
            border.append([h, k, l])
    rows.sort(key=lambda r: (r[3], -r[0], -r[1], -r[2]))
    out["presets"][name] = {"reflections": rows, "borderline": border}
    print(f"{name}: {len(rows)} reflections <= {K} A^-1, {len(border)} borderline")

path = os.path.join(ROOT, "mac4DSTEMTests", "Fixtures", "py4dstem-preset-reflections.json")
with open(path, "w") as fh:
    json.dump(out, fh, indent=0, sort_keys=True)
    fh.write("\n")
print("wrote", path)
