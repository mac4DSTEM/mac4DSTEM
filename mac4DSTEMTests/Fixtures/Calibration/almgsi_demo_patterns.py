"""The Al-Mg-Si demo mean and max diffraction patterns (float64, stored as float32), and py4DSTEM f050d207 get_probe_size on each.

Run with the py4DSTEM 0.14.19 environment: python almgsi_demo_patterns.py AlMgSi_demo.h5 <out-dir>
Writes <out>/almgsi-demo-mean-128x128.f32 and <out>/almgsi-demo-max-128x128.f32 (row-major, detector file axis 2 = rows).
"""
import json, sys
import numpy as np
import h5py
from py4DSTEM.process.calibration.probe import get_probe_size

path, out = sys.argv[1], sys.argv[2]
with h5py.File(path, "r") as f:
    data = f["4DSTEM_experiment/data/datacubes/datacube_0/data"][...].astype(np.float64)
mean_dp = data.mean(axis=(0, 1))
max_dp = data.max(axis=(0, 1))
mean_dp.astype(np.float32).tofile(out + "/almgsi-demo-mean-128x128.f32")
max_dp.astype(np.float32).tofile(out + "/almgsi-demo-max-128x128.f32")
print(json.dumps({
    "mean_float64": [float(v) for v in get_probe_size(mean_dp)],
    "mean_float32_input": [float(v) for v in get_probe_size(mean_dp.astype(np.float32).astype(np.float64))],
    "max": [float(v) for v in get_probe_size(max_dp)],
}, indent=1))
