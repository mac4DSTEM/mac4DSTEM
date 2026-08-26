"""Validate the streamed DataCube through checked-in py4DSTEM 0.14.19."""
import sys
import numpy as np
import py4DSTEM

cube = py4DSTEM.read(sys.argv[1])
assert isinstance(cube, py4DSTEM.DataCube)
assert cube.data.shape == (2, 3, 2, 3)

expected = np.empty((2, 3, 2, 3), dtype=np.float32)
for oy in range(2):
    for ox, sx in enumerate(range(1, 4)):
        for qy in range(2):
            for qx in range(3):
                expected[oy, ox, qy, qx] = sum(
                    (oy + 1) * 10000 + sx * 1000 + (qy * 2 + by) * 10 + qx * 2 + bx
                    for by in range(2) for bx in range(2)
                )
np.testing.assert_array_equal(cube.data, expected)
cal = cube.calibration
assert cal.get_R_pixel_size() == 2.5
assert cal.get_Q_pixel_size() == 0.5
# (v + 0.5) / 2 - 0.5 over the harness's in-detector fixture origins
# (1.0 + 0.125*i and 2.0 + 0.25*i at scan positions 5,6,7,9,10,11) — the
# original out-of-detector values are refused by the writer since v2 S10.
np.testing.assert_allclose(cal.get_origin()[0],
    np.array([[0.5625, 0.625, 0.6875], [0.8125, 0.875, 0.9375]]))
np.testing.assert_allclose(cal.get_origin()[1],
    np.array([[1.375, 1.5, 1.625], [1.875, 2.0, 2.125]]))
print("preprocessing-export-test: py4DSTEM round trip passed")
