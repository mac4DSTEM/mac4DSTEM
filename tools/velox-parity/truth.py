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

Every Velox file, stream or not, also gets its image stacks written: each signal rsciio
returns for the `Data/Image` groups (`select_type="images"`, `load_SI_image_stack=True`),
as little-endian float32 frames (frame, y, x) with the axes' scale, offset and units and
the `BinaryResult` fields they come from. See `image_stacks`.
"""
import json
import logging
import os
import sys

import h5py
import numpy as np

logging.disable(logging.CRITICAL)
from rsciio.emd import file_reader  # noqa: E402
from rsciio.utils._units import convert_units  # noqa: E402
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


def image_stacks(path, out, k):
    """Everything the Swift side compares about the `Data/Image` groups of one file.

    rsciio reads the groups in `h5py`'s iteration order (`_get_keys_from_group` is `list(group.keys())`),
    which is name order; the Swift reader lists them in the same order, so the stacks are keyed by position
    and carry their group name. Each stack's frames are checked here against `h5py`'s own read of the group
    (so position i is the group named by `ids[i]`, whatever rsciio does with it), then written as float32.
    Returns the manifest fields `imageOnly`, `imageStacks` and, when the comparison cannot be made, `imageError`
    (a file or group rsciio cannot return as an image is recorded, never skipped silently)."""
    with h5py.File(path) as f:
        data = f["Data"]
        ids = list(data["Image"].keys()) if "Image" in data else []
        # What `VeloxEMDReader.isVeloxEMD` asks: a spectrum stream or a spectrum image is there.
        found = {"imageOnly": "SpectrumStream" not in data and "SpectrumImage" not in data and bool(ids), "imageStacks": []}
        if ids != sorted(ids):
            found["imageError"] = f"Data/Image iterates {ids}, not in name order"
            return found
        if not ids:
            return found
        try:
            signals = file_reader(path, select_type="images", load_SI_image_stack=True)
        except Exception as e:
            found["imageError"] = repr(e)
            return found
        if len(signals) != len(ids):
            found["imageError"] = f"rsciio returned {len(signals)} image signals for {len(ids)} groups"
            return found
        for i, (gid, sig) in enumerate(zip(ids, signals)):
            arr = np.asarray(sig["data"])
            names = [a["name"] for a in sig["axes"]]
            if arr.ndim not in (2, 3) or names[-2:] != ["y", "x"] or (arr.ndim == 3) != (names[0] == "Time"):
                found["imageError"] = f"{gid}: axes {names} for data of shape {arr.shape}"
                return found
            stack = arr if arr.ndim == 3 else arr[np.newaxis]          # (frame, y, x); rsciio squeezes a one-frame stack
            raw = data["Image"][gid]["Data"]                              # (y, x, frame) as stored
            compound = raw.dtype.names is not None                        # Velox FFT and DPC images: rsciio returns complex
            if not compound and not np.array_equal(np.moveaxis(raw[()], 2, 0), stack):
                found["imageError"] = f"{gid}: rsciio's frames are not h5py's frames of the same group"
                return found
            br = sig["original_metadata"].get("BinaryResult", {})
            ax = {a["name"]: a for a in sig["axes"]}
            stored = lambda key: key in br
            entry = {
                "id": gid, "dtype": str(stack.dtype), "shape": list(stack.shape), "file": None,
                "axes": [{"name": a["name"], "scale": float(a["scale"]), "offset": float(a["offset"]), "units": a["units"], "size": a["size"]}
                         for a in sig["axes"]],
                "detector": br.get("Detector", ""),
                "pixelSizeStored": stored("PixelSize"), "offsetStored": stored("Offset"),
                "unitX": br.get("PixelUnitX"), "unitY": br.get("PixelUnitY"),
            }
            if stored("PixelSize"):
                # rsciio's axes, back in metres by its own unit registry (it converts x with PixelUnitX and compacts the unit).
                entry["metres"] = {
                    "scaleX": convert_units(float(ax["x"]["scale"]), ax["x"]["units"], "m"),
                    "scaleY": convert_units(float(ax["y"]["scale"]), ax["y"]["units"], "m"),
                    "offsetX": convert_units(float(ax["x"]["offset"]), ax["x"]["units"], "m"),
                    "offsetY": convert_units(float(ax["y"]["offset"]), ax["y"]["units"], "m"),
                }
            if stack.dtype.kind in "iuf":
                f32 = np.ascontiguousarray(stack.astype("<f4"))
                f32.tofile(os.path.join(out, f"{k}.stack{i}.f32"))
                entry["file"] = f"{k}.stack{i}.f32"
                entry["floatExact"] = bool(np.array_equal(f32.astype(np.float64), stack.astype(np.float64), equal_nan=True))
            found["imageStacks"].append(entry)
    return found


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
            entry.update(image_stacks(path, out, len(manifest["files"]) - 1))
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
    print(f"truth: rsciio {rsciio.__version__}, {sum(1 for e in manifest['files'] if e['stream'])} files with a stream, "
          f"{sum(len(e['imageStacks']) for e in manifest['files'])} image stacks, wrote {out}")


if __name__ == "__main__":
    main()
