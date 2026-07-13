"""Inject a valid external EMD Array unknown to the mac4DSTEM manifest."""
import sys
import h5py
import numpy as np

with h5py.File(sys.argv[1], "r+") as f:
    root = f["/braggvectors_root"]
    group = root.create_group("external_analysis")
    group.attrs["emd_group_type"] = "array"
    group.attrs["python_class"] = "Array"
    data = group.create_dataset("data", data=np.array([3.0, 1.0, 4.0], dtype=np.float32))
    data.attrs["units"] = "arbitrary"
    dim = group.create_dataset("dim0", data=np.array([0.0, 2.0], dtype=np.float64))
    dim.attrs["name"] = "external axis"
    dim.attrs["units"] = "sample"
