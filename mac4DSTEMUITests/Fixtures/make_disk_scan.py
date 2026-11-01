# Writes disk-scan.h5, the small py4DSTEM file the UI journeys open with --open (a real file through the real open path).
# An 8 x 8 scan of a 32 x 32 detector: one bright disk (radius 5 px) whose centre moves 1 px across the scan in x and y,
# so DPC has a signal and the origin fit has a disk to find. No calibration is stored: the file opens uncalibrated.
# Rerun with py4DSTEM installed (the reference venv) only to regenerate:  python make_disk_scan.py disk-scan.h5
import sys

import numpy as np
import py4DSTEM

out = sys.argv[1] if len(sys.argv) > 1 else "disk-scan.h5"
rx, ry, qx, qy, radius = 8, 8, 32, 32, 5.0
x, y = np.meshgrid(np.arange(qx), np.arange(qy), indexing="ij")
data = np.zeros((rx, ry, qx, qy), dtype=np.float32)
for i in range(rx):
    for j in range(ry):
        cx = 15.5 + (i - (rx - 1) / 2) / (rx - 1)
        cy = 15.5 + (j - (ry - 1) / 2) / (ry - 1)
        data[i, j] = np.where((x - cx) ** 2 + (y - cy) ** 2 <= radius**2, 100.0, 1.0)

py4DSTEM.save(out, py4DSTEM.DataCube(data), mode="o")
