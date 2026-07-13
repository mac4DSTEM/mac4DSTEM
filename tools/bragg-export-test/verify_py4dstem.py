#!/usr/bin/env python3
"""Validate the native Swift sidecar through checked-in py4DSTEM 0.14.19."""

import sys

import numpy as np
import py4DSTEM
from py4DSTEM.braggvectors import BraggVectors


path = sys.argv[1]
vectors = py4DSTEM.read(path)
assert isinstance(vectors, BraggVectors), type(vectors)
assert tuple(vectors.Rshape) == (2, 3), vectors.Rshape
assert tuple(vectors.Qshape) == (5, 7), vectors.Qshape

expected = {
    (0, 0): [(1.25, 2.5, 10.0), (-0.5, 6.125, 3.25)],
    (0, 1): [],
    (0, 2): [(4.75, 0.125, 99.5)],
    (1, 0): [(2.0, 3.0, 1.0)],
    (1, 1): [(0.0, 0.0, 2.0), (4.0, 6.0, 4.0), (1.5, 2.25, 8.0)],
    (1, 2): [(3.125, 5.875, 7.5)],
}
for position, rows in expected.items():
    actual = vectors.raw[position].data
    wanted = np.array(rows, dtype=actual.dtype)
    np.testing.assert_allclose(actual["qx"], wanted["qx"], rtol=0, atol=0)
    np.testing.assert_allclose(actual["qy"], wanted["qy"], rtol=0, atol=0)
    np.testing.assert_allclose(actual["intensity"], wanted["intensity"], rtol=0, atol=0)

cal = vectors.calibration
assert cal.get_Q_pixel_size() == 0.03125
assert cal.get_Q_pixel_units() == "A^-1"
assert cal.get_R_pixel_size() == 1.75
assert cal.get_R_pixel_units() == "nm"
assert bool(cal.get_QR_flip()) is True
print("PASS: py4dstem_0.14.19_roundtrip axes values calibration")
print("bragg-export-test: all passed")
