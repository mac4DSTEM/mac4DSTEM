#!/usr/bin/env python3
"""Source-lock py4DSTEM parallax depth_section on a non-square fixture."""

import json
import pathlib
import sys

import numpy as np

repo = pathlib.Path(__file__).resolve().parents[2]
source = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/parallax.py").read_text()
for contract in (
    "def depth_section(",
    "dx = -self._probe_angles[:, 0] * dz / self._scan_sampling[0]",
    "shift_op = xp.exp(",
    "im_depth = xp.fft.fft2(self._stack_BF_shifted) * shift_op * CTF_corr",
    "stack_depth[a0] = xp.real(xp.fft.ifft2(im_depth)).mean(0)",
    "(k_info_limit) ** (2 * k_info_power)",
):
    if contract not in source:
        raise SystemExit(f"py4DSTEM depth contract changed: {contract}")

height, width = 5, 7
scan_shape = (3, 5)
sampling = 2.0
wavelength = 0.025079
depths = np.array([-37.5, 0.0, 84.0])
angles = np.array([[-7.0, 3.5], [2.0, -5.0], [8.5, 6.0]], dtype=np.float32) / 1000
terms = np.array([[1, 0, 0], [1, 2, 0], [1, 2, 1], [2, 1, 0]], dtype=int)
coefs = np.array([420.0, -75.0, 33.0, 2100.0])
y, x = np.mgrid[:height, :width]
stack = np.stack([
    1 + 0.18 * np.sin(0.71 * y + 0.29 * x + i)
    + 0.07 * np.cos(0.17 * y - 0.53 * x + 0.4 * i)
    for i in range(len(angles))
]).astype(np.float32)


def calculate_ctf():
    qx = np.fft.fftfreq(height, sampling).astype(np.float32)
    qy = np.fft.fftfreq(width, sampling).astype(np.float32)
    qr2 = qx[:, None] ** 2 + qy[None, :] ** 2
    alpha = np.sqrt(qr2) * wavelength
    theta = np.arctan2(qy[None, :], qx[:, None])
    chi = np.zeros((height, width), dtype=np.float32)
    for (m, n, a), coef in zip(terms, coefs):
        radial = alpha ** (m + 1) / (m + 1)
        if n == 0:
            chi += radial * coef
        elif a == 0:
            chi += radial * np.cos(n * theta) * coef
        else:
            chi += radial * np.sin(n * theta) * coef
    return chi * (2 * np.pi / wavelength), qr2


def run(full, limit=None, power=1.0):
    chi, qr2 = calculate_ctf()
    if not full:
        chi = np.pi * wavelength * coefs[0] * qr2
    ctf = np.sign(np.sin(chi))
    ctf[0, 0] = 0
    result = []
    qx_shift = -2j * np.pi * np.fft.fftfreq(height)[:, None]
    qy_shift = -2j * np.pi * np.fft.fftfreq(width)[None, :]
    for depth in depths:
        dx = -angles[:, 0] * depth / sampling
        dy = -angles[:, 1] * depth / sampling
        operator = np.exp(qx_shift[None] * dx[:, None, None]
                          + qy_shift[None] * dy[:, None, None])
        spectrum = np.fft.fft2(stack) * operator * ctf
        if limit is not None:
            spectrum /= 1 + (qr2**power) / (limit ** (2 * power))
        result.append(np.real(np.fft.ifft2(spectrum)).mean(0))
    result = np.asarray(result, dtype=np.float32)
    crop = result[:, 1:4, 1:6]
    return {"full": full, "limit": limit, "power": power,
            "stack": result.ravel().tolist(), "cropped": crop.ravel().tolist()}


json.dump({
    "shape": [height, width], "scanShape": list(scan_shape),
    "sampling": sampling, "wavelength": wavelength,
    "depths": depths.tolist(), "anglesMrad": (angles * 1000).ravel().tolist(),
    "terms": terms.ravel().tolist(), "coefficients": coefs.tolist(),
    "shiftedStack": stack.ravel().tolist(),
    "full": run(True), "fallback": run(False),
    "filtered": run(True, 0.11, 1.5),
}, sys.stdout, separators=(",", ":"))
print()
