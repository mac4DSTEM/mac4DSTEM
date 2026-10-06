#!/usr/bin/env python3
"""Writes mac4DSTEMTests/Fixtures/edx-regmismatch-m1.json from the regmismatch truth (WP3 lane M, prediction M1).

The Swift test cannot read .npz, and References/ is gitignored, so the small part of the truth the mask transport
needs is committed: the planted affine, the per-phase masks on the 4D grid (as one label per pixel), and, on the EDS
grid, the generator's group map, outside fraction and expected counts per pixel. ~25 kB.

    python3 tools/demo-edx/dump_m1_fixture.py [References/demo-edx] [out.json]
"""
import json, sys
import numpy as np

src = sys.argv[1] if len(sys.argv) > 1 else "References/demo-edx"
out = sys.argv[2] if len(sys.argv) > 2 else "mac4DSTEMTests/Fixtures/edx-regmismatch-m1.json"
t = json.load(open(f"{src}/truth_edx_regmismatch.json"))
z = np.load(f"{src}/truth_edx_regmismatch_arrays.npz")
masks = z["phase_masks_4d_grid"]                      # (phase, ny, nx) bool, a partition
assert (masks.sum(0) == 1).all()
labels4d = masks.argmax(0)
g4, ge = t["grids"]["4d"], t["grids"]["eds"]
json.dump({
    "note": "from truth_edx_regmismatch.json + arrays by tools/demo-edx/dump_m1_fixture.py",
    "affine_2x3": t["planted_transform"]["affine_2x3_4d_pixel_centre_to_eds_pixel_centre"],
    "scan": [g4["nx"], g4["ny"]], "eds": [ge["nx"], ge["ny"]],
    "phase_names": t["phase_names"],
    "labels_4d": "".join(str(int(v)) for v in labels4d.ravel()),
    "eds_group_map": z["eds_group_map"].ravel().tolist(),
    "eds_outside_fraction": z["eds_outside_fraction"].ravel().tolist(),
    "eds_expected_counts": [round(float(v), 4) for v in z["eds_expected_total_counts_per_pixel"].ravel()],
    "realised_total_eds_counts_by_group": t["realised_total_eds_counts_by_group"],
    "expected_total_eds_counts_by_group": t["expected_total_eds_counts_by_group"],
}, open(out, "w"), separators=(",", ":"))
