# Writes the ground-truth calibration fixture with py4DSTEM itself
# (References/py4DSTEM-dev, v0.14.x). Values must match the assertions in
# main.swift. The committed real_py4dstem.h5 was produced by this script;
# rerun it (venv with py4DSTEM installed) only to regenerate.
import sys
import numpy as np
import py4DSTEM

out = sys.argv[1] if len(sys.argv) > 1 else "real_py4dstem.h5"

dc = py4DSTEM.DataCube(np.arange(2 * 2 * 4 * 4, dtype=np.float32).reshape(2, 2, 4, 4))
cal = dc.calibration
cal.set_Q_pixel_size(0.0125)
cal.set_Q_pixel_units("A^-1")
cal.set_R_pixel_size(2.5)
cal.set_R_pixel_units("A")
cal.set_QR_flip(True)
cal.set_qx0_mean(31.5)
cal.set_qy0_mean(32.25)
cal.set_ellipse((1.02, 0.98, 0.35))

py4DSTEM.save(out, dc, mode="o")

# Print the datacube dataset path so run.sh/main.swift can target it.
import h5py
with h5py.File(out, "r") as f:
    paths = []
    f.visit(lambda name: paths.append(name) if name.endswith("/data") else None)
    print("datacube dataset paths:", paths)
