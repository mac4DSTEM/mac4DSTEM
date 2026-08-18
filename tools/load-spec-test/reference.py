#!/usr/bin/env python3
"""Fixtures for tools/load-spec-test.

Every cube is filled with its own flat source index, so a cropped read that is
off by one position, one row or one detector column produces a *different
number*, not a plausible one. That is the whole point: the harness compares a
cropped read against a slice of a full read, and a fixture whose values did not
depend on position would let an offset error pass.

Writes: rank4.h5, rank3.h5 (HDF5), cube.dm4 (Gatan), empad.raw + empad.xml,
merlin.mib + merlin.hdr.
"""
import pathlib
import struct
import sys

try:
    import h5py
    import numpy as np
except ImportError as error:  # loud, never skipped
    sys.stderr.write(
        "load-spec-test needs h5py and numpy (%s). Set PYTHON=/path/to/python "
        "to an interpreter that has them.\n" % error
    )
    raise SystemExit(1)

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

# ---- HDF5, rank 4 -----------------------------------------------------------
H5_4D = (3, 4, 6, 5)
with h5py.File(root / "rank4.h5", "w") as f:
    group = f.create_group("4DSTEM_experiment/data/datacubes/datacube_0")
    cube = np.arange(int(np.prod(H5_4D)), dtype=np.float32).reshape(H5_4D)
    group.create_dataset("data", data=cube)

# ---- HDF5, rank 3 -----------------------------------------------------------
# H5Reader.describe() reshapes a rank-3 dataset to [1, N, Qy, Qx]: the whole
# dataset is one scan row. A scan crop therefore moves along the N axis.
H5_3D = (5, 6, 5)
with h5py.File(root / "rank3.h5", "w") as f:
    group = f.create_group("4DSTEM_experiment/data/datacubes/datacube_0")
    cube = np.arange(int(np.prod(H5_3D)), dtype=np.float32).reshape(H5_3D)
    group.create_dataset("data", data=cube)

# ---- DM4 --------------------------------------------------------------------
# Byte layout per docs/dm4-format.md and tools/dm4-robustness-test: structure
# fields big-endian, primitive values little-endian.
def u8(v):    return struct.pack(">B", v)
def u16be(v): return struct.pack(">H", v)
def u32be(v): return struct.pack(">I", v)
def u64be(v): return struct.pack(">Q", v)
def i32le(v): return struct.pack("<i", v)

def group_header(n_tags):
    return u8(1) + u8(0) + u64be(n_tags)

def number_tag(label, value):
    return (u8(21) + u16be(len(label)) + label.encode() + u64be(0) + b"%%%%"
            + u64be(1) + u64be(3) + i32le(value))

def subgroup_entry(label, n_tags):
    return u8(20) + u16be(len(label)) + label.encode() + u64be(0) + group_header(n_tags)

def array_tag(label, element_type, length, payload):
    return (u8(21) + u16be(len(label)) + label.encode() + u64be(0) + b"%%%%"
            + u64be(3) + u64be(20) + u64be(element_type) + u64be(length) + payload)

DM4 = (3, 4, 6, 5)   # ry, rx, qy, qx
count = DM4[0] * DM4[1] * DM4[2] * DM4[3]
payload = struct.pack("<%dh" % count, *range(count))
# Dimensions.{0,1,2,3} are fastest-first: Qx, Qy, Rx, Ry.
dims = (subgroup_entry("Dimensions", 4)
        + number_tag("0", DM4[3]) + number_tag("1", DM4[2])
        + number_tag("2", DM4[1]) + number_tag("3", DM4[0]))
image = (subgroup_entry("ImageData", 3)
         + number_tag("DataType", 1)          # 1 = int16
         + dims
         + array_tag("Data", 2, count, payload))
(root / "cube.dm4").write_bytes(
    u32be(4) + u64be(0) + u32be(1) + group_header(1) + image
)

# ---- EMPAD ------------------------------------------------------------------
# 130x128 float32 frames; the final two rows are the per-frame footer, so the
# reader's source detector is 128x128. Footer values are negative and distinct
# from every image value, so a crop that leaked into the footer would show up.
EMPAD_SCAN = (3, 4)
with (root / "empad.raw").open("wb") as f:
    for frame in range(EMPAD_SCAN[0] * EMPAD_SCAN[1]):
        base = frame * 128 * 128
        values = [float(base + i) for i in range(128 * 128)]
        values += [-float(frame + 1)] * (2 * 128)
        f.write(struct.pack("<%df" % len(values), *values))
(root / "empad.xml").write_text(
    '<root><raw_file filename="empad.raw"/><type>scan</type>'
    '<scan_parameters mode="acquire">'
    "<scan_resolution_x>%d</scan_resolution_x>"
    "<scan_resolution_y>%d</scan_resolution_y>"
    "</scan_parameters></root>" % (EMPAD_SCAN[1], EMPAD_SCAN[0])
)

# ---- MIB --------------------------------------------------------------------
MIB_SCAN = (2, 3)
fields = ["MQ1", "1", "384", "1", "0", "0", "U16", "1x1", "0",
          "2026-08-18 00:00:00", "0.001", "0", "0", "0", "0", "0", "0", "0", "12"]
header = (",".join(fields).encode("ascii") + b"\0").ljust(384, b"\0")
with (root / "merlin.mib").open("wb") as f:
    for frame in range(MIB_SCAN[0] * MIB_SCAN[1]):
        f.write(header)
        base = frame * 256 * 256
        f.write(struct.pack(">%dH" % (256 * 256),
                            *[(base + i) % 65535 for i in range(256 * 256)]))
(root / "merlin.hdr").write_text("ScanX:\t%d\nScanY:\t%d\n" % (MIB_SCAN[1], MIB_SCAN[0]))

print("load-spec-test fixtures written to %s" % root)
