#!/usr/bin/env python3
"""Ground truth for tools/strain-frame-test, from py4DSTEM itself (v2 S8).

The app computes strain in detector x/y (StrainMapping.swift) and re-expresses
it in the scan frame at presentation (StrainFrame.swift). py4DSTEM reaches the
same numbers by rotating the calibrated Bragg VECTORS before the fit
(braggvectors.py: v_cal = R(QR_rotation) @ (flip ? (qy,qx) : (qx,qy))) — and it
ships the tensor-level equivalent, `get_rotated_strain_map`. This script:

1. SOURCE-LOCKS the vendored expressions the Swift port mirrors, so a py4DSTEM
   update that changes a convention fails here by name instead of silently
   invalidating the golden data.
2. EXECUTES the vendored `get_rotated_strain_map` on a fixed anisotropic tensor
   field for several (rotation, transpose) cases and writes golden.json for the
   Swift side to match.

THE MAPPING UNDER TEST. The app's `rotate(rotationRad: θ, transposed: t)` must
equal py4DSTEM's `get_rotated_strain_map(swap_xx_yy_if_t(input),
xaxis=(cos(−θ), sin(−θ)), flip_theta=t)`:

  - xaxis: py4DSTEM takes the new x-axis in diffraction coordinates. The scan
    x-axis expressed in detector coordinates is R(θ)⁻¹·x̂ = (cos(−θ), sin(−θ)),
    because calibrated vectors transform v_scan = R(θ)·v_det.
  - transpose: py4DSTEM's flip swaps the vector components BEFORE the rotation
    (positions = R @ (qy, qx)). On the tensor that is ε → F·ε·F (swap εxx/εyy,
    εxy unchanged) before rotating, with the pseudo-scalar θ_lattice negated —
    exactly `flip_theta`.

Every case is ALSO checked here against an independent numpy similarity
transform E' = (R·F)·E·(R·F)ᵀ before it is written, so a wrong xaxis mapping
fails loudly at generation time instead of baking a wrong golden file.
"""
import json
import pathlib
import sys

try:
    import numpy as np
    from py4DSTEM.data import RealSlice
    from py4DSTEM.process.strain.latticevectors import get_rotated_strain_map
except ImportError as error:
    sys.stderr.write(
        "strain-frame-test needs numpy and the vendored py4DSTEM (%s). "
        "Run via run.sh, which sets PYTHONPATH.\n" % error
    )
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[2]

# --- 1. Source locks -------------------------------------------------------

LOCKS = {
    "process/strain/latticevectors.py": (
        # The rotation convention and the flip_theta negation the app mirrors.
        "theta = -np.arctan2(xaxis_y, xaxis_x)",
        'rotated_strain_map.data[3, :, :] = -unrotated_strain_map.get_slice("theta").data',
    ),
    "braggvectors/braggvectors.py": (
        # Calibrated vectors: flip swaps components BEFORE the rotation, and
        # the matrix layout fixes the rotation's sign convention.
        'positions = R @ np.vstack((ans["qy"], ans["qx"]))',
        "[[np.cos(theta), -np.sin(theta)], [np.sin(theta), np.cos(theta)]]",
    ),
    "process/strain/strain.py": (
        # The calibrated/uncalibrated split the app's presentation follows:
        # without a measured rotation py4DSTEM warns and stays detector-frame.
        "Real to reciprocal space rotation not calibrated",
    ),
}
for rel, expressions in LOCKS.items():
    source = (ROOT / "References/py4DSTEM-dev/py4DSTEM" / rel).read_text()
    for expression in expressions:
        if expression not in source:
            raise RuntimeError(f"py4DSTEM contract changed in {rel}: {expression}")

# --- 2. Golden data from the vendored implementation -----------------------

rng = np.random.default_rng(20260825)
shape = (3, 4)
exx = rng.uniform(-0.03, 0.03, shape)
eyy = rng.uniform(-0.03, 0.03, shape)
exy = rng.uniform(-0.02, 0.02, shape)
theta_l = rng.uniform(-0.01, 0.01, shape)
mask = np.ones(shape)

CASES = [
    (np.deg2rad(37.2), False),
    (np.deg2rad(-64.0), False),
    (np.deg2rad(90.0), False),
    (np.deg2rad(30.0), True),
    (np.deg2rad(-71.6), True),
]


def realslice(e_xx, e_yy, e_xy, th):
    return RealSlice(
        data=np.stack([e_xx, e_yy, e_xy, th, mask]),
        slicelabels=("e_xx", "e_yy", "e_xy", "theta", "mask"),
        name="unrotated",
    )


def independent(e_xx, e_yy, e_xy, th, rotation, transposed):
    """E' = (R·F)·E·(R·F)ᵀ, elementwise over the field — no py4DSTEM code."""
    a, b = (e_yy, e_xx) if transposed else (e_xx, e_yy)
    th_out = -th if transposed else th
    c, s = np.cos(rotation), np.sin(rotation)
    out_xx = c * c * a - 2 * s * c * e_xy + s * s * b
    out_yy = s * s * a + 2 * s * c * e_xy + c * c * b
    out_xy = s * c * (a - b) + (c * c - s * s) * e_xy
    return out_xx, out_yy, out_xy, th_out


cases_out = []
for rotation, transposed in CASES:
    if transposed:
        slice_in = realslice(eyy, exx, exy, theta_l)  # F·ε·F: swap εxx/εyy
    else:
        slice_in = realslice(exx, eyy, exy, theta_l)
    rotated = get_rotated_strain_map(
        slice_in,
        xaxis_x=float(np.cos(-rotation)),
        xaxis_y=float(np.sin(-rotation)),
        flip_theta=transposed,
    )
    got = tuple(rotated.get_slice(k).data for k in ("e_xx", "e_yy", "e_xy", "theta"))
    want = independent(exx, eyy, exy, theta_l, rotation, transposed)
    for name, g, w in zip(("e_xx", "e_yy", "e_xy", "theta"), got, want):
        if not np.allclose(g, w, atol=1e-12):
            raise RuntimeError(
                f"py4DSTEM disagrees with the independent similarity transform "
                f"on {name} at rotation={rotation}, transposed={transposed} — "
                f"the xaxis/flip mapping in this script is wrong"
            )
    cases_out.append({
        "rotation_rad": float(rotation),
        "transposed": bool(transposed),
        "expected_exx": got[0].ravel().tolist(),
        "expected_eyy": got[1].ravel().tolist(),
        "expected_exy": got[2].ravel().tolist(),
        "expected_theta": got[3].ravel().tolist(),
    })

golden = {
    "shape": list(shape),
    "input_exx": exx.ravel().tolist(),
    "input_eyy": eyy.ravel().tolist(),
    "input_exy": exy.ravel().tolist(),
    "input_theta": theta_l.ravel().tolist(),
    "cases": cases_out,
}

out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(".")
(out_dir / "golden.json").write_text(json.dumps(golden))
print("PASS: py4DSTEM rotation/flip source lock, and golden data generated "
      f"({len(cases_out)} cases, verified against the independent transform)")
