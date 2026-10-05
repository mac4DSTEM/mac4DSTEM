#!/usr/bin/env python3
"""Writes the tiny synthetic Velox EMDs that mac4DSTEMTests/VeloxEMDReaderTests.swift embeds as base64
(so the unit tests need no References data). Prints the raw-deflate base64 (what Foundation's `.zlib`
decompression expects):

    make-tiny-fixture.py <out.emd>               the main file
    make-tiny-fixture.py --bare <out.emd>        no FrameLocationTable, no SpectrumImage group, one stream
                                                 stopped mid-frame (the ceil-of-markers path)
    make-tiny-fixture.py --image-only <out.emd>  a Velox image file with no stream
    make-tiny-fixture.py --no-scan-area <out.emd>   the main file without ScanArea (grid from the last image)
    make-tiny-fixture.py --wrong-height <out.emd>   the main file with ScanSize height 4 (a grid the stream cannot fill)
    make-tiny-fixture.py --bare-huge-grid <out.emd> the bare file with ScanSize height 6000 (a corrupt grid, no table to catch it)
    make-tiny-fixture.py --no-last-marker <out.emd> the main file, every stream lacking its final pixel marker (EELS_EDS-like)
    make-tiny-fixture.py --multi-version <out.emd>  a Version dataset of 3 elements (a guard test)

Main file: a NON-SQUARE 3-row x 2-column spectrum image (ScanSize 4 x 6, ScanArea .25-.75 x 0-.5), 8 channels,
2 frames, two detector streams (SuperXG21, SuperXG22) with a FrameLocationTable, a (3, 2, 2) HAADF stack, and
Super-X segments with DIFFERENT elevations and a different dispersion (G22: 20 eV/channel, the rest 10), so a
swapped axis, a swapped segment or a lost calibration cannot pass. ScanTransformation is written the way Velox
writes it: FLAT dotted keys under CustomProperties."""
import base64, json, sys, zlib
import h5py
import numpy as np

M = 65535
ROWS = 4096
NY, NX = 3, 2
# per frame, per pixel: the channels detected. Pixels are row-major (p = y * 2 + x).
A = [[[1, 1], [], [2], [], [], [7]], [[1], [3], [], [], [], [0]]]
B = [[[], [3], [], [4], [], [7]], [[], [], [5], [], [], []]]


def stream(frames, stop_after=None):
    out, n = [], 0
    for fr in frames:
        for px in fr:
            if stop_after is not None and n == stop_after:
                return out
            out += px + [M]
            n += 1
    return out


VARIANT = {"scan_area": True, "height": "6"}


def meta(detector, frames):
    dets = {"Detector-0": {"DetectorName": "HAADF", "DetectorType": "ScanningDetector", "Enabled": "true"}}
    for i, (az, el, disp) in enumerate(((45, 0.31415927, 10), (135, 0.5235988, 20), (225, 0.4, 10), (315, 0.6, 10))):
        dets[f"Detector-{i + 1}"] = {
            "DetectorName": f"SuperXG2{i + 1}", "DetectorType": "AnalyticalDetector", "Inserted": "true",
            "Enabled": "false" if i == 3 else "true", "ElevationAngle": repr(el),
            "AzimuthAngle": repr(float(np.radians(az))), "CollectionAngle": "0.225", "Dispersion": str(disp),
            "OffsetEnergy": "-250", "RealTime": "0.5", "LiveTime": "0.4"}
    m = {"Detectors": dets,
         "BinaryResult": {"Detector": detector, "DetectorIndex": "8", "PixelSize": {"width": "1e-9", "height": "1e-9"},
                          "PixelUnitX": "m", "Offset": {"x": "0", "y": "0"}},
         "Scan": {"ScanSize": {"width": "4", "height": VARIANT["height"]}, "DwellTime": "1e-3", "FrameTime": "0.006",
                  "ScanArea": {"left": "0.25", "top": "0", "right": "0.75", "bottom": "0.5"}, "ScanRotation": "-0.5"},
         "Optics": {"AccelerationVoltage": "200000", "ScreenCurrent": "1.5e-9"},
         "Stage": {"AlphaTilt": "-0.2945", "BetaTilt": "0.01", "HolderType": "FEI Double Tilt",
                   "Position": {"x": "1e-5", "y": "2e-5", "z": "3e-5"}},
         "Instrument": {"InstrumentModel": "Talos"}, "Acquisition": {"AcquisitionStartDatetime": {"DateTime": "1776689766"}}}
    if not VARIANT["scan_area"]:
        del m["Scan"]["ScanArea"]
    cols = []
    for f in range(frames):
        mm = json.loads(json.dumps(m))
        mm["CustomProperties"] = {f"Scan.ScanTransformation.{k}": {"type": "double", "value": str(v)} for k, v in
                                  dict(A11=1, A12=0, A13=0.001 * f, A21=0, A22=1, A23=-0.002 * f).items()}
        b = json.dumps(mm).encode()
        assert len(b) < ROWS
        cols.append(np.frombuffer(b.ljust(ROWS, b"\0"), dtype=np.uint8))
    return np.stack(cols, axis=1)


vl = h5py.string_dtype()


def emit(path):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    print(base64.b64encode(c.compress(open(path, "rb").read()) + c.flush()).decode())


def version(f):
    f.create_dataset("Version", data=[json.dumps({"version": "11", "format": "Velox"})], dtype=vl)


def image(d):
    g = d.create_group("Image/img0")
    stack = np.stack([np.arange(1, 7, dtype=np.uint16).reshape(NY, NX), 10 * np.arange(1, 7, dtype=np.uint16).reshape(NY, NX)], axis=2)
    g.create_dataset("Data", data=stack)   # (y, x, frame)
    g.create_dataset("Metadata", data=meta("HAADF", 2))


mode, path = (sys.argv[1], sys.argv[2]) if sys.argv[1].startswith("--") else ("--main", sys.argv[1])
if mode == "--no-scan-area":      # the last-image grid fallback
    VARIANT["scan_area"] = False
if mode == "--bare-huge-grid":    # the bare file with ScanSize height 6000: more pixels per frame than the stream has pixel ends
    VARIANT["height"] = "6000"
    mode = "--bare"
NO_LAST_MARKER = mode == "--no-last-marker"   # every stream ends without its final pixel marker
if NO_LAST_MARKER:
    mode = "--main"
if mode == "--wrong-height":      # ScanSize height 4 instead of 6: a grid the stream cannot fill
    VARIANT["height"] = "4"
with h5py.File(path, "w") as f:
    if mode == "--multi-version":
        # A Version dataset with SEVERAL elements: any other HDF5 file may have one; reading it into one pointer overflows.
        f.create_dataset("Version", data=[json.dumps({"version": "11", "format": "Velox"})] * 3, dtype=vl)
        f.create_group("Data/SpectrumStream")
    else:
        version(f)
    d = f.create_group("Data") if mode != "--multi-version" else None
    if mode == "--multi-version":
        pass
    elif mode == "--image-only":
        d.create_group("Image/img0").create_dataset("Data", data=np.zeros((2, 2, 1), dtype=np.uint16))
    elif mode == "--bare":
        g = d.create_group("SpectrumStream/aaaa")
        g.create_dataset("AcquisitionSettings", data=[json.dumps({"bincount": "8", "StreamEncoding": "uint16"})], dtype=vl)
        g.create_dataset("Data", data=np.array(stream(A, stop_after=8), dtype=np.uint16).reshape(-1, 1))
        g.create_dataset("Metadata", data=meta("SuperXG21", 2))
        image(d)
    else:
        for name, fr, det in (("aaaa", A, "SuperXG21"), ("bbbb", B, "SuperXG22")):
            g = d.create_group(f"SpectrumStream/{name}")
            g.create_dataset("AcquisitionSettings", data=[json.dumps({"bincount": "8", "StreamEncoding": "uint16"})], dtype=vl)
            s = stream(fr)
            if NO_LAST_MARKER:
                s = s[:-1]
            g.create_dataset("Data", data=np.array(s, dtype=np.uint16).reshape(-1, 1))
            idx = [i for i, v in enumerate(s) if v == M]
            g.create_dataset("FrameLocationTable", data=np.array([[0], [idx[NY * NX - 1] + 1]], dtype=np.uint64))
            g.create_dataset("Metadata", data=meta(det, 2))
        g = d.create_group("SpectrumImage/si00")
        g.create_dataset("SpectrumImageSettings", data=[json.dumps({"startFramePosition": "1", "endFramePosition": "2"})], dtype=vl)
        image(d)
emit(path)
