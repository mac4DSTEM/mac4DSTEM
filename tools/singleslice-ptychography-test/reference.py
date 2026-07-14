#!/usr/bin/env python3
"""Source-lock the first py4DSTEM single-slice GD operator slice."""

import json
import pathlib
import sys

import numpy as np

repo = pathlib.Path(__file__).resolve().parents[2]
methods = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/ptychographic_methods.py").read_text()
base = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/phase_base_class.py").read_text()
single = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/singleslice_ptychography.py").read_text()
constraints = (repo / "References/py4DSTEM-dev/py4DSTEM/process/phase/ptychographic_constraints.py").read_text()
for contract in (
    "fourier_modified_overlap = amplitudes * xp.exp(",
    "fourier_modified_overlap = fourier_modified_overlap - fourier_overlap",
    "exit_waves = xp.fft.ifft2(fourier_modified_overlap)",
    "xp.conj(shifted_probes) * exit_waves",
    "xp.conj(object_patches) * exit_waves",
    "((1 - normalization_min) * probe_normalization) ** 2",
):
    if contract not in methods:
        raise SystemExit(f"py4DSTEM GD contract changed: {contract}")
for contract in (
    "projection_x = 1 - projection_a - projection_b",
    "projection_y = 1 - projection_c",
    "factor_to_be_projected = projection_c * overlap + projection_y * exit_waves",
    "projection_x * exit_waves\n            + projection_a * overlap",
    "current_object = (\n                self._sum_overlapping_patches_bincounts(\n                    xp.conj(shifted_probes) * exit_waves",
):
    if contract not in methods:
        raise SystemExit(f"py4DSTEM projection contract changed: {contract}")
for contract in (
    "x0 = xp_storage.round(positions_px[:, 0]).astype(\"int\")",
    "x_ind = xp_storage.fft.fftfreq(roi_shape[0], d=1 / roi_shape[0]).astype(\"int\")",
    "counts = xp.bincount(",
):
    if contract not in base:
        raise SystemExit(f"py4DSTEM patch contract changed: {contract}")
if "error /= self._mean_diffraction_intensity * self._num_diffraction_patterns" not in single:
    raise SystemExit("py4DSTEM error normalization changed")
for contract in (
    "amplitude = xp.minimum(xp.abs(current_object), 1.0)",
    "get_CoM(\n            probe_intensity, device=self._device, corner_centered=True",
    "sigma = np.sqrt(np.pi) / relative_width",
    "tophat_mask = 0.5 * (1 - erf(sigma * r / (1 - r**2)))",
    "normalization = xp.sqrt(current_probe_sum / updated_probe_sum)",
):
    if contract not in constraints:
        raise SystemExit(f"py4DSTEM constraint contract changed: {contract}")

rng = np.random.default_rng(17)
probe_shape = (4, 6)
object_shape = (9, 11)
positions = np.array([[2.25, 3.5], [2.75, 7.1], [6.2, 3.2], [6.6, 7.35]], dtype=np.float32)
y, x = np.mgrid[: object_shape[0], : object_shape[1]]
true_object = np.exp(1j * (0.18 * np.sin(0.5 * y) + 0.12 * np.cos(0.37 * x))).astype(np.complex64)
py, px = np.mgrid[: probe_shape[0], : probe_shape[1]]
probe_true = (np.exp(-((py - 1.3) ** 2 / 2.2 + (px - 2.4) ** 2 / 3.7))
              * np.exp(1j * (0.08 * py - 0.05 * px))).astype(np.complex64)
probe_initial = (probe_true * np.exp(1j * 0.12) * 0.92).astype(np.complex64)
object_initial = np.ones(object_shape, dtype=np.complex64)


def offsets(n):
    return np.fft.fftfreq(n, d=1 / n).astype(int)


def shifted_probe(probe, position):
    fractional = position - np.round(position)
    ky = np.fft.fftfreq(probe_shape[0])[:, None]
    kx = np.fft.fftfreq(probe_shape[1])[None, :]
    return np.fft.ifft2(np.fft.fft2(probe)
        * np.exp(-2j * np.pi * (ky * fractional[0] + kx * fractional[1])))


def patches(obj, probe, position):
    center = np.round(position).astype(int)
    rows = (center[0] + offsets(probe_shape[0])) % object_shape[0]
    cols = (center[1] + offsets(probe_shape[1])) % object_shape[1]
    patch = obj[rows[:, None], cols[None, :]]
    return patch, rows, cols


amplitudes = []
for position in positions:
    shifted = shifted_probe(probe_true, position)
    patch, _, _ = patches(true_object, shifted, position)
    amplitudes.append(np.abs(np.fft.fft2(shifted * patch)))
amplitudes = np.asarray(amplitudes, dtype=np.float32)


def constrain_probe_com(probe):
    rows = np.fft.fftfreq(probe.shape[0], 1 / probe.shape[0])[:, None]
    columns = np.fft.fftfreq(probe.shape[1], 1 / probe.shape[1])[None, :]
    intensity = np.abs(probe) ** 2
    com = np.array([
        np.sum(rows * intensity) / np.sum(intensity),
        np.sum(columns * intensity) / np.sum(intensity),
    ])
    ky = np.fft.fftfreq(probe.shape[0])[:, None]
    kx = np.fft.fftfreq(probe.shape[1])[None, :]
    return np.fft.ifft2(np.fft.fft2(probe)
        * np.exp(-2j * np.pi * (ky * -com[0] + kx * -com[1])))


def constrain_probe_amplitude(probe, relative_radius=0.42, relative_width=0.09):
    from scipy.special import erf
    original_sum = np.sum(np.abs(probe) ** 2)
    rows = np.fft.fftfreq(probe.shape[0])[:, None]
    columns = np.fft.fftfreq(probe.shape[1])[None, :]
    radius = np.hypot(rows, columns) - relative_radius
    sigma = np.sqrt(np.pi) / relative_width
    mask = 0.5 * (1 - erf(sigma * radius / (1 - radius**2)))
    updated = probe * mask
    return updated * np.sqrt(original_sum / np.sum(np.abs(updated) ** 2))


def reconstruct(iterations=3, step_size=0.5, normalization_min=0.7,
                constrained=False, method="GD", alpha=1.0):
    obj = object_initial.copy()
    probe = probe_initial.copy()
    errors = []
    total_intensity = np.sum(amplitudes.astype(np.float64) ** 2)
    exit_waves = np.zeros_like(amplitudes, dtype=np.complex64)
    for iteration in range(iterations):
        obj_num = np.zeros(object_shape, dtype=np.complex64)
        probe_norm = np.zeros(object_shape, dtype=np.float32)
        probe_num = np.zeros(probe_shape, dtype=np.complex64)
        obj_norm = np.zeros(probe_shape, dtype=np.float32)
        error = 0.0
        for index, position in enumerate(positions):
            shifted = shifted_probe(probe, position)
            patch, rows, cols = patches(obj, shifted, position)
            overlap = shifted * patch
            if method == "DM_AP":
                projection_a, projection_b, projection_c = -alpha, 1.0, 1 + alpha
                projection_x = 1 - projection_a - projection_b
                projection_y = 1 - projection_c
                previous = overlap.copy() if iteration == 0 else exit_waves[index]
                factor = projection_c * overlap + projection_y * previous
                fourier = np.fft.fft2(factor)
            else:
                fourier = np.fft.fft2(overlap)
            farfield = np.abs(fourier)
            error += np.sum(np.abs(amplitudes[index] - farfield) ** 2)
            projected = np.fft.ifft2(
                amplitudes[index] * np.exp(1j * np.angle(fourier))
            )
            if method == "DM_AP":
                exit_wave = (projection_x * previous + projection_a * overlap
                             + projection_b * projected)
                exit_waves[index] = exit_wave
            else:
                exit_wave = projected - overlap
            for r, object_row in enumerate(rows):
                for c, object_col in enumerate(cols):
                    obj_num[object_row, object_col] += np.conj(shifted[r, c]) * exit_wave[r, c]
                    probe_norm[object_row, object_col] += np.abs(shifted[r, c]) ** 2
            probe_num += np.conj(patch) * exit_wave
            obj_norm += np.abs(patch) ** 2
        probe_inv = 1 / np.sqrt(1e-16
            + ((1 - normalization_min) * probe_norm) ** 2
            + (normalization_min * np.max(probe_norm)) ** 2)
        object_inv = 1 / np.sqrt(1e-16
            + ((1 - normalization_min) * obj_norm) ** 2
            + (normalization_min * np.max(obj_norm)) ** 2)
        if method == "DM_AP":
            obj = obj_num * probe_inv
            probe = probe_num * object_inv
        else:
            obj += step_size * obj_num * probe_inv
            probe += step_size * probe_num * object_inv
        if constrained:
            amplitude = np.minimum(np.abs(obj), 1.0)
            obj = amplitude * np.exp(1j * np.angle(obj))
            probe = constrain_probe_com(probe)
            probe = constrain_probe_amplitude(probe)
        errors.append(float(error / total_intensity))
    row0, column0 = np.floor(positions.min(0)).astype(int)
    row1, column1 = np.ceil(positions.max(0)).astype(int)
    crop = obj[row0:row1, column0:column1]
    return obj, probe, np.array(errors, dtype=np.float32), crop


obj, probe, errors, crop = reconstruct()
constrained_obj, constrained_probe, constrained_errors, _ = reconstruct(constrained=True)
dm_obj, dm_probe, dm_errors, dm_crop = reconstruct(method="DM_AP", alpha=0.8)
json.dump({
    "scanShape": [2, 2], "probeShape": list(probe_shape),
    "objectShape": list(object_shape), "positions": positions.ravel().tolist(),
    "amplitudes": amplitudes.ravel().tolist(),
    "initialObjectReal": object_initial.real.ravel().tolist(),
    "initialObjectImag": object_initial.imag.ravel().tolist(),
    "initialProbeReal": probe_initial.real.ravel().tolist(),
    "initialProbeImag": probe_initial.imag.ravel().tolist(),
    "iterations": 3, "stepSize": 0.5, "normalizationMinimum": 0.7,
    "errors": errors.tolist(), "objectReal": obj.real.ravel().tolist(),
    "objectImag": obj.imag.ravel().tolist(), "probeReal": probe.real.ravel().tolist(),
    "probeImag": probe.imag.ravel().tolist(), "cropShape": list(crop.shape),
    "cropPhase": np.angle(crop).astype(np.float32).ravel().tolist(),
    "cropAmplitude": np.abs(crop).astype(np.float32).ravel().tolist(),
    "constrainedErrors": constrained_errors.tolist(),
    "constrainedObjectReal": constrained_obj.real.astype(np.float32).ravel().tolist(),
    "constrainedObjectImag": constrained_obj.imag.astype(np.float32).ravel().tolist(),
    "constrainedProbeReal": constrained_probe.real.astype(np.float32).ravel().tolist(),
    "constrainedProbeImag": constrained_probe.imag.astype(np.float32).ravel().tolist(),
    "centeredProbePhase": np.angle(np.fft.fftshift(constrained_probe)).astype(np.float32).ravel().tolist(),
    "centeredProbeAmplitude": np.abs(np.fft.fftshift(constrained_probe)).astype(np.float32).ravel().tolist(),
    "dmErrors": dm_errors.tolist(),
    "dmObjectReal": dm_obj.real.astype(np.float32).ravel().tolist(),
    "dmObjectImag": dm_obj.imag.astype(np.float32).ravel().tolist(),
    "dmProbeReal": dm_probe.real.astype(np.float32).ravel().tolist(),
    "dmProbeImag": dm_probe.imag.astype(np.float32).ravel().tolist(),
    "dmCropPhase": np.angle(dm_crop).astype(np.float32).ravel().tolist(),
    "dmCropAmplitude": np.abs(dm_crop).astype(np.float32).ravel().tolist(),
}, sys.stdout, separators=(",", ":"))
print()
