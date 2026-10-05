import sys, h5py, json, numpy as np
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
fn = sys.argv[1]
with h5py.File(fn, "r") as f:
    d = f["Data"]
    print("Data groups:", list(d.keys()))
    for k in d["Image"]:
        g = d["Image"][k]; m = md(g)
        print("Image", k[:8], g["Data"].shape, m["BinaryResult"].get("Detector"), "ScanSize", m.get("Scan",{}).get("ScanSize"), "ScanArea", m.get("Scan",{}).get("ScanArea"), "Acq start", m.get("Acquisition",{}).get("AcquisitionStartDatetime"))
    for k in d["SpectrumImage"]:
        g = d["SpectrumImage"][k]; m = md(g)
        print("SI", k[:8], "ScanSize", m.get("Scan",{}).get("ScanSize"), "ScanArea", m.get("Scan",{}).get("ScanArea"), "Acq start", m.get("Acquisition",{}).get("AcquisitionStartDatetime"), "BR", m["BinaryResult"])
    for k in d["SpectrumStream"]:
        g = d["SpectrumStream"][k]; m = md(g)
        s = g["Data"][:].ravel()
        print("Stream", k[:8], m["BinaryResult"].get("Detector"), "ScanSize", m.get("Scan",{}).get("ScanSize"), "ScanArea", m.get("Scan",{}).get("ScanArea"), "DwellTime", m.get("Scan",{}).get("DwellTime"), "Acq start", m.get("Acquisition",{}).get("AcquisitionStartDatetime"), "first", s[:3], "markers", (s==65535).sum())
    if "EelsSpectrumImage" in d:
        for k in d["EelsSpectrumImage"]:
            print("EELS SI", k[:8], d["EelsSpectrumImage"][k]["Data"].shape)
