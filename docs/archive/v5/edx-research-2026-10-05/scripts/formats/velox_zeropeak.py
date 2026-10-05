import sys, h5py, json, numpy as np
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
for fn in sys.argv[1:]:
    with h5py.File(fn, "r") as f:
        d = f["Data"]
        for k in list(d["SpectrumStream"])[:2]:
            g = d["SpectrumStream"][k]; s = g["Data"][:].ravel(); m = md(g)
            det = m["BinaryResult"]["Detector"]
            dv = [v for v in m["Detectors"].values() if det in v.get("DetectorName","")][0]
            disp = float(dv["Dispersion"]); off = float(dv["OffsetEnergy"])
            ev = s[s != 65535].astype(float)
            E = off + ev*disp   # eV, channel left edge (assumes offset is channel-0 energy)
            zero = np.abs(E) < 150
            print(fn.split("/")[-1][:42], det, "events", ev.size, "frac |E|<150eV: %.3f"%zero.mean(), "frac E>150eV: %.3f"%(E>150).mean(), "median E of non-zero events %.0f eV"%np.median(E[E>150]) if (E>150).any() else "")
