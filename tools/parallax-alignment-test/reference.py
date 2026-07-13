#!/usr/bin/env python3
"""Source-lock integer and subpixel multi-level py4DSTEM Parallax alignment."""

import json
import pathlib
import sys

import numpy as np

repo = pathlib.Path(__file__).resolve().parents[2]
parallax = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/parallax.py").read_text()
cross = (repo / "References/py4DSTEM-dev/py4DSTEM/process/utils/cross_correlate.py").read_text()
multicorr = (repo / "References/py4DSTEM-dev/py4DSTEM/process/utils/multicorr.py").read_text()
contracts = [
    "xy_center = (self._xy_inds - xp.median(self._xy_inds, axis=0)).astype(\"float\")",
    "xy_inds = xp.round(xy_center / bin_vals[a0] + bin_shift).astype(\"int\")",
    "xy_vals = np.unique(",
    "inds_order = xp.argsort(xp.sum(xy_vals**2, axis=1))",
    "coefs = xp.linalg.lstsq(self._basis, xy_shifts_new, rcond=None)[0]",
    "shift_op = xp.exp(",
    "xy_shifts_median = xp.round(xp.median(self._xy_shifts, axis=0)).astype(int)",
    "self._recon_mask = xp.mean(self._stack_mask, axis=0)",
]
for contract in contracts:
    if contract not in parallax:
        raise SystemExit(f"py4DSTEM parallax alignment contract changed: {contract}")
for contract in (
    "cc = G1 * xp.conj(G2)",
    "cc_real = xp.real(xp.fft.ifft2(cc))",
    "x0, y0 = xp.unravel_index(cc_real.argmax(), cc.shape)",
):
    if contract not in cross:
        raise SystemExit(f"py4DSTEM correlation contract changed: {contract}")
for contract in (
    "xyShift[0] = xp.round(xyShift[0] * upsampleFactor) / upsampleFactor",
    "globalShift = xp.fix(xp.ceil(upsampleFactor * 1.5) / 2)",
    "imageCorrUpsample = xp.conj(",
    "xyShift = xyShift + (xySubShift + xp.array([dx, dy])) / upsampleFactor",
    "imageUpsample = xp.real(rowKern @ imageCorr @ colKern)",
):
    if contract not in multicorr:
        raise SystemExit(f"py4DSTEM multicorr contract changed: {contract}")

scan_y, scan_x = 8, 10
padding_y, padding_x = 4, 6
height, width = scan_y + padding_y, scan_x + padding_x
edge_blend = 4.0
indices = np.array(
    [[1, 1], [1, 3], [1, 5], [3, 1], [3, 3], [3, 5], [5, 1], [5, 3], [5, 5]],
    dtype=int,
)
kxy = np.asarray((indices - indices.mean(axis=0)[None]) * 0.05, dtype=np.float32)


def edge_axis(count):
    axis = np.linspace(-1, 1, count + 1, dtype=np.float32)[1:]
    axis -= (axis[1] - axis[0]) / 2
    return np.sin(
        np.clip((1 - np.abs(axis)) * count / edge_blend / 2, 0, 1)
        * (np.pi / 2)
    ) ** 2


window = edge_axis(scan_y)[:, None] * edge_axis(scan_x)[None, :]
y, x = np.mgrid[:scan_y, :scan_x]
base = (
    1.0
    + 0.55 * np.exp(-((y - 2.2) ** 2 / 2.3 + (x - 6.7) ** 2 / 4.1))
    - 0.23 * np.exp(-((y - 5.8) ** 2 / 1.8 + (x - 2.1) ** 2 / 2.7))
    + 0.09 * np.sin(0.73 * y + 0.29 * x)
    + 0.04 * np.cos(0.21 * y - 0.61 * x)
).astype(np.float32)
top, left = padding_y // 2, padding_x // 2
stack = np.ones((len(indices), height, width), dtype=np.float32)
intended_content_shifts = []
for i, (qx, qy) in enumerate(indices):
    content_shift = (0.72 * (qx - 3) / 2, -0.57 * (qy - 3) / 2)
    intended_content_shifts.append(content_shift)
    operator = np.exp(
        -2j
        * np.pi
        * (
            np.fft.fftfreq(scan_y)[:, None] * content_shift[0]
            + np.fft.fftfreq(scan_x)[None, :] * content_shift[1]
        )
    )
    shifted = np.real(np.fft.ifft2(np.fft.fft2(base) * operator)).astype(np.float32)
    weight = np.average(shifted.ravel(), weights=window.ravel())
    stack[i, top : top + scan_y, left : left + scan_x] = (
        1 - window + window * shifted / weight
    )

base_mask = np.zeros((height, width), dtype=np.float32)
base_mask[top : top + scan_y, left : left + scan_x] = window
stack_mean = np.mean(stack)
mask_sum = np.sum(window) * len(indices)
initial_mask = np.broadcast_to(base_mask, stack.shape)
initial_recon_mask = np.mean(initial_mask, axis=0)
mask_inv = 1 - np.clip(initial_recon_mask, 0, 1)
initial_recon = (
    stack_mean * mask_inv + np.mean(stack * initial_mask, axis=0)
) / (initial_recon_mask + mask_inv)
initial_error = (
    np.sum(np.abs(stack - initial_recon[None]) * initial_mask)
    / mask_sum
    / stack_mean
)


def shift_fourier(images, shifts):
    qrow = np.fft.fftfreq(height).astype(np.float32)
    qcolumn = np.fft.fftfreq(width).astype(np.float32)
    out = np.empty_like(images, dtype=np.float32)
    for i, image in enumerate(images):
        operator = np.exp(
            -2j
            * np.pi
            * (
                qrow[:, None] * shifts[i, 0]
                + qcolumn[None, :] * shifts[i, 1]
            )
        )
        out[i] = np.real(np.fft.ifft2(np.fft.fft2(image) * operator)).astype(np.float32)
    return out


def level(alignment_bin):
    xy_center = (indices - np.median(indices, axis=0)).astype("float")
    grouped_indices = np.round(xy_center / alignment_bin + 0.5).astype("int")
    xy_vals = np.unique(grouped_indices, axis=0)
    order = np.argsort(np.sum(xy_vals**2, axis=1))
    groups = []
    raw = np.zeros((len(indices), 2), dtype=np.float32)
    group_shifts = []
    g_ref = np.fft.fft2(initial_recon)
    qrow = np.fft.fftfreq(height).astype(np.float32)
    qcolumn = np.fft.fftfreq(width).astype(np.float32)
    for number, group_index in enumerate(order):
        coordinate = xy_vals[group_index]
        members = np.flatnonzero(np.all(grouped_indices == coordinate, axis=1))
        groups.append([int(coordinate[0]), int(coordinate[1]), members.tolist()])
        g = np.fft.fft2(np.mean(stack[members], axis=0))
        correlation = np.real(np.fft.ifft2(g_ref * np.conj(g)))
        peak = np.unravel_index(correlation.argmax(), correlation.shape)
        shift = np.array(
            [
                (peak[0] + height / 2) % height - height / 2,
                (peak[1] + width / 2) % width - width / 2,
            ],
            dtype=np.float32,
        )
        group_shifts.append(shift.tolist())
        raw[members] = shift
        operator = np.exp(
            -2j
            * np.pi
            * (qrow[:, None] * shift[0] + qcolumn[None, :] * shift[1])
        )
        g_ref = g_ref * number / (number + 1) + (g * operator) / (number + 1)

    coefficients = np.linalg.lstsq(kxy, raw, rcond=None)[0]
    fitted = np.asarray(kxy @ coefficients, dtype=np.float32)
    masks = np.broadcast_to(base_mask, stack.shape).copy()
    shifted_stack = shift_fourier(stack, fitted)
    shifted_masks = shift_fourier(masks, fitted)
    shift_median = np.round(np.median(fitted, axis=0)).astype(int)
    fitted -= shift_median[None]
    shifted_stack = np.roll(shifted_stack, -shift_median, axis=(1, 2))
    shifted_masks = np.roll(shifted_masks, -shift_median, axis=(1, 2))
    recon_mask = np.mean(shifted_masks, axis=0)
    mask_inv = 1 - np.clip(recon_mask, 0, 1)
    aligned = (
        stack_mean * mask_inv + np.mean(shifted_stack * shifted_masks, axis=0)
    ) / (recon_mask + mask_inv)
    error = (
        np.sum(np.abs(shifted_stack - aligned[None]) * shifted_masks)
        / mask_sum
        / stack_mean
    )
    return {
        "alignmentBin": alignment_bin,
        "groups": groups,
        "groupShifts": group_shifts,
        "totalShifts": fitted.ravel().tolist(),
        "shiftedStack": shifted_stack.ravel().tolist(),
        "shiftedMasks": shifted_masks.ravel().tolist(),
        "reconstructionMask": recon_mask.ravel().tolist(),
        "alignedBF": aligned.ravel().tolist(),
        "error": float(error),
    }


def dft_upsample(image_corr, upsample_factor, xy_shift):
    rows, columns = image_corr.shape
    patch_size = int(np.ceil(1.5 * upsample_factor))
    column_frequencies = (
        np.fft.ifftshift(np.arange(columns)) - np.floor(columns / 2)
    )
    row_frequencies = np.fft.ifftshift(np.arange(rows)) - np.floor(rows / 2)
    column_kernel = np.exp(
        (-1j * 2 * np.pi / (columns * upsample_factor))
        * np.outer(
            column_frequencies,
            np.arange(patch_size) - xy_shift[1],
        )
    )
    row_kernel = np.exp(
        (-1j * 2 * np.pi / (rows * upsample_factor))
        * np.outer(
            np.arange(patch_size) - xy_shift[0],
            row_frequencies,
        )
    )
    return np.real(row_kernel @ image_corr @ column_kernel)


def align_images_fourier(g_ref, g, upsample_factor=8):
    correlation = g_ref * np.conj(g)
    correlation_real = np.real(np.fft.ifft2(correlation))
    row, column = np.unravel_index(correlation_real.argmax(), correlation.shape)
    row_indices = np.mod(row + np.arange(-1, 2), correlation.shape[0]).astype(int)
    column_indices = np.mod(
        column + np.arange(-1, 2), correlation.shape[1]
    ).astype(int)
    row_values = correlation_real[row_indices, column]
    column_values = correlation_real[row, column_indices]
    row_offset = (row_values[2] - row_values[0]) / (
        4 * row_values[1] - 2 * row_values[2] - 2 * row_values[0]
    )
    column_offset = (column_values[2] - column_values[0]) / (
        4 * column_values[1]
        - 2 * column_values[2]
        - 2 * column_values[0]
    )
    shift = np.array(
        [
            np.round((row + row_offset) * 2) / 2,
            np.round((column + column_offset) * 2) / 2,
        ]
    )
    shift = np.round(shift * upsample_factor) / upsample_factor
    global_shift = np.trunc(np.ceil(upsample_factor * 1.5) / 2)
    center = global_shift - upsample_factor * shift
    patch = np.conj(
        dft_upsample(np.conj(correlation), upsample_factor, center)
    )
    sub = np.asarray(np.unravel_index(patch.argmax(), patch.shape), dtype=float)
    sub_row, sub_column = sub.astype(int)
    if (
        0 < sub_row < patch.shape[0] - 1
        and 0 < sub_column < patch.shape[1] - 1
    ):
        values = np.real(
            patch[
                sub_row - 1 : sub_row + 2,
                sub_column - 1 : sub_column + 2,
            ]
        )
        row_polish = (values[2, 1] - values[0, 1]) / (
            4 * values[1, 1] - 2 * values[2, 1] - 2 * values[0, 1]
        )
        column_polish = (values[1, 2] - values[1, 0]) / (
            4 * values[1, 1] - 2 * values[1, 2] - 2 * values[1, 0]
        )
    else:
        row_polish = column_polish = 0
    return shift + (sub - global_shift + [row_polish, column_polish]) / upsample_factor


def multilevel_alignment(schedule):
    current_stack = stack.copy()
    current_masks = np.broadcast_to(base_mask, stack.shape).copy()
    current_recon = initial_recon.copy()
    total_shifts = np.zeros((len(indices), 2), dtype=np.float32)
    levels = []
    qrow = np.fft.fftfreq(height).astype(np.float32)
    qcolumn = np.fft.fftfreq(width).astype(np.float32)

    for alignment_bin in schedule:
        xy_center = (indices - np.median(indices, axis=0)).astype("float")
        grouped_indices = np.round(xy_center / alignment_bin + 0.5).astype("int")
        xy_vals = np.unique(grouped_indices, axis=0)
        order = np.argsort(np.sum(xy_vals**2, axis=1))
        g_ref = np.fft.fft2(current_recon)
        updates = np.zeros((len(indices), 2), dtype=np.float32)
        groups = []
        group_shifts = []
        for number, group_index in enumerate(order):
            coordinate = xy_vals[group_index]
            members = np.flatnonzero(np.all(grouped_indices == coordinate, axis=1))
            groups.append([int(coordinate[0]), int(coordinate[1]), members.tolist()])
            g = np.fft.fft2(np.mean(current_stack[members], axis=0))
            shift = align_images_fourier(g_ref, g, 8)
            shift = np.asarray(
                [
                    (shift[0] + height / 2) % height - height / 2,
                    (shift[1] + width / 2) % width - width / 2,
                ],
                dtype=np.float32,
            )
            group_shifts.append(shift.tolist())
            updates[members] = shift
            shift_operator = np.exp(
                -2j
                * np.pi
                * (
                    qrow[:, None] * shift[0]
                    + qcolumn[None, :] * shift[1]
                )
            )
            g_ref = (
                g_ref * number / (number + 1)
                + g * shift_operator / (number + 1)
            )

        candidate = total_shifts + updates
        coefficients = np.linalg.lstsq(kxy, candidate, rcond=None)[0]
        fitted = np.asarray(kxy @ coefficients, dtype=np.float32)
        incremental = fitted - total_shifts
        current_stack = shift_fourier(current_stack, incremental)
        current_masks = shift_fourier(current_masks, incremental)
        total_shifts += incremental
        shift_median = np.round(np.median(total_shifts, axis=0)).astype(int)
        total_shifts -= shift_median[None]
        current_stack = np.roll(current_stack, -shift_median, axis=(1, 2))
        current_masks = np.roll(current_masks, -shift_median, axis=(1, 2))
        recon_mask = np.mean(current_masks, axis=0)
        mask_inv = 1 - np.clip(recon_mask, 0, 1)
        current_recon = (
            stack_mean * mask_inv
            + np.mean(current_stack * current_masks, axis=0)
        ) / (recon_mask + mask_inv)
        error = (
            np.sum(np.abs(current_stack - current_recon[None]) * current_masks)
            / mask_sum
            / stack_mean
        )
        levels.append(
            {
                "alignmentBin": int(alignment_bin),
                "groups": groups,
                "groupShifts": group_shifts,
                "totalShifts": total_shifts.ravel().tolist(),
                "shiftedStack": current_stack.ravel().tolist(),
                "shiftedMasks": current_masks.ravel().tolist(),
                "reconstructionMask": recon_mask.ravel().tolist(),
                "alignedBF": current_recon.ravel().tolist(),
                "error": float(error),
            }
        )
    return levels


diameter = int(max(np.ptp(indices[:, 0]), np.ptp(indices[:, 1])) + 1)
schedule = (
    2 ** np.arange(np.ceil(np.log2(diameter)).astype(int))[::-1]
).tolist()

json.dump(
    {
        "scanShape": [scan_y, scan_x],
        "stackShape": [len(indices), height, width],
        "detectorIndices": indices.tolist(),
        "reciprocalVectors": kxy.ravel().tolist(),
        "edgeWindow": window.ravel().tolist(),
        "normalizedStack": stack.ravel().tolist(),
        "incoherentBF": initial_recon.ravel().tolist(),
        "initialError": float(initial_error),
        "defaultSchedule": schedule,
        "intendedContentShifts": np.asarray(intended_content_shifts).ravel().tolist(),
        "levels": [level(schedule[0]), level(1)],
        "multilevel": multilevel_alignment(schedule),
    },
    sys.stdout,
    separators=(",", ":"),
)
print()
