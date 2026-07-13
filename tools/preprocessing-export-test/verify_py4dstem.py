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
np.testing.assert_allclose(cal.get_origin()[0],
    np.array([[6.25, 6.75, 7.25], [8.25, 8.75, 9.25]]))
np.testing.assert_allclose(cal.get_origin()[1],
    np.array([[12.25, 12.75, 13.25], [14.25, 14.75, 15.25]]))
print("preprocessing-export-test: py4DSTEM round trip passed")
