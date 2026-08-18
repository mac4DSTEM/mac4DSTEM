#!/usr/bin/env python3
"""Ground truth for tools/preprocess-crop-bin-test, from py4DSTEM itself.

WHY py4DSTEM AND NOT THE bin2/bin8 TRAINING PAIR the plan names. There is no
pair: `References/training_dataset/` holds ONE Particle_1 file, whose name
carries both tokens (`…_bin2_cl-600mm_300kV_bin8.h5`) because one describes the
acquisition and the other a later reduction. Checked 2026-08-18. Binning against
`preprocess.bin_data_diffraction` is the stronger arbiter anyway: it is the
reference implementation the app is required to match, and it pins the
edge-remainder rule and sum-not-average directly rather than transitively.

EXACTNESS. The cubes are filled with small integers, so every partial sum is
exact in float32 and the comparison can be `==` regardless of the order the two
implementations accumulate in. With arbitrary float data a bit-identical claim
would be false — NumPy's pairwise summation over a reshaped axis need not match
a nested loop — and stating a tolerance would then hide a real disagreement.
"""
import json
import pathlib
import sys

try:
    import numpy as np
    import h5py
    from py4DSTEM.preprocess import preprocess
except ImportError as error:
    sys.stderr.write(
        "preprocess-crop-bin-test needs numpy, h5py and the vendored py4DSTEM "
        "(%s). Run via run.sh, which sets PYTHONPATH.\n" % error
    )
    raise SystemExit(1)


class FakeCalibration:
    def __init__(self, q_pixel_size):
        self._q = q_pixel_size
        self._units = "A^-1"

    def get_Q_pixel_size(self):
        return self._q

    def get_Q_pixel_units(self):
        return self._units

    def set_Q_pixel_size(self, value):
        self._q = value


class FakeDataCube:
    """The surface `bin_data_diffraction` touches, and nothing else.

    Constructing a real DataCube would drag in the EMD tree and its own
    calibration propagation; this keeps the arbiter to the array math under
    test, which is what the app is required to reproduce.
    """

    def __init__(self, data, q_pixel_size):
        self.data = data
        self.calibration = FakeCalibration(q_pixel_size)
        self.R_Nx, self.R_Ny, self.Q_Nx, self.Q_Ny = data.shape

    def set_dim(self, *args, **kwargs):
        pass


root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

Q_PIXEL_SIZE = 0.0125

# Cases chosen so each one can only pass for the right reason:
#  * a detector that divides cleanly, to pin the plain reduction;
#  * one that divides on NEITHER axis, to pin the edge remainder on both;
#  * one that divides on exactly one axis, which is a separate branch in
#    py4DSTEM (preprocess.py:182-190) and the one an asymmetric bug survives;
#  * a crop combined with a bin, where the crop must be applied first.
CASES = [
    {"name": "divisible", "shape": [2, 3, 16, 12], "bin": 4, "crop": None},
    {"name": "remainder_both_axes", "shape": [2, 3, 14, 11], "bin": 4, "crop": None},
    {"name": "remainder_rows_only", "shape": [2, 3, 14, 12], "bin": 4, "crop": None},
    {"name": "remainder_columns_only", "shape": [2, 3, 16, 11], "bin": 4, "crop": None},
    {"name": "bin_two", "shape": [2, 3, 10, 9], "bin": 2, "crop": None},
    {"name": "bin_eight", "shape": [2, 2, 20, 17], "bin": 8, "crop": None},
    # Crop first, then bin: the crop is 9 x 10, which the factor 4 trims to 8 x 8.
    {"name": "crop_then_bin", "shape": [3, 3, 16, 16], "bin": 4,
     "crop": {"yOffset": 3, "xOffset": 2, "height": 9, "width": 10}},
]

manifest = []
for case in CASES:
    ry, rx, qy, qx = case["shape"]
    count = ry * rx * qy * qx
    # Small integers: exact in float32, and every element distinct so a
    # transposed or mis-strided read changes a value rather than shuffling.
    cube = (np.arange(count, dtype=np.float32) % 97).reshape(case["shape"])

    with h5py.File(root / ("%s.h5" % case["name"]), "w") as f:
        group = f.create_group("4DSTEM_experiment/data/datacubes/datacube_0")
        group.create_dataset("data", data=cube)

    # Apply the crop OUTSIDE py4DSTEM, exactly as a reader would, so the
    # reference for the combined case is still py4DSTEM's own bin of the
    # cropped array rather than a second app-shaped opinion.
    source = cube
    if case["crop"] is not None:
        c = case["crop"]
        source = cube[:, :,
                      c["yOffset"]:c["yOffset"] + c["height"],
                      c["xOffset"]:c["xOffset"] + c["width"]]

    datacube = FakeDataCube(source.copy(), Q_PIXEL_SIZE)
    preprocess.bin_data_diffraction(datacube, case["bin"])

    expected = np.ascontiguousarray(datacube.data, dtype=np.float32)
    expected.tofile(root / ("%s.expected" % case["name"]))
    manifest.append({
        "name": case["name"],
        "shape": case["shape"],
        "bin": case["bin"],
        "crop": case["crop"],
        "expectedShape": list(expected.shape),
        "qPixelSize": Q_PIXEL_SIZE,
        "binnedQPixelSize": datacube.calibration.get_Q_pixel_size(),
    })

(root / "manifest.json").write_text(json.dumps(manifest, indent=2))
print("preprocess-crop-bin-test: %d py4DSTEM references written" % len(manifest))
