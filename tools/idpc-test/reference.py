#!/usr/bin/env python3
"""Source-locked DPC-angle and non-square quantitative iDPC fixture."""

from __future__ import annotations

import colorsys
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
PY4DSTEM_DPC = ROOT / "References/py4DSTEM-dev/py4DSTEM/process/phase/dpc.py"
PY4DSTEM_BASE = (
    ROOT / "References/py4DSTEM-dev/py4DSTEM/process/phase/phase_base_class.py"
)


def assert_source_contract() -> None:
    dpc = PY4DSTEM_DPC.read_text()
    base = PY4DSTEM_BASE.read_text()
    required = {
        "padding_factor: float = 2": dpc,
        "d=self._scan_sampling[0]": dpc,
        "d=self._scan_sampling[1]": dpc,
        "* reciprocal_sampling[0]": base,
        "* reciprocal_sampling[1]": base,
    }
    for expression, source in required.items():
        if expression not in source:
            raise RuntimeError(f"py4DSTEM DPC contract changed: {expression}")


def integrate(
    com: np.ndarray,
    row_sampling: float,
    column_sampling: float,
    com_to_gradient: float,
    regularization: float,
    padding_factor: int,
) -> np.ndarray:
    height, width, _ = com.shape
    field_x = (com[..., 0] * com_to_gradient).astype(np.float32)
    field_y = (com[..., 1] * com_to_gradient).astype(np.float32)
    field_x -= field_x.mean(dtype=np.float32)
    field_y -= field_y.mean(dtype=np.float32)

    ny, nx = height * padding_factor, width * padding_factor
    y0, x0 = (ny - height) // 2, (nx - width) // 2
    padded_x = np.zeros((ny, nx), dtype=np.float32)
    padded_y = np.zeros((ny, nx), dtype=np.float32)
    padded_x[y0 : y0 + height, x0 : x0 + width] = field_x
    padded_y[y0 : y0 + height, x0 : x0 + width] = field_y

    x_ft = np.fft.fft2(padded_x)
    y_ft = np.fft.fft2(padded_y)
    qx = np.fft.fftfreq(nx, d=column_sampling)
    qy = np.fft.fftfreq(ny, d=row_sampling)
    qx_grid, qy_grid = np.meshgrid(qx, qy)
    q2 = qx_grid**2 + qy_grid**2
    eps = regularization * (
        (0.5 / column_sampling) ** 2 + (0.5 / row_sampling) ** 2
    )
    denominator = 1j * 2 * np.pi * (q2 + eps)
    phase_ft = np.zeros_like(x_ft)
    nonzero = q2 != 0
    phase_ft[nonzero] = (
        qx_grid[nonzero] * x_ft[nonzero]
        + qy_grid[nonzero] * y_ft[nonzero]
    ) / denominator[nonzero]
    phase = np.fft.ifft2(phase_ft).real[y0 : y0 + height, x0 : x0 + width]
    phase -= phase.mean()
    return phase.astype(np.float32)


def main() -> None:
    assert_source_contract()
    height, width = 5, 7
    row_sampling, column_sampling = 2.0, 3.0
    reciprocal_sampling = 0.025
    y, x = np.mgrid[:height, :width]

    phase = (
        0.7 * np.sin(2 * np.pi * x / width)
        + 0.4 * np.cos(2 * np.pi * y / height)
        + 0.2 * np.sin(2 * np.pi * (x / width + y / height))
    )
    gradient_x = (
        0.7 * (2 * np.pi / (width * column_sampling)) * np.cos(2 * np.pi * x / width)
        + 0.2
        * (2 * np.pi / (width * column_sampling))
        * np.cos(2 * np.pi * (x / width + y / height))
    )
    gradient_y = (
        -0.4 * (2 * np.pi / (height * row_sampling)) * np.sin(2 * np.pi * y / height)
        + 0.2
        * (2 * np.pi / (height * row_sampling))
        * np.cos(2 * np.pi * (x / width + y / height))
    )
    com = np.stack(
        [
            gradient_x / (2 * np.pi * reciprocal_sampling) + 0.31,
            gradient_y / (2 * np.pi * reciprocal_sampling) - 0.27,
        ],
        axis=-1,
    ).astype(np.float32)

    periodic = integrate(
        com,
        row_sampling,
        column_sampling,
        2 * np.pi * reciprocal_sampling,
        regularization=0,
        padding_factor=1,
    )
    padded = integrate(
        com,
        row_sampling,
        column_sampling,
        2 * np.pi * reciprocal_sampling,
        regularization=1e-4,
        padding_factor=2,
    )
    qualitative = integrate(
        com,
        row_sampling=1,
        column_sampling=1,
        com_to_gradient=1,
        regularization=1e-4,
        padding_factor=2,
    )
    # The first two cases pin both signed-zero forms to canonical +0. The
    # remaining sign-discriminating directions avoid only symmetric axes, and
    # the final case forces the production wrap into [0, 2π). NumPy's arctan2
    # is the independent radian reference. A normalized-turn implementation
    # differs from every nonzero expected value below by much more than tolerance.
    angle_com = np.asarray(
        [[1, 0.0], [1, -0.0], [0, 1], [-1, 1], [1, -1]], dtype=np.float32
    )
    expected_angle_radians = np.mod(
        np.arctan2(angle_com[:, 1], angle_com[:, 0]), 2 * np.pi
    ).astype(np.float32)
    expected_angle_radians[expected_angle_radians == 0] = 0.0

    # A separate, non-cardinal vector field pins the display-only hue path.
    # `colorsys` is an independent HSV implementation; the expected hue stays
    # in normalized turns even though the scalar angle product is now radians.
    color_com = np.asarray(
        [[1.0, 0.25], [-0.4, 0.7], [0.3, -0.9], [-0.8, -0.2]],
        dtype=np.float32,
    )
    magnitudes = np.linalg.norm(color_com, axis=1)
    p99 = np.sort(magnitudes)[int((len(magnitudes) - 1) * 0.99)]
    values = np.minimum(magnitudes / p99, 1.0)
    expected_color_rgba: list[int] = []
    for vector, value in zip(color_com, values):
        hue = (np.arctan2(vector[1], vector[0]) / (2 * np.pi) + 0.5) % 1.0
        rgb = colorsys.hsv_to_rgb(float(hue), 1.0, float(value))
        expected_color_rgba.extend([*(int(channel * 255) for channel in rgb), 255])

    print(
        json.dumps(
            {
                "width": width,
                "height": height,
                "rowSamplingAngstrom": row_sampling,
                "columnSamplingAngstrom": column_sampling,
                "reciprocalAngstromPerDetectorPixel": reciprocal_sampling,
                "com": com.ravel().tolist(),
                "expectedPhase": (phase - phase.mean()).astype(np.float32).ravel().tolist(),
                "periodic": periodic.ravel().tolist(),
                "zeroPadded": padded.ravel().tolist(),
                "qualitative": qualitative.ravel().tolist(),
                "angleCOM": angle_com.ravel().tolist(),
                "expectedAngleRadians": expected_angle_radians.tolist(),
                "colorCOM": color_com.ravel().tolist(),
                "expectedColorRGBA": expected_color_rgba,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
