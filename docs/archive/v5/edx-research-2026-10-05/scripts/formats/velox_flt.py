import sys, h5py, json, numpy as np
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
for fn in sys.argv[1:]:
    print("=====", fn.split("/")[-1])
    with h5py.File(fn, "r") as f:
        try: print(" Version", json.loads(f["Version"][0])["version"])
        except Exception as e: print(" version?", e)
        d = f["Data"]
        if "Image" in d:
            for k in d["Image"]:
                print(" Image", d["Image"][k]["Data"].shape, d["Image"][k]["Data"].dtype)
        if "SpectrumImage" in d:
            for k in d["SpectrumImage"]:
                g = d["SpectrumImage"][k]
                print(" SpectrumImage keys", list(g.keys()), "Data", g["Data"].shape, g["Data"].dtype)
                if "SpectrumImageSettings" in g: print(" SISettings", g["SpectrumImageSettings"][0])
        if "SpectrumStream" not in d: print(" no SpectrumStream"); continue
        for k in d["SpectrumStream"]:
            g = d["SpectrumStream"][k]
            s = g["Data"][:].ravel()
            acq = json.loads(g["AcquisitionSettings"][0])
            ncol = g["Metadata"].shape[1]
            m0 = md(g, 0); mL = md(g, ncol-1)
            det = m0["BinaryResult"].get("Detector")
            lt0 = rt0 = ltL = rtL = None
            for dv in m0["Detectors"].values():
                if det and det in dv.get("DetectorName",""): lt0, rt0 = dv.get("LiveTime"), dv.get("RealTime"); disp, off = dv.get("Dispersion"), dv.get("OffsetEnergy")
            for dv in mL["Detectors"].values():
                if det and det in dv.get("DetectorName",""): ltL, rtL = dv.get("LiveTime"), dv.get("RealTime")
            idx = np.nonzero(s == 65535)[0]
            flt = g["FrameLocationTable"][:].ravel() if "FrameLocationTable" in g else None
            print(f" stream {det}: len={s.size} dtype={s.dtype} markers={idx.size} lastval={s[-1]} acq={acq} metaCols={ncol} LT col0={lt0} colLast={ltL} RT col0={rt0} colLast={rtL} disp={disp} off={off}")
            print("  FLT", flt[:12] if flt is not None else None, "len", None if flt is None else flt.size)
            if flt is not None and flt.size > 1:
                # pixels per frame implied
                img = [d["Image"][k2]["Data"].shape for k2 in d["Image"]][0]
                npix = img[0]*img[1]
                cand = [idx[npix*j-1]+1 for j in range(1, min(flt.size, idx.size//npix+1))]
                print("  index after (npix*j)-th marker:", cand[:12])
