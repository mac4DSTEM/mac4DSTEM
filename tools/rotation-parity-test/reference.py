#!/usr/bin/env python3
"""Source-locked rotation-parity fixture for RotationCalibration.swift.

Two legs, both computed here, never by calling the code under test:

(a) ANALYTIC RECOVERY (floor). The gradient of a known scalar potential,
    rotated by a PLANTED 37.2 deg — asymmetric on purpose (0/45/90 let a sign
    flip AND a dropped transpose both survive, the S8 lesson,
    docs/decisions/030-lessons-promoted-from-the-archive.md) — emitted for
    transpose=false and for a transposed field. Ground truth is the analytic
    gradient itself: numpy differentiates the potential by hand, not by
    calling into Swift.

(b) PY4DSTEM PARITY (bonus, has a hard stop). `assert_source_contract()`
    below is the hard gate: it raises if the pinned curl grid search in
    References/py4DSTEM-dev's `_solve_for_center_of_mass_relative_rotation`
    ("Transpose unknown, rotation unknown" branch) has drifted from the exact
    text this file transcribes. The transcription itself
    (`py4dstem_curl_grid_search` below) is frozen from that pinned text and
    run on the SAME leg-(a) field. main.swift compares its answer with
    Swift's — informationally only, even now that they agree (never gates:
    the source-contract assert above is the only hard gate on this leg).

    DIAGNOSED 2026-09-17 -> 2026-09-23 (Gate D,
    docs/archive/v3/rq-frame-class-2026-09-23.md): a first measurement found
    Swift and this transcription disagreeing — (-37.2 deg, transpose=false)
    vs (+37.2 deg, transpose=true), same magnitude, flipped sign and
    transpose. That was a bug in THIS FILE, not in RotationCalibration.swift
    and not in py4DSTEM's own math. py4DSTEM's Rx is unconditionally array
    axis 0 (`R_Nx = self.data.shape[0]`, py4DSTEM/datacube/datacube.py:172-173;
    the CoM loop `for rx, ry in tqdmnd(sx, sy): ... intensities[rx, ry]`,
    py4DSTEM/process/phase/phase_base_class.py:706-727, with `sx =
    intensities.shape[0]`) — but `potential_gradient` below builds `gx, gy`
    via `np.meshgrid(np.arange(width), np.arange(height))` (default 'xy'
    indexing), giving shape (height, width): axis 0 is the FIELD's row/
    height axis, not its width/Rx-direction axis. Feeding that array to
    `py4dstem_curl_grid_search` un-transposed told py4DSTEM's formula "axis 0
    (height) is Rx" when Rx is really the width axis (RotationCalibration's
    own real call site passes `width: d.rx, height: d.ry`,
    mac4DSTEM/App/AppState+Calibration.swift:244) — an axis-order bug in this
    harness's call, confirmed by transposing the array and recovering
    Swift's exact answer on both the direct and transposed fixture fields,
    and on a non-square (30x40) field that rules out the 40x40 coincidence.
    Fix: transpose the fixture array (swap axis 0 <-> axis 1, keep the cx/cy
    channel labels) before this one call. Nothing else about the
    transcription changed; it is still frozen from, and gated against, the
    exact pinned text. Never edit RotationCalibration.swift here.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PY4DSTEM_PHASE_BASE = (
    ROOT / "References/py4DSTEM-dev/py4DSTEM/process/phase/phase_base_class.py"
)


def assert_source_contract() -> None:
    source = PY4DSTEM_PHASE_BASE.read_text()
    required = [
        # The default angle grid ("rotation unknown" branches all fall
        # through to this when no angles are supplied) — the search this
        # port's DEVIATION note (RotationCalibration.swift) says it matches
        # before adding its own 0.1 deg refinement.
        "rotation_angles_deg = np.arange(-89.0, 90.0, 1.0)",
        # The curl gradient terms, "Transpose unknown, rotation unknown"
        # branch (both the untransposed and transposed halves reuse these
        # exact slice expressions — grep finds each more than once, which is
        # the point: the formula must not have changed anywhere it appears).
        "com_measured_x[:, 1:-1, 2:] - com_measured_x[:, 1:-1, :-2]",
        "com_measured_y[:, 2:, 1:-1] - com_measured_y[:, :-2, 1:-1]",
        # The rotation matrices applied before differencing.
        "xp.cos(rotation_angles_rad) * _com_normalized_x[None]",
        "xp.cos(rotation_angles_rad) * _com_normalized_y[None]",
        # The transpose selector: curl (not divergence) picks the smaller of
        # the two argmins, ties going to untransposed.
        "ind_min = xp.argmin(rotation_curl).item()",
        "ind_trans_min = xp.argmin(rotation_curl_transpose).item()",
        "if rotation_curl[ind_min] <= rotation_curl_transpose[ind_trans_min]:",
    ]
    for expression in required:
        if expression not in source:
            raise RuntimeError(
                f"py4DSTEM rotation-solve contract changed: {expression!r} "
                "no longer found in phase_base_class.py — re-read the "
                "current source before trusting this transcription"
            )


def potential_gradient(width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    """d/dx and d/dy of sin(x/6)*cos(y/5), analytically — the same smooth
    scalar potential CalibrationReReferenceTests.swift's phaseObjectField
    uses, computed independently here in numpy. Shape (height, width):
    axis 0 is the scan row (Swift's slow/Y axis), axis 1 the scan column
    (Swift's fast/X axis) — the field's own natural, unambiguous layout,
    independent of the (Rx,Ry) question leg (b) is about.
    """
    x, y = np.meshgrid(np.arange(width, dtype=np.float64), np.arange(height, dtype=np.float64))
    gx = np.cos(x / 6.0) * np.cos(y / 5.0) / 6.0
    gy = -np.sin(x / 6.0) * np.sin(y / 5.0) / 5.0
    return gx, gy


def rotate(a: np.ndarray, b: np.ndarray, theta_deg: float) -> tuple[np.ndarray, np.ndarray]:
    theta = np.deg2rad(theta_deg)
    c, s = np.cos(theta), np.sin(theta)
    return c * a - s * b, s * a + c * b


def py4dstem_curl_grid_search(
    com_x: np.ndarray, com_y: np.ndarray
) -> tuple[float, bool]:
    """Frozen transcription of the "Transpose unknown, rotation unknown",
    maximize_divergence=False branch of
    `_solve_for_center_of_mass_relative_rotation` — every line traceable to
    the required expressions `assert_source_contract` just checked. com_x,
    com_y: shape (Rx, Ry) per the docstring, i.e. array axis 0 = Rx, axis 1 =
    Ry (py4DSTEM/datacube/datacube.py:172-173, `R_Nx = data.shape[0]`;
    py4DSTEM/process/phase/phase_base_class.py:706-727's CoM loop indexes
    `intensities[rx, ry]` with `rx` over `shape[0]`) — the CALLER is
    responsible for handing this function an array laid out that way; it
    does no reshaping of its own (see the module docstring's 2026-09-23
    entry: the one call site below transposes `potential_gradient`'s
    (height, width) field before passing it here, precisely to satisfy this).
    """
    rotation_angles_deg = np.arange(-89.0, 90.0, 1.0)
    rotation_angles_rad = np.deg2rad(rotation_angles_deg)[:, None, None]

    # Untransposed.
    mx = (
        np.cos(rotation_angles_rad) * com_x[None]
        - np.sin(rotation_angles_rad) * com_y[None]
    )
    my = (
        np.sin(rotation_angles_rad) * com_x[None]
        + np.cos(rotation_angles_rad) * com_y[None]
    )
    com_grad_x_y = mx[:, 1:-1, 2:] - mx[:, 1:-1, :-2]
    com_grad_y_x = my[:, 2:, 1:-1] - my[:, :-2, 1:-1]
    rotation_curl = np.mean(np.abs(com_grad_y_x - com_grad_x_y), axis=(-2, -1))

    # Transposed.
    mxt = (
        np.cos(rotation_angles_rad) * com_y[None]
        - np.sin(rotation_angles_rad) * com_x[None]
    )
    myt = (
        np.sin(rotation_angles_rad) * com_y[None]
        + np.cos(rotation_angles_rad) * com_x[None]
    )
    com_grad_x_y_t = mxt[:, 1:-1, 2:] - mxt[:, 1:-1, :-2]
    com_grad_y_x_t = myt[:, 2:, 1:-1] - myt[:, :-2, 1:-1]
    rotation_curl_transpose = np.mean(
        np.abs(com_grad_y_x_t - com_grad_x_y_t), axis=(-2, -1)
    )

    ind_min = int(np.argmin(rotation_curl))
    ind_trans_min = int(np.argmin(rotation_curl_transpose))
    if rotation_curl[ind_min] <= rotation_curl_transpose[ind_trans_min]:
        return float(rotation_angles_deg[ind_min]), False
    return float(rotation_angles_deg[ind_trans_min]), True


def main() -> None:
    assert_source_contract()

    width, height = 40, 40
    planted_deg = 37.2  # asymmetric: 0/45/90 hide a sign flip or a dropped transpose

    gx, gy = potential_gradient(width, height)

    # Case "direct": the field as measured with no transpose needed.
    # Swift's solve() should report transpose=false, angle = -planted (mod 180)
    # — the app-wide convention CalibrationReReferenceTests.swift pins.
    direct_cx, direct_cy = rotate(gx, gy, planted_deg)

    # Case "transposed": swap the channels before rotating. A detector whose
    # two channels are transposed relative to the scan axes measures this
    # field for the same underlying potential; solve() should report
    # transpose=true (and, empirically, angle = +planted mod 180 — the
    # transpose branch's own sign, not the direct branch's).
    transposed_cx, transposed_cy = rotate(gy, gx, planted_deg)

    # Transpose axis 0 <-> axis 1 before this call: potential_gradient builds
    # (height, width)-shaped arrays (axis 0 = the field's height/row axis),
    # but py4dstem_curl_grid_search wants axis 0 = Rx = the WIDTH axis
    # (RotationCalibration's real call site passes width: d.rx, height:
    # d.ry — mac4DSTEM/App/AppState+Calibration.swift:244). Fixed
    # 2026-09-23 per docs/archive/v3/rq-frame-class-2026-09-23.md; channel
    # labels (cx/cy) are untouched, only the array's own axis order.
    py4dstem_angle, py4dstem_transpose = py4dstem_curl_grid_search(direct_cx.T, direct_cy.T)

    def interleave(cx: np.ndarray, cy: np.ndarray) -> list[float]:
        out = np.empty(cx.size * 2, dtype=np.float32)
        out[0::2] = cx.ravel().astype(np.float32)
        out[1::2] = cy.ravel().astype(np.float32)
        return out.tolist()

    print(
        json.dumps(
            {
                "width": width,
                "height": height,
                "plantedDeg": planted_deg,
                "directField": interleave(direct_cx, direct_cy),
                "transposedField": interleave(transposed_cx, transposed_cy),
                "py4dstemAngleDeg": py4dstem_angle,
                "py4dstemTranspose": py4dstem_transpose,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
