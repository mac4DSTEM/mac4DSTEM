#!/usr/bin/env python3
"""Source-lock py4DSTEM's low-order parallax aberration fit."""

import json
import pathlib
import sys

import numpy as np
from scipy.linalg import polar

repo = pathlib.Path(__file__).resolve().parents[2]
source = (
    repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/parallax.py"
).read_text()
for contract in (
    "shifts_Ang = shifts * sampling",
    "m = np.linalg.lstsq(angles, shifts_Ang, rcond=None)[0]",
    'm_rotation, m_aberration = polar(m, side="right")',
    "rotation_rad = -1 * np.arctan2(m_rotation[1, 0], m_rotation[0, 0])",
    "aberrations_C1 = (m_aberration[0, 0] + m_aberration[1, 1]) / 2",
    "aberrations_C12b = (m_aberration[1, 0] + m_aberration[0, 1]) / 2",
):
    if contract not in source:
        raise SystemExit(f"py4DSTEM low-order aberration contract changed: {contract}")
for contract in (
    "chi *= 2 * np.pi / self._wavelength",
    "CTF_corr = xp.sign(xp.sin(chi_even)) * xp.exp(-1j * chi_odd)",
    "CTF_corr[0, 0] = 0",
    "im_fft_corr = xp.fft.fft2(im) * CTF_corr",
    "im_fft_corr /= 1 + (xp.sqrt(kra2) / q_lowpass) ** (2 * butterworth_order)",
):
    if contract not in source:
        raise SystemExit(f"py4DSTEM correction contract changed: {contract}")
utils_source = (
    repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/utils.py"
).read_text()
for contract in (
    "u = qx * wavelength",
    "v = qy * wavelength",
    "_aberrations_basis_du[:, a0] = (u * alpha ** (m - 1)).ravel()",
    "* ((m + 1) * u * xp.cos(n * theta) + n * v * xp.sin(n * theta))",
    "* ((m + 1) * u * xp.sin(n * theta) - n * v * xp.cos(n * theta))",
):
    if contract not in utils_source:
        raise SystemExit(f"py4DSTEM gradient contract changed: {contract}")

angles_mrad = np.array(
    [
        [-18.0, -11.0],
        [-17.0, 4.0],
        [-9.0, 15.0],
        [2.0, -16.0],
        [4.0, 7.0],
        [11.0, 17.0],
        [19.0, -7.0],
        [22.0, 9.0],
    ],
    dtype=np.float64,
)
angles = angles_mrad / 1000
scan_sampling = 2.35
rotation_true = -0.31
q = np.array(
    [
        [np.cos(rotation_true), -np.sin(rotation_true)],
        [np.sin(rotation_true), np.cos(rotation_true)],
    ]
)
p = np.array([[158.0, -21.0], [-21.0, 102.0]])
transform = q @ p
residual = np.array(
    [
        [0.003, -0.002],
        [-0.001, 0.004],
        [0.002, 0.001],
        [-0.004, -0.001],
        [0.001, -0.003],
        [0.002, 0.002],
        [-0.003, 0.001],
        [0.0, -0.002],
    ]
)
shifts_angstrom = angles @ transform + residual
shifts_pixels = shifts_angstrom / scan_sampling


def fit(force_transpose=False, forced_degrees=None):
    shifts = shifts_pixels.copy()
    if force_transpose:
        shifts = np.flip(shifts, axis=1)
    measured = shifts * scan_sampling
    matrix = np.linalg.lstsq(angles, measured, rcond=None)[0]
    if forced_degrees is None:
        rotation, aberration = polar(matrix, side="right")
        if force_transpose:
            rotation = rotation.T
        rotation_rad = -np.arctan2(rotation[1, 0], rotation[0, 0])
        if 2 * np.abs(np.mod(rotation_rad + np.pi, 2 * np.pi) - np.pi) > np.pi:
            rotation_rad = np.mod(rotation_rad, 2 * np.pi) - np.pi
            aberration *= -1
    else:
        rotation_rad = np.deg2rad(forced_degrees)
        c, s = np.cos(rotation_rad), np.sin(rotation_rad)
        rotation = np.array([[c, -s], [s, c]])
        if force_transpose:
            rotation = rotation.T
        aberration = rotation @ matrix
    c1 = (aberration[0, 0] + aberration[1, 1]) / 2
    if force_transpose:
        c12a = -(aberration[0, 0] - aberration[1, 1]) / 2
    else:
        c12a = (aberration[0, 0] - aberration[1, 1]) / 2
    c12b = (aberration[1, 0] + aberration[0, 1]) / 2
    fitted = angles @ matrix
    rms = np.sqrt(np.mean(np.sum((measured - fitted) ** 2, axis=1)))
    return {
        "forceTranspose": force_transpose,
        "forcedDegrees": forced_degrees,
        "measured": measured.ravel().tolist(),
        "fitted": fitted.ravel().tolist(),
        "rotationRad": float(rotation_rad),
        "c1": float(c1),
        "c12a": float(c12a),
        "c12b": float(c12b),
        "rms": float(rms),
    }


def default_terms():
    terms = []
    for m in range(1, 3):
        for n in range(0, min(4, m + 1) + 1):
            if (m + n) % 2:
                terms.append([m, n, 0])
                if n > 0:
                    terms.append([m, n, 1])
    return terms


def gradient_samples(rotation_rad, terms):
    c, s = np.cos(-rotation_rad), np.sin(-rotation_rad)
    u0, v0 = angles[:, 0], angles[:, 1]
    u = u0 * c + v0 * s
    v = -u0 * s + v0 * c
    alpha = np.sqrt(u**2 + v**2)
    theta = np.arctan2(v, u)
    gradients = np.zeros((len(angles), len(terms), 2))
    for index, (m, n, component) in enumerate(terms):
        radial = alpha ** (m - 1)
        if n == 0:
            gradients[:, index, 0] = u * radial
            gradients[:, index, 1] = v * radial
        elif component == 0:
            gradients[:, index, 0] = radial * (
                (m + 1) * u * np.cos(n * theta) + n * v * np.sin(n * theta)
            ) / (m + 1)
            gradients[:, index, 1] = radial * (
                (m + 1) * v * np.cos(n * theta) - n * u * np.sin(n * theta)
            ) / (m + 1)
        else:
            gradients[:, index, 0] = radial * (
                (m + 1) * u * np.sin(n * theta) - n * v * np.cos(n * theta)
            ) / (m + 1)
            gradients[:, index, 1] = radial * (
                (m + 1) * v * np.sin(n * theta) + n * u * np.cos(n * theta)
            ) / (m + 1)
    return gradients


def higher_fit(method):
    low = fit()
    terms = default_terms()
    gradients = gradient_samples(low["rotationRad"], terms)
    coefficients = np.zeros(len(terms))
    for index, term in enumerate(terms):
        if term == [1, 0, 0]:
            coefficients[index] = low["c1"]
        elif term == [1, 2, 0]:
            coefficients[index] = low["c12a"]
        elif term == [1, 2, 1]:
            coefficients[index] = low["c12b"]
    fitted = np.tensordot(gradients, coefficients, axes=(1, 0))
    groups = []
    for radial in sorted(set(term[0] for term in terms)):
        groups.append(np.flatnonzero([term[0] == radial for term in terms]))
    if method == "recursiveExclusive":
        passes = groups
    elif method == "recursive":
        passes = [np.concatenate(groups[: index + 1]) for index in range(len(groups))]
    else:
        passes = [np.arange(len(terms))]
    measured = np.asarray(low["measured"]).reshape(-1, 2)
    for indices in passes:
        delta = (measured - fitted).T.ravel()
        matrix = np.vstack(
            (gradients[:, indices, 0], gradients[:, indices, 1])
        )
        increment = np.linalg.lstsq(matrix, delta, rcond=None)[0]
        coefficients[indices] += increment
        fitted += np.tensordot(gradients[:, indices], increment, axes=(1, 0))
    rms = np.sqrt(np.mean(np.sum((measured - fitted) ** 2, axis=1)))
    return {
        "method": method,
        "terms": terms,
        "gradients": gradients.ravel().tolist(),
        "coefficients": coefficients.tolist(),
        "fitted": fitted.ravel().tolist(),
        "rms": float(rms),
    }


height, width = 10, 14
scan_height, scan_width = 6, 8
wavelength = 0.025079
yy, xx = np.mgrid[:height, :width]
aligned_bf = (
    1.1
    + 0.3 * np.sin(0.73 * yy + 0.21 * xx)
    + 0.17 * np.cos(0.19 * yy - 0.57 * xx)
    + 0.08 * np.exp(-((yy - 3.2) ** 2 + (xx - 9.1) ** 2) / 4.3)
).astype(np.float32)


def correction_case(use_full, lowpass=None, highpass=None, order=2):
    higher = higher_fit("recursive")
    terms = higher["terms"]
    coefficients = np.asarray(higher["coefficients"])
    krow = np.fft.fftfreq(height, scan_sampling)
    kcolumn = np.fft.fftfreq(width, scan_sampling)
    frequency2 = krow[:, None] ** 2 + kcolumn[None, :] ** 2
    frequency = np.sqrt(frequency2)
    alpha = frequency * wavelength
    theta = np.arctan2(kcolumn[None, :], krow[:, None])
    chi_even = np.zeros((height, width), dtype=np.float64)
    chi_odd = np.zeros((height, width), dtype=np.float64)
    if use_full:
        for (m, n, component), coefficient in zip(terms, coefficients):
            radial = alpha ** (m + 1) / (m + 1)
            if n == 0:
                basis = radial
            elif component == 0:
                basis = radial * np.cos(n * theta)
            else:
                basis = radial * np.sin(n * theta)
            if m % 2:
                chi_even += basis * coefficient
            else:
                chi_odd += basis * coefficient
        chi_even *= 2 * np.pi / wavelength
        chi_odd *= 2 * np.pi / wavelength
        if not chi_even.any():
            chi_even = np.ones_like(chi_even)
    else:
        chi_even = np.pi * wavelength * fit()["c1"] * frequency2
    transfer = np.sign(np.sin(chi_even)) * np.exp(-1j * chi_odd)
    transfer[0, 0] = 0
    if lowpass is not None:
        transfer /= 1 + (frequency / lowpass) ** (2 * order)
    if highpass is not None:
        transfer *= 1 - 1 / (1 + (frequency / highpass) ** (2 * order))
    padded = np.real(np.fft.ifft2(np.fft.fft2(aligned_bf) * transfer))
    top, left = (height - scan_height) // 2, (width - scan_width) // 2
    cropped = padded[top : top + scan_height, left : left + scan_width]
    return {
        "useFull": use_full,
        "lowpass": lowpass,
        "highpass": highpass,
        "order": order,
        "chiEven": chi_even.ravel().tolist(),
        "chiOdd": chi_odd.ravel().tolist(),
        "transferReal": transfer.real.ravel().tolist(),
        "transferImaginary": transfer.imag.ravel().tolist(),
        "padded": padded.ravel().tolist(),
        "cropped": cropped.ravel().tolist(),
    }


json.dump(
    {
        "anglesMrad": angles_mrad.ravel().tolist(),
        "shiftsPixels": shifts_pixels.ravel().tolist(),
        "scanSamplingAngstrom": scan_sampling,
        "cases": [
            fit(),
            fit(force_transpose=True),
            fit(forced_degrees=17.5),
            fit(force_transpose=True, forced_degrees=-12.0),
        ],
        "higher": [
            higher_fit("recursive"),
            higher_fit("recursiveExclusive"),
            higher_fit("global"),
        ],
        "correction": {
            "shape": [height, width],
            "scanShape": [scan_height, scan_width],
            "wavelength": wavelength,
            "alignedBF": aligned_bf.ravel().tolist(),
            "cases": [
                correction_case(True),
                correction_case(True, lowpass=0.11, highpass=0.018, order=3),
                correction_case(False),
            ],
        },
    },
    sys.stdout,
    separators=(",", ":"),
)
print()
