#!/usr/bin/env python3
"""Truth for tools/velox-parity: rosettasciio's own reading of every public Velox file.

    truth.py <velox-parity data dir> <out dir>
    truth.py owner <velox .emd> <out dir>      (diagnostic: rsciio's totals on one big private file)

For each Velox EMD that holds a spectrum stream it runs rsciio's `file_reader` with
`sum_frames=True` (and `load_SI_image_stack=True`, so the image stacks are whole) and
writes, per case, the dense spectrum image as little-endian uint32, every scan image
summed over its frames as uint32, and the energy axis, plus `manifest.json`. A case
is the default frame range and, for a multi-frame file, frames [1, n) and [0, 1).
Each of the three zips ships `.npy` truth arrays beside some files; where one
exists, rsciio's output is checked against it first, so the comparator is validated
before the app is (docs/archive/ parity-comparator-validation).
"""
import json
import logging
import os
import sys

import h5py
import numpy as np

logging.disable(logging.CRITICAL)
from rsciio.emd import file_reader  # noqa: E402
import rsciio  # noqa: E402


def has_stream(path):
    with h5py.File(path) as f:
        if "Version" not in f or "Data" not in f:
            return False
        if json.loads(f["Version"][0]).get("format") != "Velox":
            return False
        d = f["Data"]
        return "SpectrumStream" in d and len(d["SpectrumStream"]) > 0


def frame_count(path):
    with h5py.File(path) as f:
        if "SpectrumImage" not in f["Data"]:
            return 0   # a stream with no SI settings: a single spectrum, not a spectrum image
        s = f["Data/SpectrumImage"]
        k = next(iter(s))
        return int(json.loads(s[k]["SpectrumImageSettings"][0])["endFramePosition"])


def read_case(path, **kw):
    dicts = file_reader(path, sum_frames=True, load_SI_image_stack=True, **kw)
    si = None
    images = []
    for d in dicts:
        names = [a["name"] for a in d["axes"]]
        if "X-ray energy" in names and d["data"].ndim >= 3:
            si = d
        elif names[-2:] == ["y", "x"] and np.asarray(d["data"]).dtype.kind in "iu":
            a = np.asarray(d["data"])
            if a.ndim == 3:
                a = a.astype(np.uint64).sum(axis=0)
            images.append((d["metadata"]["General"].get("title", ""), a))
    return si, images


def owner(path, out):
    """rsciio's dense cube of one file (needs RAM for the dense array), reduced to what the
    Swift side compares: per-pixel totals, per-channel totals, non-empty cells, grand total."""
    os.makedirs(out, exist_ok=True)
    (d,) = [x for x in file_reader(path, sum_frames=True, select_type="spectrum_image")]
    cube = np.asarray(d["data"])
    pixel = cube.sum(axis=2, dtype=np.uint64).ravel()
    channel = cube.sum(axis=(0, 1), dtype=np.uint64)
    pixel.astype("<u4").tofile(os.path.join(out, "owner.pixel.u32"))
    channel.astype("<u4").tofile(os.path.join(out, "owner.channel.u32"))
    info = {"shape": list(cube.shape), "dtype": str(cube.dtype), "total": int(cube.sum(dtype=np.uint64)),
            "nonzero": int(np.count_nonzero(cube)), "rsciio": rsciio.__version__}
    with open(os.path.join(out, "owner.json"), "w") as fh:
        json.dump(info, fh)
    print("truth owner:", info)


def main():
    if sys.argv[1] == "owner":
        return owner(sys.argv[2], sys.argv[3])
    data_dir, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    manifest = {"rsciio": rsciio.__version__, "files": []}
    npy_checks = []
    for root, _, names in sorted(os.walk(data_dir)):
        for name in sorted(names):
            if not name.endswith(".emd"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, data_dir)
            entry = {"file": rel, "stream": has_stream(path), "cases": []}
            manifest["files"].append(entry)
            if not entry["stream"]:
                continue
            nfr = frame_count(path)
            cases = [("default", {})]
            if nfr >= 2:
                cases += [("frames1-n", dict(first_frame=1, last_frame=nfr)), ("frames0-1", dict(first_frame=0, last_frame=1))]
            for label, kw in cases:
                try:
                    si, images = read_case(path, **kw)
                except Exception as e:  # recorded, never skipped silently
                    entry["cases"].append({"label": label, "error": repr(e)})
                    continue
                if si is None:
                    entry["cases"].append({"label": label, "error": "rsciio returned no spectrum image"})
                    continue
                tag = f"{len(manifest['files']) - 1}_{label}"
                cube = np.ascontiguousarray(np.asarray(si["data"]).astype("<u4"))
                cube.tofile(os.path.join(out, tag + ".si.u32"))
                ax = [a for a in si["axes"] if a["name"] == "X-ray energy"][0]
                case = {
                    "label": label, "first": kw.get("first_frame", 0), "last": kw.get("last_frame"),
                    "shape": list(cube.shape), "tag": tag,
                    "energy": {"offsetKeV": ax["offset"], "scaleKeV": ax["scale"], "units": ax.get("units")},
                    "images": [],
                }
                for i, (title, arr) in enumerate(images):
                    arr = np.ascontiguousarray(arr.astype("<u4"))
                    arr.tofile(os.path.join(out, f"{tag}.img{i}.u32"))
                    case["images"].append({"title": title, "shape": list(arr.shape), "file": f"{tag}.img{i}.u32"})
                entry["cases"].append(case)
                # rsciio against the .npy truth that ships beside the file (when there is one).
                if label == "default" and name == "fei_emd_si.emd":
                    npy_checks.append(("fei_emd_si.npy", np.array_equal(np.asarray(si["data"]), np.load(os.path.join(root, "fei_emd_si.npy")))))
            if name == "fei_emd_si.emd":
                si, _ = read_case(path, first_frame=2, last_frame=4)
                npy_checks.append(("fei_emd_si_frame.npy (frames 2-4)", np.array_equal(np.asarray(si["data"]), np.load(os.path.join(root, "fei_emd_si_frame.npy")))))
    manifest["npyChecks"] = [{"npy": n, "equal": bool(ok)} for n, ok in npy_checks]
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    for n, ok in npy_checks:
        print(f"truth: rsciio vs shipped {n}: {'equal' if ok else 'DIFFERENT'}")
    print(f"truth: rsciio {rsciio.__version__}, {sum(1 for e in manifest['files'] if e['stream'])} files with a stream, wrote {out}")


if __name__ == "__main__":
    main()
