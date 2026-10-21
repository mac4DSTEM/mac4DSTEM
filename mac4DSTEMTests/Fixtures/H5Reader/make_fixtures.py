#!/usr/bin/env python3
"""Writes the small HDF5 files of H5ReaderKitSwitchBaselineTests (FormatoKit 0.7.0 switch, 2026-10-21).

Run once with an h5py interpreter (python make_fixtures.py); the .h5 files beside this script are committed, so the test needs
no Python. Every array holds deterministic values that use the whole range of its type. Tiny files."""
import pathlib
import numpy as np
import h5py

root = pathlib.Path(__file__).resolve().parent


def ramp(shape, dtype, scale=1):
    n = int(np.prod(shape))
    a = (np.arange(n, dtype=np.float64) * scale - n / 3.0)
    return a.astype(dtype).reshape(shape)


def calibration(f, group="4DSTEM_experiment/data/datacubes/metadatabundle/calibration", qr_flip=True, as_attrs=False, flip_kind="enum_dataset"):
    g = f.require_group(group)
    q = {"Q_pixel_size": 0.0123456789, "R_pixel_size": 2.5, "qx0_mean": 64.25, "qy0_mean": 63.75, "a": 1.02, "b": 0.98,
         "theta": 0.3, "QR_rotation": -0.45, "probe_semiangle": 21.5}
    units = {"Q_pixel_units": "A^-1", "R_pixel_units": "nm", "QR_rotation_convention": "degrees"}
    if as_attrs:
        for k, v in q.items():
            g.attrs[k] = v
        for k, v in units.items():
            g.attrs[k] = v
    else:
        for k, v in q.items():
            g.create_dataset(k, data=np.float64(v))
        for k, v in units.items():
            g.create_dataset(k, data=v, dtype=h5py.string_dtype())
    if flip_kind == "enum_dataset":
        g.create_dataset("QR_flip", data=np.bool_(qr_flip))
    elif flip_kind == "enum_attr":
        g.attrs["QR_flip"] = np.bool_(qr_flip)
    elif flip_kind == "uint8_dataset":
        g.create_dataset("QR_flip", data=np.uint8(qr_flip))
    elif flip_kind == "int_attr":
        g.attrs["QR_flip"] = np.int64(1 if qr_flip else 0)
    elif flip_kind == "double_dataset":
        g.create_dataset("QR_flip", data=np.float64(1.0 if qr_flip else 0.0))
    elif flip_kind == "float16_dataset":
        g.create_dataset("QR_flip", data=np.float16(1.0 if qr_flip else 0.0))
    return g


def cube(f, path, shape=(3, 4, 5, 6), dtype=np.float32, **kw):
    return f.create_dataset(path, data=ramp(shape, dtype), **kw)


# ---- calibration forms ------------------------------------------------------------------------------------------------------------
for name, kw in {
    "cal_enum_dataset": dict(flip_kind="enum_dataset"),
    "cal_enum_dataset_false": dict(flip_kind="enum_dataset", qr_flip=False),
    "cal_enum_attr": dict(flip_kind="enum_attr"),
    "cal_uint8_dataset": dict(flip_kind="uint8_dataset"),
    "cal_int_attr": dict(flip_kind="int_attr"),
    "cal_double_dataset": dict(flip_kind="double_dataset"),
    "cal_float16_dataset": dict(flip_kind="float16_dataset"),
    "cal_attrs": dict(as_attrs=True, flip_kind="enum_attr"),
}.items():
    with h5py.File(root / (name + ".h5"), "w") as f:
        cube(f, "4DSTEM_experiment/data/datacubes/datacube_0/data", chunks=(1, 2, 5, 6), compression="gzip")
        g = calibration(f, **kw)
        if kw.get("as_attrs"):
            pass
        # per-position origins: float16 and float64 matrices of the scan shape
        g.create_dataset("qx0", data=ramp((3, 4), np.float16, 0.25))
        g.create_dataset("qy0", data=ramp((3, 4), np.float64, 0.5))
        g.create_dataset("qx0_meas", data=ramp((3, 4), np.float32, 0.75))
        g.create_dataset("qy0_meas", data=ramp((3, 4), np.float32, 0.125))

# a ellipse that must be refused whole, and a non-uniform dim vector
with h5py.File(root / "cal_bad_ellipse.h5", "w") as f:
    cube(f, "4DSTEM_experiment/data/datacubes/datacube_0/data")
    g = calibration(f)
    del g["a"]
    g.create_dataset("a", data=np.float64(-1.0))

# ---- EMD dim vectors ----------------------------------------------------------------------------------------------------------------
for name, dims_dtype in {"emd_dims_f64": np.float64, "emd_dims_f16": np.float16, "emd_dims_f32": np.float32}.items():
    with h5py.File(root / (name + ".h5"), "w") as f:
        g = f.create_group("Experiments/__unnamed__")
        g.create_dataset("data", data=ramp((3, 4, 5, 6), np.uint16, 7), chunks=(3, 4, 5, 6))
        for i, (step, u) in enumerate([(1.5, "nm"), (1.5, "nm"), (0.25, "1/nm"), (0.25, "1/nm")]):
            d = g.create_dataset("dim%d" % i, data=(np.arange(3 + i) * step + 10).astype(dims_dtype))
            d.attrs["units"] = u
with h5py.File(root / "emd_dims_rank3.h5", "w") as f:
    g = f.create_group("exp")
    g.create_dataset("data", data=ramp((7, 5, 6), np.int16, 3))
    for i, (step, u) in enumerate([(2.0, "nm"), (0.1, "1/nm"), (0.1, "1/nm")]):
        d = g.create_dataset("dim%d" % i, data=np.arange(7 - i) * step)
        d.attrs["units"] = u

# ---- stored types converted to Float -----------------------------------------------------------------------------------------------
with h5py.File(root / "dtypes.h5", "w") as f:
    g = f.create_group("dt")
    for name in ["int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64", "float16", "float32", "float64",
                 ">i2", ">u2", ">i4", ">f4", ">f8", "<i2"]:
        dt = np.dtype(name)
        shape = (2, 3, 4, 5)
        n = int(np.prod(shape))
        if dt.kind == "f":
            v = (np.arange(n) - n / 2.0) * 1234.56789e0
            v[3] = 65504 if dt.itemsize == 2 else 3.4e38 if dt.itemsize == 4 else 1.7e300
            v[5] = np.inf; v[7] = -0.0
            if dt.itemsize == 2:
                v[3] = 65504.0
        elif dt.kind == "u":
            info = np.iinfo(dt)
            v = np.linspace(0, info.max, n).astype(np.float64) if dt.itemsize < 8 else (np.arange(n, dtype=np.uint64) * np.uint64(1 << 55))
            v = v.astype(dt)
            v[2] = info.max; v[4] = 16777217 % (int(info.max) + 1)
        else:
            info = np.iinfo(dt)
            v = np.linspace(info.min, info.max, n).astype(dt) if dt.itemsize < 8 else (np.arange(n, dtype=np.int64) - n // 2) * np.int64(1 << 55)
            v[2] = info.min; v[4] = 16777217 if info.max >= 16777217 else 1
        g.create_dataset(name.replace(">", "be_").replace("<", "le_"), data=v.astype(dt).reshape(shape))

# ---- links ------------------------------------------------------------------------------------------------------------------------
with h5py.File(root / "links.h5", "w") as f:
    a = f.create_group("a")
    a.create_dataset("data", data=ramp((3, 4, 5, 6), np.float32))
    a.create_dataset("probe", data=ramp((5, 6), np.float32))
    f["b_alias"] = a                      # a hard link to the same group
    f["c_soft"] = h5py.SoftLink("/a")     # a soft link to a group
    f["dangling"] = h5py.SoftLink("/nowhere")
    p = f.create_group("probes")
    p.create_dataset("probe_template", data=ramp((5, 6, 2), np.float32))
    p.create_dataset("stack_probe", data=ramp((3, 5, 6), np.float32))
    f.create_group("zz/deeper").create_dataset("probe", data=ramp((5, 6), np.float32))
with h5py.File(root / "links_alias_first.h5", "w") as f:
    a = f.create_group("zeta")
    a.create_dataset("data", data=ramp((3, 4, 5, 6), np.float32))
    f["alpha_alias"] = a
with h5py.File(root / "links_cycle.h5", "w") as f:
    g = f.create_group("g")
    g.create_dataset("data", data=ramp((3, 4, 5, 6), np.float32))
    g["up"] = h5py.SoftLink("/")
    h = f.create_group("h")
    h["self"] = h

# ---- odd canonical nodes ------------------------------------------------------------------------------------------------------------
with h5py.File(root / "odd_scalar.h5", "w") as f:
    f.create_dataset("4DSTEM_experiment/data/datacubes/datacube_0/data", data=np.float32(3))
    f.create_dataset("other/data", data=ramp((3, 4, 5, 6), np.float32))
with h5py.File(root / "odd_rank5.h5", "w") as f:
    f.create_dataset("a/data", data=ramp((2, 2, 2, 2, 2), np.float32))
with h5py.File(root / "odd_empty.h5", "w") as f:
    f.create_dataset("4DSTEM_experiment/data/datacubes/datacube_0/data", data=h5py.Empty("f4"))
with h5py.File(root / "odd_string.h5", "w") as f:
    f.create_dataset("dm_dataset_root/dm_dataset/data", data=np.array([b"x", b"y"]))
with h5py.File(root / "odd_compound.h5", "w") as f:
    f.create_dataset("a/data", data=np.zeros((2, 2, 2, 2), dtype=[("x", "f4"), ("y", "f4")]))
with h5py.File(root / "odd_chunked_rank3.h5", "w") as f:
    f.create_dataset("a/data", data=ramp((9, 5, 6), np.float32), chunks=(2, 5, 6), compression="gzip", shuffle=True)
with open(root / "odd_not_hdf5.h5", "wb") as f:
    f.write(b"not an hdf5 file")
