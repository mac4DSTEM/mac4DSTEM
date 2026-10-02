import sys, json, h5py, numpy as np, py4DSTEM
p = sys.argv[1]
root = py4DSTEM.read(p); print("root:", type(root).__name__)
with h5py.File(p, "r") as f:
    g = f["/scientific_bundle_root"]
    node = [k for k, v in g.items() if isinstance(v, h5py.Group) and "mac4dstem_kind" in v.attrs][0]
    print("node:", node, "attrs:", dict(g[node].attrs))
    print("data:", g[node]["data"][:].tolist(), "dim0:", g[node]["dim0"][:], "dim1:", g[node]["dim1"][:])
r = py4DSTEM.read(p, datapath=f"/scientific_bundle_root/{node}")
print("py4DSTEM:", type(r).__name__, r.data.shape, r.data.dtype, r.data.tolist())
print("dims:", [(d.name if hasattr(d,'name') else d) for d in getattr(r,'dims',[])], getattr(r, 'dim_units', None), getattr(r,'dim_names',None))
