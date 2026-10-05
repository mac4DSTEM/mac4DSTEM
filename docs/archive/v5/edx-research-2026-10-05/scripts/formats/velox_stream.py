import sys, h5py, json, numpy as np
fn = sys.argv[1]
def pj(ds, i=0):
    v = ds[i]
    if isinstance(v, bytes): v = v.decode()
    return json.loads(v)
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
with h5py.File(fn, "r") as f:
    print("Version:", f["Version"][0])
    d = f["Data"]
    img = d["Image"]
    for k in img:
        print("Image", k, img[k]["Data"].shape, img[k]["Data"].dtype, "FrameLookupTable", img[k]["FrameLookupTable"][:])
    if "SpectrumImage" in d:
        for k in d["SpectrumImage"]:
            g = d["SpectrumImage"][k]
            print("SpectrumImageSettings:", json.dumps(pj(g["SpectrumImageSettings"]), indent=1)[:1500])
            m = md(g)
            print("SI metadata top keys:", list(m.keys()))
    ss = d["SpectrumStream"]
    for k in ss:
        g = ss[k]
        acq = pj(g["AcquisitionSettings"])
        print("== stream", k, "AcquisitionSettings:", json.dumps(acq)[:1200])
        s = g["Data"][:].T[0]
        flt = g["FrameLocationTable"][:].ravel()
        print(" stream len", s.size, "dtype", s.dtype, "max non-marker", s[s!=65535].max() if (s!=65535).any() else None, "n markers", (s==65535).sum())
        print(" FrameLocationTable", flt)
        idx = np.nonzero(s == 65535)[0]
        print(" first idx", s[:20])
        m0 = md(g, 0)
        print(" metadata keys", list(m0.keys()))
        print(" BinaryResult", json.dumps(m0.get("BinaryResult"))[:800])
        br = m0["BinaryResult"]
        for dk, dv in m0["Detectors"].items():
            if br.get("Detector","~") in dv.get("DetectorName",""):
                print(" matched detector", dk, {kk: dv.get(kk) for kk in ["DetectorName","DetectorType","Dispersion","OffsetEnergy","ElevationAngle","AzimuthAngle","LiveTime","RealTime","CollectionAngle","Gain","Offset","InputCountRate","OutputCountRate","AnalyticalDwellTime","BeginEnergy","PulseProcessTime","ExcitationVoltage"]})
        if g["Metadata"].shape[1] > 1:
            m1 = md(g, 1)
            for dk, dv in m1["Detectors"].items():
                if br.get("Detector","~") in dv.get("DetectorName",""):
                    print(" col1 LiveTime/RealTime", dv.get("LiveTime"), dv.get("RealTime"))
        print(" Scan:", json.dumps(m0.get("Scan"))[:600])
        print(" Optics.AccelerationVoltage", m0.get("Optics",{}).get("AccelerationVoltage"))
