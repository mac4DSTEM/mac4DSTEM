#!/usr/bin/env python3
"""Source-locked parity fixture for Core/Analysis/FriedelOrigin.swift.

FriedelOrigin ports py4DSTEM's `get_origin_friedel`
(References/py4DSTEM-dev/py4DSTEM/process/calibration/origin.py). This file:

1. `assert_source_contract()` — the hard gate. It raises if the exact
   expressions FriedelOrigin.swift transcribes have drifted from the pinned
   source, so a py4DSTEM update cannot silently invalidate the port.
2. `friedel_origin()` — a frozen, single-pattern transcription of that
   function (both the no-beamstop `cc = Re(ifft2(fft2(im)**2))` form and the
   masked three-term form), every line traceable to a checked expression. It
   is NEVER computed by calling the Swift code — it is the independent truth.
3. Two synthetic patterns with a PLANTED, sub-pixel, asymmetric origin: one
   clean, one with a rectangular beamstop knocked out and a matching mask. The
   pattern is centrosymmetric about the planted origin by construction, so the
   method must recover it — and Swift must agree with this transcription.

main.swift asserts BOTH: parity (Swift == this transcription, tight) and
recovery (both land on the planted origin, loose). Do not loosen either
tolerance to paper over a disagreement, and do not edit this transcription to
chase Swift's answer — fix the port or file the frame question, as the
rotation harness's leg (b) did.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PY4DSTEM_ORIGIN = ROOT / "References/py4DSTEM-dev/py4DSTEM/process/calibration/origin.py"


def assert_source_contract() -> None:
    source = PY4DSTEM_ORIGIN.read_text()
    required = [
        # The zero-pad to double size (both axes, appended).
        "((0, datacube.data.shape[2]), (0, datacube.data.shape[3])),",
        # No-mask self-correlation: G**2 then real ifft2.
        "cc = xp.real(xp.fft.ifft2(G**2))",
        # Masked three-term normalisation.
        "term1 = xp.real(xp.fft.ifft2(xp.fft.fft2(im) ** 2) * xp.fft.ifft2(M**2))",
        "term2 = xp.real(xp.fft.ifft2(xp.fft.fft2(im**2) * M))",
        "term3 = xp.real(xp.fft.ifft2(xp.fft.fft2(im * mask_pad)))",
        "cc = (term1 - term3) / (term2 - term3)",
        # The mask padded with 1.0 (constant_values=1.0).
        "constant_values=(1.0, 1.0),",
        # Argmax + the parabolic subpixel shift on each axis.
        "x, y = xp.unravel_index(xp.argmax(cc), im.shape)",
        "dx = (cc[x + 1, y] - cc[x - 1, y]) / (",
        "4.0 * cc[x, y] - 2.0 * cc[x + 1, y] - 2.0 * cc[x - 1, y]",
        # Correlation peak halved and folded back into the pattern.
        "qx0[rx, ry] = (x / 2) % datacube.data.shape[2]",
        "qy0[rx, ry] = (y / 2) % datacube.data.shape[3]",
    ]
    for expression in required:
        if expression not in source:
            raise RuntimeError(
                f"py4DSTEM get_origin_friedel contract changed: {expression!r} "
                "no longer found in origin.py — re-read the current source "
                "before trusting this transcription"
            )


def friedel_origin(im: np.ndarray, mask: np.ndarray | None) -> tuple[float, float]:
    """Single-pattern transcription of get_origin_friedel. `im` shape (H, W)
    = (datacube axis 2, axis 3). Returns (qx0, qy0): qx0 along axis 0 (rows),
    qy0 along axis 1 (cols) — the pattern's own frame, the app swap applied at
    the Swift call site, not here.
    """
    H, W = im.shape
    im = np.pad(im, ((0, H), (0, W)))
    if mask is None:
        G = np.fft.fft2(im)
        cc = np.real(np.fft.ifft2(G**2))
    else:
        mask_pad = np.pad(mask.astype("float"), ((0, H), (0, W)), constant_values=(1.0, 1.0))
        M = np.fft.fft2(mask_pad)
        term1 = np.real(np.fft.ifft2(np.fft.fft2(im) ** 2) * np.fft.ifft2(M**2))
        term2 = np.real(np.fft.ifft2(np.fft.fft2(im**2) * M))
        term3 = np.real(np.fft.ifft2(np.fft.fft2(im * mask_pad)))
        cc = (term1 - term3) / (term2 - term3)

    x, y = np.unravel_index(np.argmax(cc), im.shape)
    dx = (cc[x + 1, y] - cc[x - 1, y]) / (
        4.0 * cc[x, y] - 2.0 * cc[x + 1, y] - 2.0 * cc[x - 1, y]
    )
    dy = (cc[x, y + 1] - cc[x, y - 1]) / (
        4.0 * cc[x, y] - 2.0 * cc[x, y + 1] - 2.0 * cc[x, y - 1]
    )
    x = x.astype("float") + dx
    y = y.astype("float") + dy
    # py4DSTEM folds by the ORIGINAL detector size (shape[2], shape[3] = H, W).
    return float((x / 2) % H), float((y / 2) % W)


def centrosymmetric_pattern(H: int, W: int, cx: float, cy: float) -> np.ndarray:
    """A diffraction pattern that is centrosymmetric about (cx, cy): a bright
    central beam plus Friedel-paired disks at ±(u, v). Truth is (cx, cy),
    chosen here, not read back from any correlation.
    """
    yy, xx = np.meshgrid(np.arange(H, dtype=np.float64), np.arange(W, dtype=np.float64), indexing="ij")

    def gaussian(r0: float, c0: float, amp: float, sigma: float) -> np.ndarray:
        return amp * np.exp(-(((yy - r0) ** 2 + (xx - c0) ** 2) / (2 * sigma**2)))

    pattern = gaussian(cx, cy, 1000.0, 2.2)  # central beam
    # Friedel pairs at ±(u, v) about the centre.
    for u, v, amp in [(6.0, 3.0, 400.0), (-2.0, 8.0, 260.0), (9.0, -5.0, 180.0)]:
        pattern += gaussian(cx + u, cy + v, amp, 1.8)
        pattern += gaussian(cx - u, cy - v, amp, 1.8)
    return pattern.astype(np.float32)


def main() -> None:
    assert_source_contract()

    H, W = 32, 32
    cx, cy = 15.3, 17.6  # planted origin: sub-pixel, off-centre, asymmetric

    clean = centrosymmetric_pattern(H, W, cx, cy)
    clean_qx, clean_qy = friedel_origin(clean.astype(np.float64), None)

    # Beamstop: a rectangular bar knocked to zero, with a matching mask
    # (False under the bar). Placed off the centre so it occludes real signal.
    masked = clean.copy()
    mask = np.ones((H, W), dtype=bool)
    masked[10:14, 6:26] = 0.0
    mask[10:14, 6:26] = False
    masked_qx, masked_qy = friedel_origin(masked.astype(np.float64),
                                          mask.astype(np.float64))

    print(
        json.dumps(
            {
                "height": H,
                "width": W,
                "plantedRow": cx,
                "plantedCol": cy,
                "cleanPattern": clean.ravel().astype(np.float32).tolist(),
                "cleanRow": clean_qx,
                "cleanCol": clean_qy,
                "maskedPattern": masked.ravel().astype(np.float32).tolist(),
                "mask": mask.ravel().astype(bool).tolist(),
                "maskedRow": masked_qx,
                "maskedCol": masked_qy,
            }
        )
    )


if __name__ == "__main__":
    main()
