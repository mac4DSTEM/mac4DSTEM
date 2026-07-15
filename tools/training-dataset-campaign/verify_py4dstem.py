#!/usr/bin/env python3
"""Read every campaign sidecar through py4DSTEM and h5py."""

from pathlib import Path
import sys

import h5py
import py4DSTEM
from py4DSTEM.braggvectors import BraggVectors
from py4DSTEM.data import RealSlice


directory = Path(sys.argv[1])
paths = sorted(directory.glob("*.mac4dstem.h5"))
assert paths, "campaign produced no session sidecars"

for path in paths:
    root = py4DSTEM.read(path)
    assert type(root).__name__ == "Root", type(root)
    bragg = py4DSTEM.read(path, datapath="/braggvectors_root/braggvectors")
    assert isinstance(bragg, BraggVectors), type(bragg)
    with h5py.File(path, "r") as handle:
        session = handle["/braggvectors_root"]
        manifest = session.attrs["mac4dstem_result_nodes"]
        if isinstance(manifest, bytes):
            manifest = manifest.decode("utf-8")
        nodes = manifest.split("\n")
        assert len(nodes) == 1, nodes
        expected_shape = tuple(bragg.Rshape)
    result = py4DSTEM.read(
        path, datapath=f"/braggvectors_root/{nodes[0]}"
    )
    assert isinstance(result, RealSlice), type(result)
    assert result.data.shape == expected_shape, (result.data.shape, expected_shape)
    print(f"PASS: {path.name} py4DSTEM BraggVectors + RealSlice readback")
