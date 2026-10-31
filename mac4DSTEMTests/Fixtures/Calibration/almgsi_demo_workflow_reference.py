"""py4DSTEM f050d207 virtual images on the Al-Mg-Si demo, and the precipitate positions per grain from truth.json.

Run with the py4DSTEM 0.14.19 environment: python almgsi_demo_workflow_reference.py AlMgSi_demo.h5 truth.json
"""
import json, sys
import numpy as np
import h5py
import py4DSTEM

with h5py.File(sys.argv[1], "r") as f:
    data = f["4DSTEM_experiment/data/datacubes/datacube_0/data"][...].astype(np.float64)
dc = py4DSTEM.DataCube(data=data)
bf = dc.get_virtual_image(mode="circle", geometry=((63.5, 63.5), 5), name="bf", returncalc=True).data
adf = dc.get_virtual_image(mode="annulus", geometry=((63.5, 63.5), (10, 60)), name="adf", returncalc=True).data
print(json.dumps({"bf": [float(bf.sum()), float(bf[0, 0]), float(bf[50, 50])],
                  "adf": [float(adf.sum()), float(adf[0, 0]), float(adf[50, 50])]}))
truth = json.load(open(sys.argv[2]))
pm = np.array(truth["precipitate_map"])
print("precipitate_map shape", pm.shape, "codes", truth.get("precipitate_codes"))
cols = np.arange(100)[None, :].repeat(100, 0)
rows = np.arange(100)[:, None].repeat(100, 1)
for name, sel in (("A", cols <= 54), ("B", (cols >= 55) & (rows <= 49)), ("C", (cols >= 55) & (rows >= 50))):
    print(name, "precipitate positions", int(((pm != 0) & sel).sum()))
