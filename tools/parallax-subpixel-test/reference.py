#!/usr/bin/env python3
"""Source-lock py4DSTEM's bilinear parallax KDE on an asymmetric fixture."""

import json
import pathlib
import sys

import numpy as np
from scipy.ndimage import gaussian_filter

repo = pathlib.Path(__file__).resolve().parents[2]
parallax = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/parallax.py").read_text()
utils = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/utils.py").read_text()
for contract in (
    "BF_sampling = 1 / asnumpy(self._kr).max() / 2",
    "DF_sampling = 1 / (",
    "pixel_output_shape = np.round(BF_size * self._kde_upsample_factor).astype(\"int\")",
    "xa = (xa_init + xy_shifts[:, 0, None, None]) * self._kde_upsample_factor",
    "stack_BF_unshifted = self._stack_BF_unshifted",
):
    if contract not in parallax:
        raise SystemExit(f"py4DSTEM subpixel contract changed: {contract}")
for contract in (
    "def bilinear_kernel_density_estimate(",
    "mode=[\"wrap\", \"wrap\"]",
    "pix_count = gaussian_filter(pix_count, kde_sigma)",
    "sub = pix_count > 1e-3",
    "pix_output[np.logical_not(sub)] = 1",
    "pix_fft /= xp.sinc(",
):
    if contract not in utils:
        raise SystemExit(f"py4DSTEM bilinear KDE contract changed: {contract}")

scan_shape = (3, 5)
padding = (2, 2)
shape = (scan_shape[0] + padding[0], scan_shape[1] + padding[1])
shifts = np.array([[0.25, -0.375], [-0.5, 0.125], [0.1, 0.6]], dtype=np.float32)
k_vectors = np.array([[-0.15, 0.0], [0.0, 0.10], [0.12, -0.04]], dtype=np.float32)
y, x = np.mgrid[: shape[0], : shape[1]]
stack = np.stack(
    [
        1 + 0.11 * np.sin(0.7 * y + 0.23 * x + i)
        + 0.06 * np.cos(0.19 * y - 0.61 * x + 0.4 * i)
        for i in range(len(shifts))
    ]
).astype(np.float32)


def sinc(value):
    return np.sinc(value)


def kde(factor, lowpass, lanczos=None, probe_rows=None, probe_columns=None):
    out_shape = np.round(np.array(shape) * factor).astype(int)
    xa0, ya0 = np.meshgrid(
        np.arange(shape[0], dtype=np.float32),
        np.arange(shape[1], dtype=np.float32), indexing="ij"
    )
    if probe_rows is None:
        probe_rows = np.zeros(shape, dtype=np.float32)
        probe_columns = np.zeros(shape, dtype=np.float32)
    xa = (xa0 + probe_rows + shifts[:, 0, None, None]) * factor
    ya = (ya0 + probe_columns + shifts[:, 1, None, None]) * factor
    xf = np.floor(xa.ravel()).astype(int)
    yf = np.floor(ya.ravel()).astype(int)
    dx = xa.ravel() - xf
    dy = ya.ravel() - yf
    intensities = stack.ravel()
    count = np.zeros(np.prod(out_shape), dtype=np.float32)
    output = np.zeros(np.prod(out_shape), dtype=np.float32)
    if lanczos is None:
        bases = (
            (xf, yf, (1 - dx) * (1 - dy)),
            (xf + 1, yf, dx * (1 - dy)),
            (xf, yf + 1, (1 - dx) * dy),
            (xf + 1, yf + 1, dx * dy),
        )
    else:
        bases = []
        for i in range(-lanczos + 1, lanczos + 1):
            for j in range(-lanczos + 1, lanczos + 1):
                # Preserve the checked-in helper's i/dy expression.
                weights = (
                    sinc(i - dx) * sinc((i - dx) / lanczos)
                ) * (sinc(j - dy) * sinc((i - dy) / lanczos))
                bases.append((xf + i, yf + j, weights))
    for rows, cols, weights in bases:
        inds = np.ravel_multi_index((rows, cols), out_shape, mode=["wrap", "wrap"])
        count += np.bincount(inds, weights=weights, minlength=np.prod(out_shape))
        output += np.bincount(
            inds, weights=weights * intensities, minlength=np.prod(out_shape)
        )
    count = gaussian_filter(count.reshape(out_shape), 0.125 * factor)
    output = gaussian_filter(output.reshape(out_shape), 0.125 * factor)
    valid = count > 1e-3
    output[valid] /= count[valid]
    output[~valid] = 1
    if lowpass:
        spectrum = np.fft.fft2(output)
        spectrum /= np.sinc(np.fft.fftfreq(out_shape[0]).astype(np.float32))[:, None]
        spectrum /= np.sinc(np.fft.fftfreq(out_shape[1]).astype(np.float32))[None]
        output = np.real(np.fft.ifft2(spectrum))
    pad = np.round(np.array(padding) * factor).astype(int)
    start = np.round(np.array(padding) / 2 * factor).astype(int)
    crop = output[
        start[0] : out_shape[0] - (pad[0] - start[0]),
        start[1] : out_shape[1] - (pad[1] - start[1]),
    ]
    return {
        "factor": factor,
        "shape": out_shape.tolist(),
        "padded": output.astype(np.float32).ravel().tolist(),
        "cropShape": list(crop.shape),
        "cropped": crop.astype(np.float32).ravel().tolist(),
        "lowpass": lowpass,
    }


def interpolate(image, probe_rows, probe_columns, factor):
    xa0, ya0 = np.meshgrid(
        np.arange(shape[0], dtype=np.float32),
        np.arange(shape[1], dtype=np.float32), indexing="ij"
    )
    xa = (xa0 + probe_rows + shifts[:, 0, None, None]) * factor
    ya = (ya0 + probe_columns + shifts[:, 1, None, None]) * factor
    xf = np.floor(xa).astype(int)
    yf = np.floor(ya).astype(int)
    dx = xa - xf
    dy = ya - yf
    out = np.zeros_like(xa, dtype=np.float32)
    for rows, cols, weights in (
        (xf, yf, (1 - dx) * (1 - dy)),
        (xf + 1, yf, dx * (1 - dy)),
        (xf, yf + 1, (1 - dx) * dy),
        (xf + 1, yf + 1, dx * dy),
    ):
        out += image[rows % image.shape[0], cols % image.shape[1]] * weights
    return out


def position_correct(factor, iterations, checkerboard):
    output = np.array(kde(factor, False)["padded"], dtype=np.float32).reshape(
        np.round(np.array(shape) * factor).astype(int)
    )
    probe_rows = np.zeros(shape, dtype=np.float32)
    probe_columns = np.zeros(shape, dtype=np.float32)
    step = np.ones(shape, dtype=np.float32)
    window = np.zeros(shape, dtype=np.float32)
    window[padding[0] // 2 : padding[0] // 2 + scan_shape[0],
           padding[1] // 2 : padding[1] // 2 + scan_shape[1]] = 1
    scores = np.mean(np.abs(interpolate(output, probe_rows, probe_columns, factor) - stack), axis=0) * window
    stats = [float(scores.mean())]
    directions = np.array(
        [[-1, 0], [1, 0], [0, -1], [0, 1]] if checkerboard
        else [[-0.5, 0], [0.5, 0], [0, -0.5], [0, 0.5]], dtype=np.float32
    )
    for _ in range(iterations):
        tests = []
        for direction in directions:
            sampled = interpolate(
                output, probe_rows + direction[0] * step,
                probe_columns + direction[1] * step, factor
            )
            tests.append(np.mean(np.abs(sampled - stack), axis=0))
        tests = np.array(tests)
        if checkerboard:
            tests *= window[None]
            update = np.min(tests, axis=0) < scores
            best = np.argmin(tests, axis=0)
            for index, direction in enumerate(directions):
                selected = update & (best == index)
                probe_rows[selected] += direction[0] * step[selected] * window[selected]
                probe_columns[selected] += direction[1] * step[selected] * window[selected]
        else:
            delta_row = tests[0] - tests[1]
            delta_column = tests[2] - tests[3]
            dr = np.sqrt(delta_row**2 + delta_column**2) / step
            delta_row *= window / dr
            delta_column *= window / dr
            fixed = np.mean(np.abs(interpolate(
                output, probe_rows + delta_row, probe_columns + delta_column, factor
            ) - stack), axis=0) * window
            update = fixed < scores
            probe_rows[update] += delta_row[update]
            probe_columns[update] += delta_column[update]
        step[~update] *= 0.75
        step = np.maximum(step, 0.1)
        result = kde(factor, False, probe_rows=probe_rows, probe_columns=probe_columns)
        output = np.array(result["padded"], dtype=np.float32).reshape(result["shape"])
        scores = np.mean(np.abs(interpolate(output, probe_rows, probe_columns, factor) - stack), axis=0) * window
        stats.append(float(scores.mean()))
    return {
        "factor": factor, "shape": list(output.shape),
        "padded": output.ravel().tolist(), "cropShape": result["cropShape"],
        "cropped": result["cropped"], "lowpass": False,
        "probeRows": probe_rows.ravel().tolist(),
        "probeColumns": probe_columns.ravel().tolist(), "scores": stats,
    }


scan_sampling = 2.0
q_sampling = 0.2
detector_height = 6
bf_limit = scan_sampling / (1 / np.linalg.norm(k_vectors, axis=1).max() / 2)
df_limit = max(scan_sampling / (1 / (q_sampling * detector_height)), 1)
auto_factor = max(df_limit * 2 / 3, 1)
json.dump(
    {
        "scanShape": list(scan_shape), "padding": list(padding),
        "stackShape": list(shape), "stack": stack.ravel().tolist(),
        "shifts": shifts.ravel().tolist(), "kVectors": k_vectors.ravel().tolist(),
        "scanSampling": scan_sampling, "qSampling": q_sampling,
        "detectorHeight": detector_height, "bfLimit": float(bf_limit),
        "dfLimit": float(df_limit), "auto": kde(float(auto_factor), False),
        "filtered": kde(2.25, True),
        "lanczos": kde(1.75, False, lanczos=2),
        "position": position_correct(float(auto_factor), 2, False),
        "checkerboard": position_correct(float(auto_factor), 2, True),
    }, sys.stdout, separators=(",", ":")
)
print()
