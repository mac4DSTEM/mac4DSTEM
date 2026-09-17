"""Write the ground truth at the same stride as subsample.py, as the JSON
`tools/phase-map-probe --thronsen` reads. Labels per their
create_ground_truth.ipynb: 0 Al, 1 θ′ edge-on, 2 θ′ face-on, 3 T1, 4 the
three annotators' disagreement.

usage: make_truth.py <out.json> [stride=3]
"""
import sys, os, io, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rangefile import RangeFile
import h5py, numpy as np
out = sys.argv[1]; stride = int(sys.argv[2]) if len(sys.argv) > 2 else 3
f = RangeFile("https://zenodo.org/api/records/6645396/files/ground_truth.hspy/content", block=65536)
with h5py.File(io.BufferedReader(f), "r") as h:
    g = h["Experiments"][list(h["Experiments"].keys())[0]]
    gt = g["data"][()]
sub = gt[::stride, ::stride]
json.dump({"source": "Thronsen et al. 2024, Zenodo 10.5281/zenodo.6645396 ground_truth.hspy (CC BY 4.0), every %dth row and column" % stride,
           "classes": {"0": "Al", "1": "θ′ edge-on", "2": "θ′ face-on", "3": "T1", "4": "disagreement"},
           "labels": sub.tolist()}, open(out, "w"))
u, c = np.unique(sub, return_counts=True)
print("truth", sub.shape, dict(zip(u.tolist(), c.tolist())))
