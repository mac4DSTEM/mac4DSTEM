import sys, h5py, json, numpy as np
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
for fn in sys.argv[1:]:
    with h5py.File(fn, "r") as f:
        d = f["Data"]
        k = list(d["SpectrumStream"])[0]; g = d["SpectrumStream"][k]
        n = g["Metadata"].shape[1]
        det = md(g)["BinaryResult"]["Detector"]
        rows = []
        for c in range(n):
            m = md(g, c)
            dv = [v for v in m["Detectors"].values() if det in v.get("DetectorName","")][0]
            rows.append((c, dv.get("LiveTime"), dv.get("RealTime")))
        sc = md(g)["Scan"]
        print(fn.split("/")[-1][:40], "Dwell", sc.get("DwellTime"), "FrameTime", sc.get("FrameTime"), "cols:", [(c, round(float(l),4), round(float(r),4)) for c,l,r in rows][:6])
