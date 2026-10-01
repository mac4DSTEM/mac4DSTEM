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

# ---- X2: scan stride, detector crop, bin, filter_hot_pixels --------------
# The reference is py4DSTEM's own chain on the harness's planted cube
# (main.swift: SyntheticSource(hot: true)): crop_R, thin_R, crop_Q, bin_Q,
# then filter_hot_pixels. Axis names follow py4DSTEM: R_x is the app's scan
# row, Q_x the app's detector row.
import json
import h5py


def planted_cube():
    data = np.empty((6, 7, 20, 24), dtype=np.float32)
    add = {(6, 9): 5000, (6, 11): 3000, (8, 3): 5000, (8, 19): 4990, (16, 19): 5000}
    for sy in range(6):
        for sx in range(7):
            for qy in range(20):
                for qx in range(24):
                    data[sy, sx, qy, qx] = (sy * 5 + sx * 3 + qy * 7 + qx * 2) % 3 \
                        + add.get((qy, qx), 0)
    return data


def reference(thresh):
    dc = py4DSTEM.DataCube(data=planted_cube())
    dc = dc.crop_R((1, 6, 0, 7))      # (Rx_min, Rx_max, Ry_min, Ry_max)
    dc = dc.thin_R(2)
    dc = dc.crop_Q((2, 18, 3, 22))    # (Qx_min, Qx_max, Qy_min, Qy_max)
    dc = dc.bin_Q(2)
    if thresh is None:
        return dc.data.copy(), None
    dc, mask = dc.filter_hot_pixels(thresh, return_mask=True)
    return dc.data.copy(), mask


def derivation(path):
    with h5py.File(path, "r") as f:
        return json.loads(f["datacube_root"].attrs["mac4dstem_derivation"])


filtered_path, unfiltered_path = sys.argv[2], sys.argv[3]
ref_on, mask = reference(20)
ref_off, _ = reference(None)
assert ref_on.shape == (2, 3, 8, 9), ref_on.shape
# The fixture must exercise what it claims: py4DSTEM's mask is exactly the
# hot pixel and the corner, and the opposite-edge pair is hidden by np.roll.
assert sorted(map(tuple, np.argwhere(mask))) == [(2, 3), (7, 8)], np.argwhere(mask)
assert not np.array_equal(ref_on, ref_off)

got_on = py4DSTEM.read(filtered_path)
got_off = py4DSTEM.read(unfiltered_path)
np.testing.assert_array_equal(got_on.data, ref_on)     # bit for bit, float32
np.testing.assert_array_equal(got_off.data, ref_off)
assert got_on.data.dtype == np.float32
differ = np.argwhere((got_on.data != got_off.data).any(axis=(0, 1)))
assert sorted(map(tuple, differ)) == [(2, 3), (7, 8)], differ

for path, thresh in ((filtered_path, 20.0), (unfiltered_path, None)):
    d = derivation(path)
    assert d["scan_stride"] == 2 and d["detector_bin"] == 2
    assert (d["scan_offset_y"], d["scan_offset_x"]) == (1, 0)
    assert (d["detector_offset_y"], d["detector_offset_x"]) == (2, 3)
    assert (d["scan_height"], d["scan_width"]) == (2, 3)
    if thresh is None:
        assert "hot_pixels" not in d and "hot_pixel_threshold" not in d
    else:
        assert d["hot_pixel_threshold"] == thresh
        assert d["hot_pixels"] == [[2, 3], [7, 8]], d["hot_pixels"]

cal = got_on.calibration
assert cal.get_R_pixel_size() == 5.0       # 2.5 * stride 2 (thin_data_real)
assert cal.get_Q_pixel_size() == 0.5
# Origin (v - crop offset + 0.5) / 2 - 0.5, at the thinned scan positions
# (rows 1, 3; columns 0, 2, 4 of the 6 x 7 map).
qx = 5.0 + 0.0625 * np.arange(42).reshape(6, 7)
qy = 7.0 + 0.0625 * np.arange(42).reshape(6, 7)
rows, cols = [1, 3], [0, 2, 4]
np.testing.assert_allclose(cal.get_origin()[0],
    (qx[np.ix_(rows, cols)] - 2 + 0.5) / 2 - 0.5)
np.testing.assert_allclose(cal.get_origin()[1],
    (qy[np.ix_(rows, cols)] - 3 + 0.5) / 2 - 0.5)
print("preprocessing-export-test: stride/crop/bin/hot-pixel parity with py4DSTEM passed")
