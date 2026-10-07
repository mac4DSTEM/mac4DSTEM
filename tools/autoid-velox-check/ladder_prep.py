#!/usr/bin/env python3
"""Prepares the demo-edx dose ladder (tools/demo-edx/run.sh --ladder; References/demo-edx/AlMgSi_edx_ladder.hspy + truth_edx_ladder.json) for
`main --ladder <dir>` (lane L12, 2026-10-07, H3's refutation test): one pooled spectrum per region (16 x 16 pixels, uint64 little-endian) and a meta file
with the axis, the beam and the PLANTED elements (every element with a line component of expected counts > 0 in that region; sum peaks, the Al K tail and
escapes are not elements). Needs h5py + numpy (the py4dstem conda env).

    ladder_prep.py <out dir> [<demo-edx dir>]"""
import json, os, sys
import h5py, numpy as np

out = sys.argv[1]; src = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "../../References/demo-edx")
os.makedirs(out, exist_ok=True)
truth = json.load(open(os.path.join(src, "truth_edx_ladder.json")))
data = h5py.File(os.path.join(src, truth["file"]), "r")["Experiments/__unnamed__/data"][...]          # (16, 128, 4096)
disp, origin = truth["energy_axis"]["dispersion_eV"], truth["energy_axis"]["origin_channel"]
for i, r in enumerate(truth["regions"]):
    c0, c1 = r["columns"]
    spec = data[:, c0:c1 + 1, :].sum(axis=(0, 1)).astype("<u8")
    elems = sorted({k.split("_")[0] for k, v in r["components_expected_total_counts"].items()
                    if v > 0 and not k.startswith("sum_") and "tail" not in k and "escape" not in k and "internal" not in k})
    spec.tofile(os.path.join(out, f"{i:02d}.spectrum.u64"))
    json.dump({"region": i + 1, "recipe": r["recipe"], "dose": r.get("target_mean_total_counts_per_pixel"), "realisedCounts": int(spec.sum()),
               "offsetKeV": -origin * disp / 1000.0, "scaleKeV": disp / 1000.0, "beamKeV": 200.0, "truth": elems},
              open(os.path.join(out, f"{i:02d}.meta.json"), "w"), indent=1)
    print(i + 1, r["recipe"], r.get("target_mean_total_counts_per_pixel"), int(spec.sum()), elems)
