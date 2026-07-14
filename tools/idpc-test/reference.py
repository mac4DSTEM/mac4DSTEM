#!/usr/bin/env python3
"""Source-locked non-square quantitative iDPC fixture."""

from __future__ import annotations

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
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
