#!/usr/bin/env python3
"""Writes the small HyperSpy-layout HDF5 files of HyperSpyAxesCalibrationTests (mac4DSTEM#204).

Run once with an h5py interpreter (python make_hyperspy_fixtures.py); the files beside this script are committed, so the test needs no
Python. The layout is the one HyperSpy 3.0 files have (checked on two public 4D-STEM files): root attributes `file_format` and
`file_format_version`, the array at Experiments/<title>/data, and one group axis-N per stored axis with the attributes name,
navigate, offset, scale, size and units. Tiny files."""
import pathlib
import numpy as np
import h5py

root = pathlib.Path(__file__).resolve().parent


def write(name, title, dtype, axes, shape=(2, 3, 4, 5)):
    with h5py.File(root / name, "w") as f:
        f.attrs["file_format"] = "HyperSpy"
        f.attrs["file_format_version"] = "3.0"
        g = f.create_group("Experiments/" + title)
        n = int(np.prod(shape))
        g.create_dataset("data", data=(np.arange(n) % 251).astype(dtype).reshape(shape))
        for i, (axis_name, scale, units, offset) in enumerate(axes):
            a = g.create_group("axis-%d" % i)
            a.attrs["name"] = axis_name
            a.attrs["navigate"] = i < len(shape) - 2
            a.attrs["offset"] = float(offset)
            a.attrs["scale"] = float(scale)
            a.attrs["size"] = shape[i]
            a.attrs["units"] = units


# A titled experiment, nanometres and "Å^-1": the spelling of the SPED scan of Zenodo 10.5281/zenodo.2652906.
write("angstrom-titled.hdf5", "6060 T6 0% scan5", np.float32,
      [("y", 1.536, "nm", 76.8), ("x", 1.536, "nm", 76.8), ("dy", 0.026, "Å^-1", -0.858), ("dx", 0.026, "Å^-1", -0.858)])
# An untitled experiment with LaTeX units: the spelling of the scan of Zenodo 10.5281/zenodo.5597738.
write("latex-untitled.hspy", "__unnamed__", np.uint16,
      [("y", 2.0, "nm", 0.0), ("x", 2.0, "nm", 0.0), ("ky", 0.01261, "$A^{-1}$", -1.61408), ("kx", 0.01261, "$A^{-1}$", -1.61408)])
# Axes HyperSpy left at their defaults: no calibration to take.
write("undefined-axes.hspy", "__unnamed__", np.uint16,
      [("y", 1.0, "<undefined>", 0.0), ("x", 1.0, "<undefined>", 0.0), ("ky", 1.0, "<undefined>", 0.0), ("kx", 1.0, "<undefined>", 0.0)])
