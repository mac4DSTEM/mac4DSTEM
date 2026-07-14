#!/usr/bin/env python3
"""Lock strain indexing/fitting/reference/tensor conventions to py4DSTEM."""

from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT / "References/py4DSTEM-dev/py4DSTEM/process/strain/latticevectors.py"
).read_text()

for expression in (
    "M = lstsq(beta, alpha, rcond=None)[0].T",
    "M = np.round(M).astype(int)",
    "weighted_M = M * weights[:, np.newaxis]",
    'g1x = np.median(g1g2_map.get_slice("g1x").data[mask])',
    'strain_map.get_slice("e_xx").data[Rx, Ry] = 1 - beta[0, 0]',
    'strain_map.get_slice("e_xy").data[Rx, Ry] = -(beta[0, 1] + beta[1, 0]) / 2.0',
):
    if expression not in SOURCE:
        raise RuntimeError(f"py4DSTEM strain contract changed: {expression}")

# Independent tensor check for the non-square Swift robustness fixture.
reference_g1 = np.array([10.0, 0.0])
reference_g2 = np.array([0.0, 10.0])
local_g1 = np.array([9.5, 0.0])
local_g2 = np.array([0.0, 10.5])
reference = np.stack([reference_g1, reference_g2])
local = np.stack([local_g1, local_g2])
beta = np.linalg.lstsq(reference, local, rcond=None)[0].T
exx = 1 - beta[0, 0]
eyy = 1 - beta[1, 1]
exy = -(beta[0, 1] + beta[1, 0]) / 2
if not np.allclose([exx, eyy, exy], [0.05, -0.05, 0.0], atol=1e-12):
    raise RuntimeError("independent strain tensor fixture changed")

print("PASS: py4DSTEM indexing, weighted fit, median reference, and strain tensor source lock")
