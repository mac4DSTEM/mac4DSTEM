import sys, h5py, json, numpy as np
def md(grp, col=0):
    a = grp["Metadata"][:, col]
    return json.loads(a.tobytes().decode("utf-8").rstrip("\x00"))
for fn in sys.argv[1:]:
    with h5py.File(fn, "r") as f:
        d = f["Data"]
        imgshape = [d["Image"][k]["Data"].shape for k in d["Image"]]
        for k in list(d["SpectrumStream"])[:1]:
            g = d["SpectrumStream"][k]; s = g["Data"][:].ravel(); m = md(g)
            sc = m.get("Scan", {})
            sa = sc.get("ScanArea"); ss = sc.get("ScanSize")
            w = (float(sa["right"])-float(sa["left"]))*float(ss["width"]); h = (float(sa["bottom"])-float(sa["top"]))*float(ss["height"])
            idx = np.nonzero(s==65535)[0]
            # run-length of leading markers, events per pixel stats
            gaps = np.diff(np.concatenate([[-1], idx, [s.size]])) - 1
            print(fn.split("/")[-1][:45], "img", imgshape, "ScanArea->", (round(h,3), round(w,3)), "s[0:5]", s[:5], "s[-3:]", s[-3:], "markers", idx.size, "evts/px mean", round(gaps.mean(),2), "empty px", int((gaps==0).sum()), "trailing events after last marker", int(s.size-1-idx[-1]))
