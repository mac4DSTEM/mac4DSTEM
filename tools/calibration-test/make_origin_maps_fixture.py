# Writes a non-square ground-truth origin-map fixture with the checked-in
# py4DSTEM 0.14.19 source. The distinct row/column values expose both scan-map
# transposition and the py4DSTEM qx/qy -> app y/x detector-axis conversion.
import pathlib
import sys

import numpy as np
import py4DSTEM


out = sys.argv[1] if len(sys.argv) > 1 else "real_py4dstem_origin_maps.h5"

data = np.arange(2 * 3 * 4 * 5, dtype=np.float32).reshape(2, 3, 4, 5)
dc = py4DSTEM.DataCube(data)
cal = dc.calibration
cal.set_Q_pixel_size(0.0125)
cal.set_Q_pixel_units("A^-1")
cal.set_R_pixel_size(2.5)
cal.set_R_pixel_units("A")
cal.set_QR_flip(True)
cal.set_QR_rotation(0.375)
cal.set_probe_param((7.25, 16.0, 36.0))

# Stored in py4DSTEM real-space order [R_Nx, R_Ny] = [2, 3].
qx0 = np.array([[10.0, 11.0, 12.0], [20.0, 21.0, 22.0]])
qy0 = np.array([[30.0, 31.0, 32.0], [40.0, 41.0, 42.0]])
cal.set_origin((qx0, qy0))

# Measured maps are deliberately different from the fitted maps.
cal.set_origin_meas((qx0 + 0.25, qy0 - 0.5))
cal.set_ellipse((1.02, 0.98, 0.35))

py4DSTEM.save(out, dc, mode="o")

print(f"wrote {pathlib.Path(out).resolve()}")
