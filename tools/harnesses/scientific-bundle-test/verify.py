#!/usr/bin/env python3
import json
import sys
import h5py
import numpy as np
import py4DSTEM
from py4DSTEM.data import RealSlice

def text(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value

path = sys.argv[1]
root = py4DSTEM.read(path)
assert type(root).__name__ == "Root", type(root)
kinds = ["strain_exx", "strain_eyy", "strain_exy", "strain_theta",
         "strain_validity", "strain_fit_residual",
         "orientation_phi1", "orientation_Phi", "orientation_phi2",
         "orientation_reliability", "orientation_score", "orientation_validity"]
with h5py.File(path, "r") as f:
    bundle = f["/scientific_bundle_root"]
    assert bundle.attrs["mac4dstem_bundle_schema"] == "1"
    assert bundle.attrs["mac4dstem_bundle_fields"].split("\n") == kinds
    calibration = bundle["metadatabundle/calibration"]
    assert calibration["R_pixel_size"][()] == 0.5
    assert text(calibration["R_pixel_units"][()]) == "nm"
    assert calibration["Q_pixel_size"][()] == 0.02
    assert text(calibration["Q_pixel_units"][()]) == "A^-1"
    nodes = {
        group.attrs["mac4dstem_kind"]: name
        for name, group in bundle.items()
        if isinstance(group, h5py.Group) and "mac4dstem_kind" in group.attrs
    }
    assert set(nodes) == set(kinds), nodes
    for kind in kinds:
        group = bundle[nodes[kind]]
        assert group.attrs["mac4dstem_kind"] == kind
        expected_units = (
            "rad" if ("phi" in kind or "Phi" in kind or kind == "strain_theta")
            else "boolean" if "validity" in kind
            else "dimensionless" if kind.startswith("orientation_")
            else "detector_px" if kind == "strain_fit_residual"
            else "strain"
        )
        assert group.attrs["mac4dstem_value_units"] == expected_units
        provenance = json.loads(group.attrs["mac4dstem_provenance"])
        assert provenance["bundle"] == (
            "orientation" if kind.startswith("orientation_") else "strain"
        )
        if kind.startswith("orientation_"):
            assert provenance["symmetry"] == "cubic"
        np.testing.assert_allclose(group["dim0"][:], [0, 0.5])
        np.testing.assert_allclose(group["dim1"][:], [0, 0.5])

for index, kind in enumerate(kinds):
    result = py4DSTEM.read(path, datapath=f"/scientific_bundle_root/{nodes[kind]}")
    assert isinstance(result, RealSlice), type(result)
    assert result.data.shape == (2, 3)
    assert result.data[0, 0] == index
    assert np.isnan(result.data[0, 2])

print("PASS: py4DSTEM RealSlice readback of all coherent fields")
