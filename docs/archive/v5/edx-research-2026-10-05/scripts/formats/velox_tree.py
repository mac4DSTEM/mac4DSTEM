import sys, h5py, json, numpy as np
def show(name, obj):
    if isinstance(obj, h5py.Dataset):
        print(f"D {name} shape={obj.shape} dtype={obj.dtype} chunks={obj.chunks} compression={obj.compression} filters={obj.compression_opts}")
    else:
        print(f"G {name}")
for fn in sys.argv[1:]:
    print("=====", fn)
    with h5py.File(fn, "r") as f:
        f.visititems(show)
