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
    # Schema "6" since v2 S5 (2026-08-24): the replay record joined the
    # format and every sidecar carries the minimum-reader marker. This
    # sidecar records no reduced specification, so the oldest reader that
    # interprets it without misreading is still "5". This assertion was
    # stale at "5" from S5 until 2026-08-25 because the harness had a
    # compile break over the same period (docs/open-items.md) and the
    # stale pin was never reached — fixed together in S7.
    assert session_root.attrs["mac4dstem_session_schema"] == "6"
    assert session_root.attrs["mac4dstem_min_reader_schema"] == "5"
    nodes = session_root.attrs["mac4dstem_result_nodes"].split("\n")
    assert len(nodes) == 9, nodes
    assert session_root.attrs["mac4dstem_current_result"] == nodes[-1]
    assert "result_map" not in session_root
    assert "external_analysis" in session_root
    detection_provenance = json.loads(
        session_root["braggvectors"].attrs["mac4dstem_detection_provenance"]
    )
    assert detection_provenance["detection_algorithm"] == "py4dstem_find_bragg_disks_native_v1"
    assert detection_provenance["min_relative_intensity"] == "0.005"
    assert detection_provenance["subpixel"] == "poly"

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
        "dpc_angle",
    ]
    for group in groups[:2]:
        np.testing.assert_allclose(group["dim0"][:], [0, 1.75])
        np.testing.assert_allclose(group["dim1"][:], [0, 1.75])
        assert group["dim0"].attrs["name"] == "Rx"
        assert group["dim1"].attrs["name"] == "Ry"
        assert group["dim0"].attrs["units"] == "nm"
        assert group["dim1"].attrs["units"] == "nm"

    rgba_group = groups[2]
    np.testing.assert_allclose(rgba_group["dim0"][:], [0, 2.5])
    np.testing.assert_allclose(rgba_group["dim1"][:], [0, 3.5])
    assert rgba_group["dim0"].attrs["units"] == "nm"
    assert rgba_group["dim1"].attrs["units"] == "nm"
    rgba_provenance = json.loads(rgba_group.attrs["mac4dstem_provenance"])
    assert rgba_provenance["quantitative_status"] == "exploratory"
    assert rgba_provenance["material_model_id"] == "au_fcc"
    assert rgba_provenance["q_scale_provenance"] == "exploratory"

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

    dpc_group = groups[-1]
    assert dpc_group.attrs["mac4dstem_value_units"] == "rad"
    np.testing.assert_allclose(
        dpc_group["data"][:],
        [[np.pi / 2, 3 * np.pi / 4, 7 * np.pi / 4]],
        rtol=0, atol=1e-6,
    )
    dpc_provenance = json.loads(dpc_group.attrs["mac4dstem_provenance"])
    assert dpc_provenance["dpc_angle_encoding"] == "radians"
    assert "dpc_angle_migration" not in dpc_provenance

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
assert json.loads(rgba.metadata["mac4dstem"]["provenance"])[
    "quantitative_status"
] == "exploratory"

for node, shape in zip(nodes[3:], [(4, 5), (2, 3), (2, 3), (3, 4), (3, 4)]):
    result = py4DSTEM.read(path, datapath=f"/braggvectors_root/{node}")
    assert isinstance(result, RealSlice), type(result)
    assert result.data.shape == shape

dpc = py4DSTEM.read(path, datapath=f"/braggvectors_root/{nodes[-1]}")
assert isinstance(dpc, RealSlice), type(dpc)
np.testing.assert_allclose(
    dpc.data, [[np.pi / 2, 3 * np.pi / 4, 7 * np.pi / 4]], rtol=0, atol=1e-6
)
assert dpc.metadata["mac4dstem"]["value_units"] == "rad"

print("PASS: py4dstem_stabilized_realslices_rgba_and_preserved_braggvectors")
print("sidecar-result-test: all passed")
