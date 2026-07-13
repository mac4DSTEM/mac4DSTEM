#!/usr/bin/env python3
"""Source-locked SciPy/py4DSTEM orientation-matrix golden values.

The numeric cases were generated with py4DSTEM's export route:
`Rotation.from_matrix(matrix.T).as_euler("zxz")`. They are kept literal so
the standalone harness requires no NumPy or SciPy installation.
"""

import json
import math
import pathlib
import sys


repo = pathlib.Path(__file__).resolve().parents[2]
source = (
    repo / "References/py4DSTEM-dev/py4DSTEM/process/diffraction/crystal_ACOM.py"
).read_text(encoding="utf-8")
viz_source = (
    repo / "References/py4DSTEM-dev/py4DSTEM/process/diffraction/crystal_viz.py"
).read_text(encoding="utf-8")
contracts = (
    "orientation_matrix = orientation_matrix @ m3z",
    'R.from_matrix(matrix.T).as_euler("zxz")',
)
for line in contracts:
    if line not in source:
        raise SystemExit(f"py4DSTEM orientation contract changed; missing: {line}")
if "where columns represent projection directions" not in viz_source:
    raise SystemExit("py4DSTEM orientation-matrix column convention changed")

cases = [
    {
        "name": "identity",
        "matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
        "euler": [0, 0, 0],
    },
    {
        "name": "general_zxz",
        "matrix": [
            [0.321198595, 0.936226717, 0.142516655],
            [-0.698648921, 0.132668462, 0.703056729],
            [0.639313028, -0.325389941, 0.696706709],
        ],
        "euler": [0.2, 0.8, 1.1],
    },
    {
        "name": "phi_zero_gimbal_lock",
        "matrix": [
            [0.540302306, 0.841470985, 0],
            [-0.841470985, 0.540302306, 0],
            [0, 0, 1],
        ],
        "euler": [1.0, 0, 0],
    },
    {
        "name": "phi_pi_gimbal_lock",
        "matrix": [
            [0.921060994, 0.389418342, 0],
            [0.389418342, -0.921060994, 0],
            [0, 0, -1],
        ],
        "euler": [-0.4, math.pi, 0],
    },
    {
        "name": "zone_axis_plus_in_plane",
        "matrix": [
            [0.3484613493895782, -0.8984131101854109, 0.2672612419124244],
            [0.7221338039630941, 0.43909962817053944, 0.5345224838248488],
            [-0.5975763191052554, 0.006737951281444023, 0.8017837257372732],
        ],
        "euler": [0.46364760900080626, 0.6405223126794245, -1.5820713146786818],
        "zoneAxis": [1, 2, 3],
        "inPlaneAngle": 0.37,
    },
]

# orix 0.14.2 `DirectionColorKeyTSL(Oh).direction2color(...)` golden values.
# These include the three m-3m IPF vertices and two interior directions.
ipf_cases = [
    {"name": "ipf_001", "direction": [0, 0, 1], "rgb": [1, 0, 0]},
    {"name": "ipf_101", "direction": [1, 0, 1],
     "rgb": [0.00525592242, 1, 0]},
    {"name": "ipf_111", "direction": [1, 1, 1],
     "rgb": [0, 0.00881970516, 1]},
    {"name": "ipf_interior_red", "direction": [0.2, 0.1, 0.97],
     "rgb": [1, 0.366801918, 0.397165286]},
    {"name": "ipf_interior_green", "direction": [0.6, 0.2, 0.77],
     "rgb": [0.453458024, 1, 0.799399351]},
]

json.dump({"cases": cases, "ipfCases": ipf_cases}, sys.stdout, separators=(",", ":"))
sys.stdout.write("\n")
