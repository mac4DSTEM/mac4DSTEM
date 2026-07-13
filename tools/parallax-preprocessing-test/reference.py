#!/usr/bin/env python3
"""Source-lock and emit a small py4DSTEM Parallax.preprocess default fixture."""

import json
import math
import pathlib
import sys

import numpy as np

repo = pathlib.Path(__file__).resolve().parents[2]
parallax = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/parallax.py").read_text()
utils = (repo / "References/py4DSTEM-dev/py4DSTEM/process/utils/utils.py").read_text()
contracts = [
    "dp_mean = intensities.mean((0, 1))",
    "self._dp_mask = dp_mean >= (xp.max(dp_mean) * threshold_intensity)",
    "(self._xy_inds - xp.mean(self._xy_inds, axis=0)[None])",
    "self._probe_angles = self._kxy * self._wavelength",
    "all_bfs = xp.moveaxis(",
    "weights = xp.average(",
    "self._window_inv[None] + self._window_edge[None] * all_bfs",
]
for contract in contracts:
    if contract not in parallax:
        raise SystemExit(f"py4DSTEM parallax contract changed; missing: {contract}")
if "lam = h / ma.sqrt(2 * m * e * E_eV) / ma.sqrt(1 + e * E_eV / 2 / m / c**2) * 10**10" not in utils:
    raise SystemExit("py4DSTEM electron-wavelength contract changed")

scan_y, scan_x, det_y, det_x = 5, 7, 6, 8
threshold = 0.8
edge_blend = 3.0
padding_y, padding_x = 4, 6
q_sampling = 0.04
energy_ev = 200_000.0

cube = np.empty((scan_y, scan_x, det_y, det_x), dtype=np.float32)
for y in range(scan_y):
    for x in range(scan_x):
        for qx in range(det_y):
            for qy in range(det_x):
                radius2 = ((qx - 2.35) / 1.7) ** 2 + ((qy - 3.65) / 2.0) ** 2
                detector = math.exp(-radius2 / 2)
                modulation = 1 + 0.13 * math.sin(
                    0.55 * y + 0.31 * x + 0.17 * qx - 0.11 * qy
                )
                cube[y, x, qx, qy] = detector * modulation + 0.004 * (y + x + 1)

dp_mean = cube.mean((0, 1))
dp_mask = dp_mean >= (np.max(dp_mean) * threshold)
xy_inds = np.argwhere(dp_mask)
wavelength = (
    6.62607e-34
    / math.sqrt(2 * 9.109383e-31 * 1.602177e-19 * energy_ev)
    / math.sqrt(
        1
        + 1.602177e-19
        * energy_ev
        / 2
        / 9.109383e-31
        / 299792458**2
    )
    * 1e10
)
kxy = np.asarray(
    (xy_inds - np.mean(xy_inds, axis=0)[None]) * q_sampling,
    dtype=np.float32,
)
probe_angles_mrad = kxy * wavelength * 1e3


def edge_axis(count):
    axis = np.linspace(-1, 1, count + 1, dtype=np.float32)[1:]
    axis -= (axis[1] - axis[0]) / 2
    return np.sin(
        np.clip((1 - np.abs(axis)) * count / edge_blend / 2, 0, 1)
        * (np.pi / 2)
    ) ** 2


window = edge_axis(scan_y)[:, None] * edge_axis(scan_x)[None, :]
all_bfs = np.moveaxis(
    cube[:, :, xy_inds[:, 0], xy_inds[:, 1]], (0, 1, 2), (1, 2, 0)
)
stack_shape = (len(xy_inds), scan_y + padding_y, scan_x + padding_x)
stack = np.ones(stack_shape, dtype=np.float32)
weights = np.average(
    all_bfs.reshape((len(xy_inds), -1)), weights=window.ravel(), axis=1
)
all_bfs /= weights[:, None, None]
top, left = padding_y // 2, padding_x // 2
unshifted = np.ones(stack_shape, dtype=np.float32)
unshifted[:, top : top + scan_y, left : left + scan_x] = all_bfs
stack[:, top : top + scan_y, left : left + scan_x] = (
    (1 - window)[None] + window[None] * all_bfs
)
stack_mask = np.zeros(stack_shape, dtype=np.float32)
stack_mask[:, top : top + scan_y, left : left + scan_x] = window[None]
stack_mean = np.mean(stack)
mask_sum = np.sum(window) * len(xy_inds)
recon_mask = np.mean(stack_mask, axis=0)
mask_inv = 1 - np.clip(recon_mask, 0, 1)
recon = (
    stack_mean * mask_inv + np.mean(stack * stack_mask, axis=0)
) / (recon_mask + mask_inv)
error = (
    np.sum(np.abs(stack - recon[None]) * stack_mask)
    / mask_sum
    / stack_mean
)

json.dump(
    {
        "shape": [scan_y, scan_x, det_y, det_x],
        "cube": cube.ravel().tolist(),
        "threshold": threshold,
        "edgeBlend": edge_blend,
        "paddingY": padding_y,
        "paddingX": padding_x,
        "qSampling": q_sampling,
        "energyEV": energy_ev,
        "wavelength": wavelength,
        "detectorMask": dp_mask.ravel().tolist(),
        "indices": xy_inds.tolist(),
        "kVectors": kxy.ravel().tolist(),
        "probeAnglesMrad": probe_angles_mrad.ravel().tolist(),
        "edgeWindow": window.ravel().tolist(),
        "stackShape": list(stack_shape),
        "normalizedStack": stack.ravel().tolist(),
        "unshiftedStack": unshifted.ravel().tolist(),
        "incoherentBF": recon.ravel().tolist(),
        "initialError": float(error),
    },
    sys.stdout,
    separators=(",", ":"),
)
print()
