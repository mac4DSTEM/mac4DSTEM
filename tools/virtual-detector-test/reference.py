#!/usr/bin/env python3
"""Generate virtual-detector golden values from source-locked py4DSTEM semantics.

The machine running the standalone harness need not have NumPy/py4DSTEM
installed. Instead, this script first asserts the exact detector predicates in
the checked-in py4DSTEM source, then evaluates those predicates over a small,
deterministic cube using only the Python standard library.
"""

import json
import pathlib
import sys


REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO / "References/py4DSTEM-dev/py4DSTEM/datacube/virtualimage.py"
PY4DSTEM = SOURCE.read_text(encoding="utf-8")

# Fail if the reference implementation changes underneath this equivalent
# standard-library calculation. These are the operative make_detector lines.
SOURCE_CONTRACT = (
    "mask[qx, qy] = 1",
    "(qxa - g[0][0]) ** 2 + (qya - g[0][1]) ** 2 < g[1] ** 2",
    "(qxa - g[0][0]) ** 2 + (qya - g[0][1]) ** 2 > g[1][0] ** 2",
    "(qxa - g[0][0]) ** 2 + (qya - g[0][1]) ** 2 < g[1][1] ** 2",
    "mask[xmin:xmax, ymin:ymax] = 1",
)
for line in SOURCE_CONTRACT:
    if line not in PY4DSTEM:
        raise SystemExit(f"py4DSTEM detector contract changed; missing: {line}")

# App order is [Ry, Rx, Qy, Qx]. py4DSTEM names the same axes
# [R_Nx, R_Ny, Q_Nx, Q_Ny], so py4DSTEM qx is the app's detector row/y and
# py4DSTEM qy is the app's detector column/x.
RY, RX, QY, QX = 2, 3, 5, 7


CASES = [
    {
        "name": "annulus_exact_inner_boundary",
        "kind": "annulus",
        "centerX": 3.0,
        "centerY": 2.0,
        "inner": 1.0,
        "outer": 2.5,
    },
    {
        "name": "annulus_fractional_center_near_edge",
        "kind": "annulus",
        "centerX": 0.25,
        "centerY": 0.5,
        "inner": 0.75,
        "outer": 3.2,
    },
    {
        "name": "circle_non_square_detector",
        "kind": "circle",
        "centerX": 4.25,
        "centerY": 1.5,
        "outer": 2.2,
    },
    {
        "name": "rectangle_half_open",
        "kind": "rectangle",
        "xMin": 1,
        "xMax": 6,
        "yMin": 1,
        "yMax": 4,
    },
    {
        "name": "point_last_detector_pixel",
        "kind": "point",
        "pointX": 6,
        "pointY": 4,
    },
]


def selected(case, y, x):
    kind = case["kind"]
    if kind in ("circle", "annulus"):
        # Translate app (x=column, y=row) to py4DSTEM (qx=row, qy=column).
        py_qx = y
        py_qy = x
        py_cx = case["centerY"]
        py_cy = case["centerX"]
        r2 = (py_qx - py_cx) ** 2 + (py_qy - py_cy) ** 2
        if kind == "circle":
            return r2 < case["outer"] ** 2
        return r2 > case["inner"] ** 2 and r2 < case["outer"] ** 2
    if kind == "rectangle":
        # py4DSTEM geometry is (qxMin,qxMax,qyMin,qyMax); the app presents
        # rectangle bounds as (x=column, y=row), hence the swapped comparison.
        return (
            case["yMin"] <= y < case["yMax"]
            and case["xMin"] <= x < case["xMax"]
        )
    if kind == "point":
        return y == case["pointY"] and x == case["pointX"]
    raise ValueError(kind)


def value(scan_index, y, x):
    # All values and sums stay exactly representable in Float32. The distinct
    # scan/row/column digits make transposes and boundary errors conspicuous.
    return scan_index * 10_000 + y * 100 + x


for case in CASES:
    case["expected"] = [
        sum(
            value(scan, y, x)
            for y in range(QY)
            for x in range(QX)
            if selected(case, y, x)
        )
        for scan in range(RY * RX)
    ]

json.dump(
    {"dimensions": [RY, RX, QY, QX], "cases": CASES},
    sys.stdout,
    separators=(",", ":"),
)
sys.stdout.write("\n")
