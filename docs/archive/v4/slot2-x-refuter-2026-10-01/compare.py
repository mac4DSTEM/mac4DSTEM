import sys, subprocess, numpy as np, os
sys.path.insert(0, "/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/py4DSTEM-dev")
import py4DSTEM
rng = np.random.default_rng(7)
fails = 0; cases = 0; nonempty = 0
shapes = [(8,9),(3,3),(2,5),(1,7),(5,5),(4,4),(6,12),(2,2),(1,1),(3,2)]
for trial in range(400):
    H, W = shapes[trial % len(shapes)]
    R0, R1 = 2, 2
    # small integers with many ties; plant hot pixels incl. adjacent pairs
    cube = rng.integers(0, 6, size=(R0,R1,H,W)).astype(np.float32)
    k = rng.integers(0, 4)
    for _ in range(k):
        r, c = rng.integers(0,H), rng.integers(0,W)
        cube[:, :, r, c] += rng.integers(10, 2000)
        if rng.random() < 0.5 and c+1 < W: cube[:, :, r, c+1] += rng.integers(10, 2000)
    thresh = float(rng.choice([0.0, 1.0, 2.5, 8.0, 20.0]))
    raw = f"raw{trial}.bin"; out = f"out{trial}.bin"
    cube.tofile(raw)
    res = subprocess.run(["./driver", raw, str(R0), str(R1), str(H), str(W), str(thresh), out], capture_output=True, text=True)
    swift_mask = [int(x) for x in res.stdout.split()]
    swift_out = np.fromfile(out, dtype=np.float32).reshape(R0,R1,H,W)
    dc = py4DSTEM.DataCube(data=cube.copy())
    import io, contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        dc, mask = dc.filter_hot_pixels(thresh, return_mask=True)
    py_mask = [int(r*W+c) for r, c in np.argwhere(mask)]
    cases += 1
    if py_mask: nonempty += 1
    ok = (swift_mask == py_mask) and np.array_equal(swift_out, dc.data)
    if not ok:
        fails += 1
        print("FAIL trial", trial, "shape", (H,W), "thresh", thresh, "swift", swift_mask, "py", py_mask,
              "data differ at", np.argwhere(swift_out != dc.data)[:5].tolist())
    os.remove(raw); os.remove(out)
print(f"cases {cases}, nonempty masks {nonempty}, failures {fails}")
