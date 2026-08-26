"""v2 S10 — the reduced-file export, judged by py4DSTEM itself.

The arbiter is data-vs-metadata INSIDE each exported file: the beam centroid
computed from the exported pixels must land on the exported calibration's
origin. Neither side comes from the Swift code's own frame math — the
centroid is measured, the origin is read — so a frame error anywhere in the
chain (crop offset, bin half-pixel, axis swap) separates them.

Case constants are duplicated from main.swift ON PURPOSE: an expectation
derived by importing the code under test would be self-consistency, the L3
harness lesson.
"""
import json
import sys

import h5py
import numpy as np
import py4DSTEM

directory = sys.argv[1]

# name -> (shape, total_bin, derivation dict or None, recipe center_x or None)
CASES = {
    "crop": ((6, 6, 48, 48), 1,
             dict(schema=1, source_file="synthetic.h5",
                  scan_offset_y=0, scan_offset_x=0, scan_height=6, scan_width=6,
                  detector_offset_y=4, detector_offset_x=8, detector_bin=1,
                  detector_height=48, detector_width=48), None),
    "cropbin": ((6, 6, 24, 24), 2,
                dict(schema=1, source_file="synthetic.h5",
                     scan_offset_y=0, scan_offset_x=0, scan_height=6, scan_width=6,
                     detector_offset_y=4, detector_offset_x=8, detector_bin=2,
                     detector_height=24, detector_width=24), None),
    "cropbinexp": ((6, 6, 12, 12), 4,
                   dict(schema=1, source_file="synthetic.h5",
                        scan_offset_y=0, scan_offset_x=0, scan_height=6, scan_width=6,
                        detector_offset_y=4, detector_offset_x=8, detector_bin=4,
                        detector_height=12, detector_width=12), "5.875"),
    # Composed scan offsets (1+2, 2+0) = (3, 2) — asymmetric on purpose, so a
    # y/x swap in DataCubeDerivation.compose cannot cancel (S10 finding 4).
    "scancrop": ((2, 3, 24, 24), 2,
                 dict(schema=1, source_file="synthetic.h5",
                      scan_offset_y=3, scan_offset_x=2, scan_height=2, scan_width=3,
                      detector_offset_y=4, detector_offset_x=8, detector_bin=2,
                      detector_height=24, detector_width=24), None),
    "full": ((6, 6, 32, 32), 2,
             dict(schema=1, source_file="synthetic.h5",
                  scan_offset_y=0, scan_offset_x=0, scan_height=6, scan_width=6,
                  detector_offset_y=0, detector_offset_x=0, detector_bin=2,
                  detector_height=32, detector_width=32), "12.25"),
}

for name, (shape, total_bin, derivation, recipe_center_x) in CASES.items():
    path = f"{directory}/{name}.h5"
    cube = py4DSTEM.read(path)
    assert isinstance(cube, py4DSTEM.DataCube), f"{name}: not a DataCube"
    assert cube.data.shape == shape, f"{name}: {cube.data.shape} != {shape}"

    cal = cube.calibration
    # Pixel lengths ÷ total bin, sampling interval × total bin — the
    # rescalings py4DSTEM's own bin_data_diffraction skips and this writer
    # refuses to skip (the DEVIATION note).
    np.testing.assert_allclose(cal.get_R_pixel_size(), 2.0, err_msg=name)
    np.testing.assert_allclose(cal.get_Q_pixel_size(), 0.25 * total_bin,
                               err_msg=f"{name}: Q_pixel_size")
    np.testing.assert_allclose(cal.get_probe_semiangle(), 6.0 / total_bin,
                               err_msg=f"{name}: probe radius")
    a, b, theta = cal.get_ellipse()
    np.testing.assert_allclose(a, 1.2 / total_bin, err_msg=f"{name}: ellipse a")
    np.testing.assert_allclose(b, 1.0 / total_bin, err_msg=f"{name}: ellipse b")
    np.testing.assert_allclose(theta, 0.2, err_msg=f"{name}: ellipse theta (an angle must not move)")

    # THE ARBITER — the origin lands on the beam. Centroids in py4DSTEM axes:
    # qx is the FIRST Q axis (rows).
    qx0, qy0 = cal.get_origin()
    ry_count, rx_count, qy_pix, qx_pix = shape
    rows = np.arange(qy_pix, dtype=np.float64)
    cols = np.arange(qx_pix, dtype=np.float64)
    worst = 0.0
    for ry in range(ry_count):
        for rx in range(rx_count):
            pattern = np.asarray(cube.data[ry, rx], dtype=np.float64)
            total = pattern.sum()
            assert total > 0, f"{name}: empty pattern at ({ry},{rx})"
            centroid_row = float((pattern.sum(axis=1) * rows).sum() / total)
            centroid_col = float((pattern.sum(axis=0) * cols).sum() / total)
            worst = max(worst,
                        abs(centroid_row - float(qx0[ry, rx])),
                        abs(centroid_col - float(qy0[ry, rx])))
    assert worst < 0.02, (
        f"{name}: origin misses the measured beam by {worst:.4f} px — "
        "the exported calibration is not in the exported file's frame"
    )

    # Provenance attributes on datacube_root: the derivation says where the
    # pixels came from; the recipe (when present) is expressed in THIS
    # file's frame.
    with h5py.File(path, "r") as handle:
        root = handle["datacube_root"]

        def text(attribute):
            value = root.attrs[attribute]
            return value.decode() if isinstance(value, bytes) else str(value)

        recorded = json.loads(text("mac4dstem_derivation"))
        assert recorded == derivation, (
            f"{name}: derivation {recorded} != {derivation}"
        )
        if recipe_center_x is None:
            assert "mac4dstem_replay_record" not in root.attrs, (
                f"{name}: a session with no recipe must stamp none — absence is absence"
            )
        else:
            recipe = json.loads(text("mac4dstem_replay_record"))
            step = recipe["steps"][0]
            assert step["kind"] == "virtual_detector", name
            assert step["parameters"]["center_x"] == recipe_center_x, (
                f"{name}: recipe center_x {step['parameters']['center_x']} "
                f"!= {recipe_center_x} — not the exported file's frame"
            )

print("reduced-export-test: py4DSTEM round trip passed")
