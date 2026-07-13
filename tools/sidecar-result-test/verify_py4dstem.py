#!/usr/bin/env python3
"""Validate the merged session tree through py4DSTEM 0.14.19 and h5py."""

import sys
import json

import h5py
import numpy as np
import py4DSTEM
from py4DSTEM.braggvectors import BraggVectors
from py4DSTEM.data import RealSlice


path = sys.argv[1]
# Reading the whole file must remain valid: every result is a direct, known EMD
# node rather than a mac4DSTEM-only container class.
root = py4DSTEM.read(path)
assert type(root).__name__ == "Root", type(root)
external = py4DSTEM.read(path, datapath="/braggvectors_root/external_analysis")
assert type(external).__name__ == "Array", type(external)
np.testing.assert_array_equal(external.data, np.array([3.0, 1.0, 4.0], dtype=np.float32))

bragg = py4DSTEM.read(path, datapath="/braggvectors_root/braggvectors")
assert isinstance(bragg, BraggVectors), type(bragg)
assert tuple(bragg.Rshape) == (2, 3)
assert tuple(bragg.Qshape) == (5, 7)
assert bragg.calibration.get_Q_pixel_size() == 0.03125
assert bragg.calibration.get_R_pixel_size() == 1.75
assert bragg.calibration.get_QR_flip() == True
assert bragg.calibration.get_QR_rotation() == -0.625
assert bragg.calibration.get_probe_semiangle() == 8.5
np.testing.assert_allclose(
    bragg.calibration.get_origin()[0],
    np.array([[10, 11, 12], [20, 21, 22]], dtype=np.float64),
)
np.testing.assert_allclose(
    bragg.calibration.get_origin()[1],
    np.array([[30, 31, 32], [40, 41, 42]], dtype=np.float64),
)
np.testing.assert_allclose(
    bragg.raw[0, 0].data[["qx", "qy", "intensity"]].tolist(),
    [(1.25, 2.5, 10.0)], rtol=0, atol=0,
)

# RealSlice 0.14's constructor currently discards the dimension args returned
# by Array._get_constructor_args, so validate the persisted calibrated vectors
# directly in HDF5 as well as validating py4DSTEM's data/metadata promotion.
with h5py.File(path, "r") as f:
    session_root = f["/braggvectors_root"]
    assert session_root.attrs["mac4dstem_session_schema"] == "4"
    nodes = session_root.attrs["mac4dstem_result_nodes"].split("\n")
    assert len(nodes) == 8, nodes
    assert session_root.attrs["mac4dstem_current_result"] == nodes[-1]
    assert "result_map" not in session_root
    assert "external_analysis" in session_root

    calibration = session_root["metadatabundle/calibration"]
    assert calibration["QR_rotation"][()] == -0.625
    assert calibration["QR_rotation_degrees"][()] == np.degrees(-0.625)
    assert calibration["probe_semiangle"][()] == 8.5
    assert calibration["a"][()] == 1.02
    assert calibration["b"][()] == 0.98
    assert calibration["theta"][()] == 0.35
    np.testing.assert_allclose(
        calibration["qx0_meas"][:],
        [[10.25, 11.25, 12.25], [20.25, 21.25, 22.25]],
    )
    np.testing.assert_allclose(
        calibration["qy0_meas"][:],
        [[29.5, 30.5, 31.5], [39.5, 40.5, 41.5]],
    )

    groups = [session_root[node] for node in nodes]
    assert [group.attrs["mac4dstem_kind"] for group in groups] == [
        "virtual_image", "strain_exx", "acom_ipf_z",
        "parallax_subpixel_bf", "parallax_corrected_phase", "parallax_depth",
        "ptychography_object_phase", "ptychography_object_amplitude",
    ]
    for group in groups[:3]:
        np.testing.assert_allclose(group["dim0"][:], [0, 1.75])
        np.testing.assert_allclose(group["dim1"][:], [0, 1.75])
        assert group["dim0"].attrs["name"] == "Rx"
        assert group["dim1"].attrs["name"] == "Ry"
        assert group["dim0"].attrs["units"] == "nm"
        assert group["dim1"].attrs["units"] == "nm"

    expected_sampling = [
        (0.625, 0.625), (2.0, 2.0), (2.0, 2.0), (0.4, 0.6), (0.4, 0.6)
    ]
    for group, sampling in zip(groups[3:], expected_sampling):
        np.testing.assert_allclose(group["dim0"][:], [0, sampling[0]])
        np.testing.assert_allclose(group["dim1"][:], [0, sampling[1]])
        assert group["dim0"].attrs["units"] == "A"
        assert group["dim1"].attrs["units"] == "A"
        provenance = json.loads(group.attrs["mac4dstem_provenance"])
        assert provenance

for node, expected, name in (
    (nodes[0], np.array([[1.5, np.nan, -2.25], [4, 5.5, 6.75]], dtype=np.float32),
     "Virtual BF"),
    (nodes[1], np.array([[19, 18, 17], [16, 15, 14]], dtype=np.float32),
     "Strain εxx v2"),
):
    result = py4DSTEM.read(path, datapath=f"/braggvectors_root/{node}")
    assert isinstance(result, RealSlice), type(result)
    np.testing.assert_allclose(result.data, expected, rtol=0, atol=0, equal_nan=True)
    assert result.metadata["mac4dstem"]["display_name"] == name

rgba = py4DSTEM.read(path, datapath=f"/braggvectors_root/{nodes[2]}")
assert type(rgba).__name__ == "Array", type(rgba)
expected_rgba = np.array([
    [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]],
    [[12, 34, 56, 255], [78, 90, 123, 255], [210, 220, 230, 128]],
], dtype=np.uint8)
np.testing.assert_array_equal(rgba.data, expected_rgba)
assert rgba.metadata["mac4dstem"]["display_name"] == "ACOM · IPF · Z"

for node, shape in zip(nodes[3:], [(4, 5), (2, 3), (2, 3), (3, 4), (3, 4)]):
    result = py4DSTEM.read(path, datapath=f"/braggvectors_root/{node}")
    assert isinstance(result, RealSlice), type(result)
    assert result.data.shape == shape

print("PASS: py4dstem_stabilized_realslices_rgba_and_preserved_braggvectors")
print("sidecar-result-test: all passed")
