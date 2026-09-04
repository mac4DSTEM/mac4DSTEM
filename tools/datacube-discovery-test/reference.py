#!/usr/bin/env python3
"""Fixtures for tools/datacube-discovery-test — WHICH node H5Reader returns.

Gate D, 2026-09-04: `describe` promotes a rank-3 dataset to one scan row and
`is4D` only counts dims, so any rank-3 array passed as a cube, and the path
sort (`/data` first, then shallowest, then alphabetical) let a shallow rank-3
sibling outrank a genuine rank-4 cube — wrong data, not a refusal. Every cube
here is filled with its own flat index so the harness can prove the PIXELS it
reads belong to the node it names, not merely the shape. Tiny arrays; no real
data. Labels follow the pinned upstream: emdfile-style stacks name the dim of
the last axis `_labels_` (`v13_emd_classes/io.py:390,429`); legacy v0.12 numbers
dims from 1 and keeps slice labels as strings in `dim{rank}`
(`read_v0_12.py:365`); this app's sidecar writer stamps `RGBA` / `rgba8`.
The x*, y* cases are the Gate B refuter's (2026-09-04), one per mutation that
survived the first harness, ported here so they gate.
"""
import pathlib
import sys

try:
    import h5py
    import numpy as np
except ImportError as error:  # loud, never skipped
    sys.stderr.write(
        "datacube-discovery-test needs h5py and numpy (%s). Set PYTHON=/path/to/python "
        "to an interpreter that has them.\n" % error
    )
    raise SystemExit(1)

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

SCHEMA_ATTRIBUTE = "mac4dstem_session_schema"   # HDF5Types.swift SessionSidecarFormat
SIDECAR_ROOT = "braggvectors_root"


def cube(shape, dtype=np.float32, offset=0):
    return np.arange(int(np.prod(shape)), dtype=dtype).reshape(shape) + offset


def dim(group, n, values, name=None, units=None):
    d = group.create_dataset("dim%d" % n, data=np.asarray(values, dtype=np.float64))
    if name is not None:
        d.attrs["name"] = name
    if units is not None:
        d.attrs["units"] = units


def labels(group, n, names):
    d = group.create_dataset("dim%d" % n, data=np.array([s.encode() for s in names]))
    d.attrs["name"] = "_labels_"


def variable_labels(group, n, names):
    dtype = h5py.string_dtype(encoding="utf-8")
    d = group.create_dataset("dim%d" % n, data=np.asarray(names, dtype=dtype))


def rgba(group, stamp_name=True, stamp_units=True):
    d = group.create_dataset("data", data=cube((100, 84, 4), np.uint8))
    if stamp_units:
        d.attrs["units"] = "rgba8"
    dim(group, 0, [0, 1], "Rx", "pixels")
    dim(group, 1, [0, 1], "Ry", "pixels")
    dim(group, 2, [0, 1], "RGBA" if stamp_name else "channel", "channel")


# ---- the original Gate D cases ---------------------------------------------

# e1 — the only node is an UNLABELLED channel-last image. Nothing says it is not a
# cube, so the rank-3 contract applies and it opens as one scan row. Pinned so a
# future size floor is a deliberate change.
with h5py.File(root / "e1_rank3_only.h5", "w") as f:
    f.create_group("results").create_dataset("data", data=cube((50, 200, 4), np.uint8))

# e2 — a genuine rank-4 cube at a DEEP non-canonical path and a SHALLOW labelled
# strain stack whose path also ends in /data. Its dims would hand pixelCalibration
# an rSize of 1.0 if the anchor did not land on the cube.
with h5py.File(root / "e2_shallow_sibling.h5", "w") as f:
    f.create_group("experiment/scan_1/datacube").create_dataset("data", data=cube((3, 4, 6, 5)))
    s = f.create_group("strain")
    s.create_dataset("data", data=cube((3, 4, 6)))
    dim(s, 0, np.arange(3), "Rx", "pixels")
    dim(s, 1, np.arange(4), "Ry", "pixels")
    labels(s, 2, ["exx", "eyy", "exy", "theta", "mask", "err"])

# e3 — the calibrationData_bullseyeProbe.h5 layout (legacy v0.12: 1-based dims, a
# string-typed dim3 on the probe stack) with the slice group renamed to sort
# BEFORE `datacubes`. Before the fix the alphabet decided.
with h5py.File(root / "e3_bullseye_alphabet.h5", "w") as f:
    f.create_group("4DSTEM_experiment/data/datacubes/polyAu").create_dataset(
        "data", data=cube((2, 2, 8, 8), np.uint16))
    p = f.create_group("4DSTEM_experiment/data/aaa_slices/probe_template")
    p.create_dataset("data", data=cube((8, 8, 3), np.uint16))
    dim(p, 1, np.arange(8), "Q_x", "[pix]")
    dim(p, 2, np.arange(8), "Q_y", "[pix]")
    p.create_dataset("dim3", data=np.array([b"0", b"1", b"2"], dtype="S64"))

# e4 — a results-only file shaped like this app's sidecar but WITHOUT the schema
# attribute: only the label rule can see it.
with h5py.File(root / "e4_results_no_attribute.h5", "w") as f:
    rgba(f.create_group("%s/result_acom_full_ipf_z_deadbeef" % SIDECAR_ROOT))

# c1 — rank-4 only, deep non-canonical path.
with h5py.File(root / "c1_rank4_only.h5", "w") as f:
    f.create_group("lab/session/scan_07/cube").create_dataset("data", data=cube((3, 4, 6, 5)))

# c2 — the load-spec-test rank-3 shape at the canonical path: one scan row.
with h5py.File(root / "c2_rank3_cube.h5", "w") as f:
    f.create_group("4DSTEM_experiment/data/datacubes/datacube_0").create_dataset(
        "data", data=cube((5, 6, 5)))

# c3 — an emdfile-style labelled stack and nothing else. Its dims (spacing 1)
# would calibrate a stale anchor after the refusal.
with h5py.File(root / "c3_labelled_stack_only.h5", "w") as f:
    s = f.create_group("4DSTEM/probe")
    s.create_dataset("data", data=cube((8, 8, 3)))
    dim(s, 0, np.arange(8), "Qx", "pixels")
    dim(s, 1, np.arange(8), "Qy", "pixels")
    labels(s, 2, ["a", "b", "c"])

# c4 — a rank-3 line scan at a non-canonical path with ASYMMETRIC EMD dims: the
# scan axis is dim0 (3.0 nm), the detector axes dim1 (0.5) and dim2 (0.25 1/nm).
# A labelled stack that sorts AFTER it is described and refused later, with
# spacings 2 and 7 — a stale anchor, or the stored-rank-4 dim mapping applied to
# a promoted node, each produce a different wrong number.
with h5py.File(root / "c4_rank3_noncanonical.h5", "w") as f:
    g = f.create_group("Experiments/line_scan")
    g.create_dataset("data", data=cube((7, 16, 12)))
    dim(g, 0, np.arange(7) * 3.0, "x", "nm")
    dim(g, 1, np.arange(16) * 0.5, "ky", "1/nm")
    dim(g, 2, np.arange(12) * 0.25, "kx", "1/nm")
    t = f.create_group("zz_results/strain")
    t.create_dataset("data", data=cube((7, 16, 6)))
    dim(t, 0, np.arange(7) * 2.0, "x", "nm")
    dim(t, 1, np.arange(16) * 7.0, "ky", "nm")
    labels(t, 2, ["exx", "eyy", "exy", "theta", "mask", "err"])

# c5 — a labelled STACK OF RANK-4: the rule is about the last axis, not the rank.
with h5py.File(root / "c5_labelled_rank4_only.h5", "w") as f:
    s = f.create_group("stack")
    s.create_dataset("data", data=cube((4, 4, 8, 2)))
    dim(s, 0, np.arange(4), "Rx", "pixels")
    dim(s, 1, np.arange(4), "Ry", "pixels")
    dim(s, 2, np.arange(8), "Qx", "pixels")
    labels(s, 3, ["first", "second"])

# ---- the Gate B refuter's cases ----------------------------------------------

# x1 — a CANONICAL rank-3 node and a genuine rank-4 elsewhere: the canonical
# path is the file's own declaration and wins (contract, not defect).
with h5py.File(root / "x1_canonical_rank3_vs_deep_rank4.h5", "w") as f:
    f.create_group("4DSTEM_experiment/data/datacubes/datacube_0").create_dataset("data", data=cube((5, 6, 5)))
    f.create_group("zz/real/cube").create_dataset("data", data=cube((3, 4, 6, 5)))

# x2 — a legacy v0.12 slice stack ALONE, string-typed dim3 (the real bullseye
# probe_template layout); x2n — the same with a NUMERIC dim3, which upstream's
# own test does not call labels: it opens as one scan row (recorded residual).
with h5py.File(root / "x2_legacy12_stack_only.h5", "w") as f:
    p = f.create_group("4DSTEM_experiment/data/diffractionslices/probe_template")
    p.create_dataset("data", data=cube((8, 8, 3), np.uint16))
    dim(p, 1, np.arange(8), "Q_x", "[pix]")
    dim(p, 2, np.arange(8), "Q_y", "[pix]")
    p.create_dataset("dim3", data=np.array([b"probe", b"kernel", b"mask"]))
with h5py.File(root / "x2n_legacy12_numeric_dim3.h5", "w") as f:
    p = f.create_group("4DSTEM_experiment/data/diffractionslices/probe_template")
    p.create_dataset("data", data=cube((8, 8, 3), np.uint16))
    dim(p, 1, np.arange(8), "Q_x", "[pix]")
    dim(p, 2, np.arange(8), "Q_y", "[pix]")
    dim(p, 3, np.arange(3))

# x2v — the same legacy layout with variable-length UTF-8 labels. The reader
# must judge HDF5's string class, not only fixed-width S datasets.
with h5py.File(root / "x2v_legacy12_vlen_labels.h5", "w") as f:
    p = f.create_group("4DSTEM_experiment/data/diffractionslices/probe_template")
    p.create_dataset("data", data=cube((8, 8, 3), np.uint16))
    dim(p, 1, np.arange(8), "Q_x", "[pix]")
    dim(p, 2, np.arange(8), "Q_y", "[pix]")
    variable_labels(p, 3, ["probe", "kernel", "mask"])

# x3 — a labelled stack at the FILE ROOT: "/data", dims at "/dim0…".
with h5py.File(root / "x3_root_level_stack.h5", "w") as f:
    f.create_dataset("data", data=cube((8, 8, 3)))
    dim(f, 0, np.arange(8), "Qx", "pixels")
    dim(f, 1, np.arange(8), "Qy", "pixels")
    labels(f, 2, ["a", "b", "c"])

# x4a / x4b — an RGBA map carrying only ONE of the writer's two stamps.
with h5py.File(root / "x4a_rgba_units_only.h5", "w") as f:
    rgba(f.create_group("results/ipf"), stamp_name=False, stamp_units=True)
with h5py.File(root / "x4b_rgba_name_only.h5", "w") as f:
    rgba(f.create_group("results/ipf"), stamp_name=True, stamp_units=False)

# x6 — TWO stored rank-4 cubes: the first in path order wins (contract; two
# pinned real files hold two cubes each).
with h5py.File(root / "x6_two_rank4_cubes.h5", "w") as f:
    f.create_group("aaa/cube").create_dataset("data", data=cube((2, 3, 4, 5)))
    f.create_group("zzz/cube").create_dataset("data", data=cube((2, 3, 4, 5), offset=10000))

# x7 — a CANONICAL node the rule refuses (an RGBA map with dims of spacing 5),
# then a real rank-4 with its own dims (1 nm, 0.5 1/nm).
with h5py.File(root / "x7_canonical_refused_then_cube.h5", "w") as f:
    g = f.create_group("4DSTEM_experiment/data/datacubes/datacube_0")
    d = g.create_dataset("data", data=cube((100, 84, 4), np.uint8))
    d.attrs["units"] = "rgba8"
    dim(g, 0, [0, 5], "Rx", "nm")
    dim(g, 1, [0, 5], "Ry", "nm")
    dim(g, 2, [0, 1], "RGBA", "channel")
    c = f.create_group("zz/real/cube")
    c.create_dataset("data", data=cube((3, 4, 6, 5)))
    dim(c, 0, [0, 1], "Rx", "nm")
    dim(c, 1, [0, 1], "Ry", "nm")
    dim(c, 2, [0, 0.5], "Qx", "1/nm")
    dim(c, 3, [0, 0.5], "Qy", "1/nm")

# x8 — TWO accepted unlabelled rank-3 nodes: the first in path order wins.
with h5py.File(root / "x8_two_rank3.h5", "w") as f:
    f.create_group("aaa/one").create_dataset("data", data=cube((5, 6, 7)))
    f.create_group("zzz/two").create_dataset("data", data=cube((5, 6, 7), offset=10000))

# x11 — an UNLABELLED rank-3 that sorts BEFORE a genuine rank-4: only the
# stored-rank preference separates them (no label can), so this is the one
# case that pins the preference itself.
with h5py.File(root / "x11_unlabelled_rank3_before_rank4.h5", "w") as f:
    f.create_group("aaa/scan").create_dataset("data", data=cube((5, 6, 7)))
    f.create_group("zzz/cube").create_dataset("data", data=cube((3, 4, 6, 5), offset=10000))

# x12 — a root-level /data rank-3 before a deeper genuine rank-4 in the
# arbitrary-link sort. Only stored-rank preference can separate these.
with h5py.File(root / "x12_root_rank3_before_deep_rank4.h5", "w") as f:
    f.create_dataset("data", data=cube((5, 6, 7)))
    f.create_group("zz/real/cube").create_dataset("data", data=cube((3, 4, 6, 5), offset=10000))

# x13 — a modern/unclassified rank-4 cube with an unrelated string sibling
# named like a legacy dim. Context, not the name alone, decides the v0.12 rule.
with h5py.File(root / "x13_modern_cube_unrelated_string_sibling.h5", "w") as f:
    g = f.create_group("modern/cube")
    g.create_dataset("data", data=cube((2, 3, 4, 5)))
    dim(g, 0, [0, 1], "Ry", "pixels")
    dim(g, 1, [0, 1], "Rx", "pixels")
    dim(g, 2, [0, 1], "Qy", "pixels")
    dim(g, 3, [0, 1], "Qx", "pixels")
    g.create_dataset("dim4", data=np.asarray(["unrelated metadata"], dtype=h5py.string_dtype(encoding="utf-8")))

# x9 — a rank-3 cube WITH py4DSTEM origin maps, and a refused sibling of a
# DIFFERENT scan shape described after it: a stale anchor SHAPE loses the maps.
with h5py.File(root / "x9_origin_maps_anchor.h5", "w") as f:
    g = f.create_group("aaa_root/cube")
    g.create_dataset("data", data=cube((7, 16, 12)))
    dim(g, 0, np.arange(7), "x", "nm")
    dim(g, 1, np.arange(16), "ky", "1/nm")
    dim(g, 2, np.arange(12), "kx", "1/nm")
    cal = f.create_group("aaa_root/metadatabundle/calibration")
    cal.create_dataset("qx0", data=np.zeros((1, 7)) + 3.5)
    cal.create_dataset("qy0", data=np.zeros((1, 7)) + 4.5)
    t = f.create_group("zzz/stack")
    t.create_dataset("data", data=cube((9, 4, 6)))
    dim(t, 0, np.arange(9) * 2, "x", "nm")
    dim(t, 1, np.arange(4) * 2, "ky", "1/nm")
    labels(t, 2, ["a", "b", "c", "d", "e", "f"])

# y1 / y2 — a marked session sidecar whose rank-3 node carries NEITHER stamp:
# the location guarantee, independent of what a writer stamped. y3 — the mark
# at the root group only speaks for that subtree: a cube outside it opens.
with h5py.File(root / "y1_sidecar_file_root_mark.h5", "w") as f:
    f.attrs[SCHEMA_ATTRIBUTE] = "1"
    f.create_group("%s/result_something" % SIDECAR_ROOT).create_dataset(
        "data", data=cube((50, 200, 4), np.uint8))
with h5py.File(root / "y2_sidecar_root_group_mark.h5", "w") as f:
    r = f.create_group(SIDECAR_ROOT)
    r.attrs[SCHEMA_ATTRIBUTE] = "1"
    r.create_group("result_something").create_dataset("data", data=cube((50, 200, 4), np.uint8))
with h5py.File(root / "y3_sidecar_mark_and_cube_outside.h5", "w") as f:
    r = f.create_group(SIDECAR_ROOT)
    r.attrs[SCHEMA_ATTRIBUTE] = "1"
    r.create_group("result_something").create_dataset("data", data=cube((50, 200, 4), np.uint8))
    f.create_group("datacube_root/datacube").create_dataset("data", data=cube((3, 4, 6, 5)))

# y4 — a future/foreign writer marks the FILE ROOT. Even a canonical-looking
# dataset is still sidecar content; the root mark is stronger than path order.
with h5py.File(root / "y4_file_root_mark_canonical_name.h5", "w") as f:
    f.attrs[SCHEMA_ATTRIBUTE] = "1"
    f.create_group("4DSTEM_experiment/data/datacubes/datacube_0").create_dataset(
        "data", data=cube((5, 6, 5))
    )
