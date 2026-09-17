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
from scipy.ndimage import binary_fill_holes, distance_transform_edt

ROOT = Path(__file__).resolve().parents[2]
PY4DSTEM_ORIGIN = ROOT / "References/py4DSTEM-dev/py4DSTEM/process/calibration/origin.py"
PY4DSTEM_DATACUBE = ROOT / "References/py4DSTEM-dev/py4DSTEM/datacube/datacube.py"


def assert_source_contract() -> None:
    datacube = PY4DSTEM_DATACUBE.read_text()
    for expression in [
        # DataCube.get_beamstop_mask — the exact steps BeamstopMask.swift ports.
        "int_sort = np.sort(im.ravel())",
        "intensity_threshold = int_sort[ind]",
        "mask_beamstop = im >= intensity_threshold",
        "mask_beamstop = np.logical_not(binary_fill_holes(np.logical_not(mask_beamstop)))",
        "mask_beamstop = binary_fill_holes(mask_beamstop)",
        "mask_beamstop = distance_transform_edt(mask_beamstop) < distance_edge",
    ]:
        if expression not in datacube:
            raise RuntimeError(
                f"py4DSTEM get_beamstop_mask contract changed: {expression!r} "
                "no longer found in datacube.py — re-read the current source "
                "before trusting BeamstopMask.swift"
            )
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


def beamstop_mask(im: np.ndarray, threshold: float = 0.25,
                  distance_edge: float = 2.0, include_edges: bool = True) -> np.ndarray:
    """Single-image transcription of DataCube.get_beamstop_mask (mean-DP path,
    sigma=0, scale_radial=None), using the SAME scipy morphology py4DSTEM does —
    so this is the truth, not a re-derivation. Returns True under the beamstop.
    """
    int_sort = np.sort(im.ravel())
    ind = int(np.round(np.clip(int_sort.shape[0] * threshold, 0, int_sort.shape[0])))
    intensity_threshold = int_sort[min(ind, int_sort.shape[0] - 1)]
    mask_beamstop = im >= intensity_threshold
    mask_beamstop = np.logical_not(binary_fill_holes(np.logical_not(mask_beamstop)))
    mask_beamstop = binary_fill_holes(mask_beamstop)
    if include_edges:
        mask_beamstop[0, :] = False
        mask_beamstop[:, 0] = False
        mask_beamstop[-1, :] = False
        mask_beamstop[:, -1] = False
    return distance_transform_edt(mask_beamstop) < distance_edge


def synthetic_mean_dp(H: int, W: int) -> np.ndarray:
    """A morphology-exercising intensity image for the beamstop-mask leg (this
    tests get_beamstop_mask, not Friedel recovery — the clean/masked legs cover
    that). A bright centre dimming smoothly outward, a vertical beamstop bar, and
    a dark hole enclosed by the bright centre. This isolates three of the four
    steps: a mutation to the percentile threshold, to the pattern-region
    fill-holes (step 3), or to the distance-transform dilation disagrees with
    scipy here. The fourth step — the dim-region fill-holes (step 2) — does not
    isolate on a small synthetic (its effect is swallowed by the 2 px dilation),
    but it IS exercised: BeamstopMask.swift is verified pixel-identical to scipy
    on the real Au_ref beamstop cube (1453 px), where step 2 moves 3 px and step
    3 moves 157 (this session's diagnostic, not a committed cube)."""
    yy, xx = np.meshgrid(np.arange(H, dtype=np.float64), np.arange(W, dtype=np.float64), indexing="ij")
    r = np.sqrt((yy - H / 2) ** 2 + (xx - W / 2) ** 2)
    dp = 1000.0 * np.exp(-(r**2) / 30.0) + 25.0
    dp *= np.exp(-r / 50.0)                                  # smooth dim falloff, no rings
    dp[:, W // 2 - 1:W // 2 + 1] = 2.0                       # vertical beamstop bar
    dp[H // 2 - 4, W // 2 + 5] = 2.0                         # dark hole in the bright centre (step 3)
    dp[H // 2 - 5, W // 2 + 5] = 2.0
    return dp.astype(np.float32)


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

    # Beamstop-mask leg: a synthetic mean DP and py4DSTEM/scipy's mask of it.
    bs_dp = synthetic_mean_dp(H, W)
    bs_mask = beamstop_mask(bs_dp.astype(np.float64))   # True = beamstop

    print(
        json.dumps(
            {
                "height": H,
                "width": W,
                "beamstopDP": bs_dp.ravel().astype(np.float32).tolist(),
                "beamstopMask": bs_mask.ravel().astype(bool).tolist(),
                "beamstopCount": int(bs_mask.sum()),
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
