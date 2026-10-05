#!/usr/bin/env python3
"""tools/demo-edx/sim_edx.py — builds the simulated 4D-STEM + EDX dataset (WP2 lane S, ADR 055).

The 4D half is `tools/demo-dataset/make_demo.py` (imported, not copied): its reflection geometry, render() and
12 recipes, plus one more (precip_Q, see GUESSES) on a NON-square scan (64 x 48) so an axis swap shows. The EDX
half is `xray_model.py`: per recipe a known composition and a Poisson spectrum. Written as

  (a) a GMS-style multi-object .dm4 (thumbnail, survey, scan HAADF, "Diffraction SI", "EDS SI", one Experiment ID),
  (b) a HyperSpy-style .hspy pair (sim_EDS.hspy + sim_4D.hspy, linked only by the identical scan grid),
  (c) one small single-HDF5 variant for tests,
and `truth_edx.json` (recipes, compositions, expected counts, per-pixel recipe map, every guess).

Usage: sim_edx.py --reflections <reflections.json> --out-dir <dir> [--tiny] [--seed 42] [--name AlMgSi_4D_EDX]
Python: the repo's py4dstem env (numpy, scipy, h5py, Pillow; make_demo imports Pillow).
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "demo-dataset"))
import make_demo as md                                   # noqa: E402  the 4D recipes/geometry
import xray_model as xm                                  # noqa: E402
from xray_model import (MATRIX, BETA, Q_PHASE, PRECIP_VOLUME_FRACTION, PRECIP_THICKNESS_FACTOR,  # noqa: E402
                        mix, edx_spec, phase_of)
from dm4_writer import Group, image_object, write_dm4    # noqa: E402

VERSION = "1.0"
EXPERIMENT_ID = "Spectrum Imaging_10/05/2026_10:00:00 AM"

SCALE_DEFAULT = {"nx": 64, "ny": 48, "pitch_nm": 5.0, "det": 128, "channels": 4096, "dispersion_ev": 5.0,
                 "origin": 95.6, "survey": 1024, "thumb": (384, 288)}
SCALE_TINY = {"nx": 6, "ny": 4, "pitch_nm": 5.0, "det": 16, "channels": 512, "dispersion_ev": 20.0,
              "origin": 23.9, "survey": 64, "thumb": (16, 12)}
DWELL_S = 1.0e-3
DEAD_TIME = 0.05

GUESSES = [
    "G1 EDS object name 'EDS SI' and Experiment label 'EDS' (4d-edx-file-structure 1b/4a: GUESS)",
    "G2 EDS SI data type uint32 (DM code 11), memory order energy slowest: dims [nx,ny,nch], C array (nch,ny,nx)",
    "G3 channel count 4096 at 5 eV, energy axis origin 95.6 (E = (i-95.6)*0.005 keV, the 1D GMS Super-X file's pattern); the tiny fixture uses 512 ch at 20 eV, origin 23.9",
    "G4 EDS.Live time and EDS.Real time are per-SI scalars (real = dwell*nx*ny, live = real*(1-0.05)); no per-pixel live-time array",
    "G5 the EDS SI sits in the SAME .dm4 as the Diffraction SI under the SAME Experiment ID, as the LAST object",
    "G6 a scan-grid 'HAADF Image' (float32 [nx,ny]) is written in a 4D+EDS run; its pixel values are a model (thickness x Z^1.7 contrast), not derived from the 4D data",
    "G7 SI.Acquisition.Survey Image.{Spectrum Image Rect, Unique Image ID} appear on the EDS SI as on the other SI objects; rect stored as a float32 array (top,left,bottom,right), IDs as a uint32 array of 4",
    "G8 detector tags EDS.Detector Info.{Azimuthal angle 45, Elevation angle 18, Solid angle 0.7, Detector type SuperX} are copied from the Titan 1D file, not Talos Super-X values; the solid angle is written both at EDS.Solid angle and EDS.Detector Info.Solid angle",
    "G9 'Data Order Swapped' = 1 on the Diffraction SI (as in the owner files, meaning unknown) and ABSENT on the EDS SI",
    "G10 counts are binned SUMS per pixel (not averages)",
    "G11 Experiment keywords: group 1 holds 'Experiment ID', group 2 holds 'Label' (positions as seen in the owner files; the reader must not rely on them)",
    "G12 calibration Origin/Scale are float32 (as in the real 1D file); strings are ushort arrays",
    "G13 precip_Q has no reflection list in the app's crystal geometry: its 4D pattern reuses beta'' [001] rotated +45 deg on the Al [001] matrix; it is a labelled stand-in, not Q crystallography",
    "G14 EDX continuum, efficiency, Al K-edge step (15 %), Al Ka tail (1.5 %), Si internal fluorescence (0.4 % of counts above 1.839 keV), stray Cu K (0.05/px) and the per-element sensitivities are model choices (truth lists them)",
    "G15 hspy 4D file carries axis calibrations (real figshare data carries none); y axis scale is POSITIVE (real figshare EDS files have a negative y scale)",
    "G16 the single-HDF5 variant /eds /diffraction /survey /scan/rect is for tests only",
    "G17 thumbnail pixels are the HAADF image as grey BGRA; survey is a model ADF field around the scan rectangle",
]


# ---- recipes -------------------------------------------------------------------------------------------
# (name, kind, rows, cols, zone_key, extra_deg); kind endon / needle / Q
PRECIP_DEFAULT = [
    ("E1", "endon", [5, 7], [3, 5], "betaDoublePrime_010", 0),
    ("E2", "endon", [12, 14], [7, 9], "betaDoublePrime_010", 90),
    ("E3", "endon", [22, 24], [26, 28], "betaDoublePrime_010", 0),
    ("E4", "endon", [30, 32], [22, 24], "betaDoublePrime_010", 90),
    ("E5", "endon", [38, 40], [28, 30], "betaDoublePrime_010", 0),
    ("E6", "endon", [38, 40], [8, 10], "betaDoublePrime_010", 90),
    ("H1", "needle", [9, 10], [21, 32], "betaDoublePrime_001", 0),
    ("H2", "needle", [35, 36], [20, 31], "betaDoublePrime_001", 90),
    ("V1", "needle", [22, 33], [5, 6], "betaDoublePrime_001", 0),
    ("Q1", "Q", [15, 18], [27, 30], "Q", 0),
    ("Q2", "Q", [41, 43], [22, 24], "Q", 0),
]
PRECIP_CODE = {"endon": 1, "needle": 2, "Q": 3}


def build_grid(nx, ny, tiny):
    """recipe[ny][nx] names + grain label map + precipitate map + stripe mask."""
    recipe = np.empty((ny, nx), dtype=object)
    precip = np.zeros((ny, nx), dtype=np.int32)
    stripe = np.zeros((ny, nx), dtype=bool)
    grain = np.zeros((ny, nx), dtype=np.int32)
    if tiny:
        rows = [["A", "A", "A_strain", "mixAB", "B", "B"],
                ["A", "precip_endon_0", "precip_endon_90", "mixAB", "B", "mixBC"],
                ["A", "precip_needle_0", "precip_needle_90", "mixAC", "C", "C"],
                ["vacuum", "vacuum", "precip_Q", "mixAC", "C", "C"]]
        for y in range(ny):
            for x in range(nx):
                r = rows[y][x]
                recipe[y, x] = r
                grain[y, x] = {"A": 0, "A_strain": 0, "B": 1, "C": 2, "vacuum": 3}.get(r, 0)
                stripe[y, x] = r == "A_strain"
                if r.startswith("precip_"):
                    precip[y, x] = 3 if r == "precip_Q" else (1 if "endon" in r else 2)
        return recipe, grain, precip, stripe, []
    # the demo's layout scaled to 64 x 48 (grain A cols 0-33, boundary col 34, B above C at row 23)
    gb, brow = 34, 23
    vac_rows, vac_cols, stripe_cols = (44, 47), (0, 5), (13, 17)
    lookup = {}
    for name, kind, rr, cc, zkey, extra in PRECIP_DEFAULT:
        for y in range(rr[0], rr[1] + 1):
            for x in range(cc[0], cc[1] + 1):
                lookup[(y, x)] = (kind, extra)
    for y in range(ny):
        for x in range(nx):
            if vac_rows[0] <= y <= vac_rows[1] and vac_cols[0] <= x <= vac_cols[1]:
                recipe[y, x], grain[y, x] = "vacuum", 3
                continue
            g = "A" if x <= gb else ("B" if y <= brow else "C")
            grain[y, x] = {"A": 0, "B": 1, "C": 2}[g]
            if x == gb:
                recipe[y, x] = "mixAB" if y <= brow else "mixAC"
            elif x > gb and y == brow:
                recipe[y, x] = "mixBC"
            elif g != "A":
                recipe[y, x] = g
            elif stripe_cols[0] <= x <= stripe_cols[1]:
                stripe[y, x] = True
                recipe[y, x] = "A_strain"
            elif (y, x) in lookup:
                kind, extra = lookup[(y, x)]
                precip[y, x] = PRECIP_CODE[kind]
                recipe[y, x] = "precip_Q" if kind == "Q" else f"precip_{kind}_{extra}"
            else:
                recipe[y, x] = "A"
    return recipe, grain, precip, stripe, [
        {"name": n, "kind": k, "rows": r, "columns": c, "zone_axis_key": z, "extra_in_plane_deg": e,
         "code": PRECIP_CODE[k]} for n, k, r, c, z, e in PRECIP_DEFAULT]


def thickness_map(recipe, nx):
    ny = recipe.shape[0]
    t = np.ones((ny, nx))
    for y in range(ny):
        for x in range(nx):
            if recipe[y, x] != "vacuum":
                t[y, x] = 0.85 + 0.30 * (x + 0.5) / nx
    return t


def bin_pattern(p, f):
    n = p.shape[0] // f
    return p.reshape(n, f, n, f).sum(axis=(1, 3))


# ---- the 4D + EDX cubes ------------------------------------------------------------------------------
def build(args):
    sc = SCALE_TINY if args.tiny else SCALE_DEFAULT
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    with open(args.reflections) as f:
        reflections = json.load(f)
    recipe, grain, precip, stripe, precip_list = build_grid(nx, ny, args.tiny)
    names = sorted(set(recipe.ravel().tolist()))
    # 4D bases: make_demo's 12 + the Q stand-in
    bases = md.build_bases(reflections)
    bases["precip_Q"] = md.render(reflections, "Al_001", md.GRAINS["A"]["in_plane_deg"],
                                  precipitate=("betaDoublePrime_001", md.GRAINS["A"]["in_plane_deg"] + 45),
                                  extra_background=True)
    if det != md.DET:
        f = md.DET // det
        bases = {k: bin_pattern(v, f) for k, v in bases.items()}       # binning the mean == binning the draws
    rng4 = np.random.default_rng(args.seed)
    rng_x = np.random.default_rng(args.seed + 1)
    rng_h = np.random.default_rng(args.seed + 2)
    rng_s = np.random.default_rng(args.seed + 3)

    axis = xm.Axis(nch, sc["dispersion_ev"], sc["origin"])
    specs = {r: edx_spec(r) for r in bases}
    base_mean, stray_mean, rtruth = {}, {}, {}
    for r in bases:
        full, stray, tr = xm.base_spectrum(specs[r], axis)
        base_mean[r], stray_mean[r], rtruth[r] = full, stray, tr
    tmap = thickness_map(recipe, nx)

    cube4d = np.zeros((ny, nx, det, det), dtype=np.float32)
    eds = np.zeros((ny, nx, nch), dtype=np.uint32)
    haadf_mean = np.zeros((ny, nx))
    for y in range(ny):
        pats = np.stack([bases[r] for r in recipe[y]])
        cube4d[y] = np.clip(rng4.poisson(pats), 0, 65535).astype(np.float32)
        mean = np.stack([tmap[y, x] * base_mean[recipe[y, x]] + stray_mean[recipe[y, x]] for x in range(nx)])
        eds[y] = rng_x.poisson(mean).astype(np.uint32)
        for x in range(nx):
            n = rtruth[recipe[y, x]]["n_atoms"]
            haadf_mean[y, x] = 800.0 * tmap[y, x] * specs[recipe[y, x]].thickness_factor * sum(
                v * xm.ATOMIC_NUMBER[e] ** 1.7 for e, v in n.items() if e != "O") / (13 ** 1.7) + 5.0
    haadf = rng_h.poisson(haadf_mean).astype(np.float32)
    return dict(sc=sc, recipe=recipe, grain=grain, precip=precip, stripe=stripe, precip_list=precip_list,
                names=names, tmap=tmap, cube4d=cube4d, eds=eds, haadf=haadf, haadf_mean=haadf_mean,
                axis=axis, specs=specs, base_mean=base_mean, stray_mean=stray_mean, rtruth=rtruth, rng_s=rng_s,
                reflections=reflections)


# ---- survey and thumbnail ---------------------------------------------------------------------------------
def make_survey(b):
    if "survey_cache" in b:
        return b["survey_cache"]
    sc = b["sc"]
    n, nx, ny, pitch = sc["survey"], sc["nx"], sc["ny"], sc["pitch_nm"]
    survey_nm = 1.0                              # nm per survey pixel
    w, h = int(round(nx * pitch / survey_nm)), int(round(ny * pitch / survey_nm))
    left, top = (n - w) // 2 + 0, (n - h) // 2 + 0
    left, top = left - (5 if n > 100 else 3), top + (7 if n > 100 else 2)    # off-centre, de-symmetrised
    rect = (float(top), float(left), float(top + h), float(left + w))        # (top, left, bottom, right)
    yy, xx = np.mgrid[0:n, 0:n]
    field = 5000.0 * (1 + 0.04 * np.sin(xx / (n / 9.0)) * np.cos(yy / (n / 7.0)))
    inner = np.kron(b["haadf"] * (6.25 if n > 100 else 6.25), np.ones((int(pitch / survey_nm),) * 2))
    field[top:top + h, left:left + w] = inner
    surv = np.clip(b["rng_s"].poisson(field), 0, 65535).astype(np.uint16)
    b["survey_cache"] = (surv, rect, survey_nm)
    return b["survey_cache"]


def make_thumbnail(b):
    tw, th = b["sc"]["thumb"]
    ny, nx = b["haadf"].shape
    yi = (np.arange(th) * ny // th)
    xi = (np.arange(tw) * nx // tw)
    img = b["haadf"][np.ix_(yi, xi)]
    g = np.clip(255 * (img - img.min()) / max(float(np.ptp(img)), 1.0), 0, 255).astype(np.uint8)
    rgba = np.zeros((th, tw, 4), dtype=np.uint8)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = g
    rgba[..., 3] = 255
    return rgba.reshape(-1), tw, th


# ---- DM4 ------------------------------------------------------------------------------------------------------
def kw_group(meta: Group, label: str):
    k = meta.group("Experiment keywords")
    k.group("").string("Experiment ID", EXPERIMENT_ID)
    k.group("").string("Label", label)


def sim_group(tags: Group, truth_name: str, seed: int):
    g = tags.group("mac4DSTEM Simulation")
    g.string("Generator", f"tools/demo-edx/sim_edx.py {VERSION}")
    g.value("Seed", "i32", seed)
    g.string("Truth file", truth_name)
    g.string("Guesses", " | ".join(GUESSES))


def write_dm4_file(path, b, seed, truth_name):
    sc = b["sc"]
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    pitch = sc["pitch_nm"]
    survey, rect, survey_nm = make_survey(b)
    import hashlib
    b["hashes"] = {k: hashlib.sha256(np.ascontiguousarray(v).tobytes()).hexdigest() for k, v in
                   {"eds_ny_nx_nch_uint32": b["eds"], "diffraction_ny_nx_qy_qx_float32": b["cube4d"],
                    "haadf_ny_nx_float32": b["haadf"], "survey_uint16": survey}.items()}
    thumb, tw, th = make_thumbnail(b)
    survey_id = [1234567, 2345678, 3456789, 1357911]
    ids = {"thumb": [11, 12, 13, 14], "haadf": [21, 22, 23, 24], "diff": [31, 32, 33, 34], "eds": [41, 42, 43, 44]}
    q_nm = md.Q_PIXEL_INV_A * 10.0 * (md.DET // det)             # 1/nm per detector pixel
    q_origin = md.ORIGIN if det == md.DET else (md.ORIGIN + 0.5) / (md.DET // det) - 0.5
    real_s = DWELL_S * nx * ny

    def common(tags: Group, label, fmt, signal=None):
        meta = tags.group("Meta Data")
        meta.string("Format", fmt)
        if signal:
            meta.string("Signal", signal)
            meta.string("Acquisition Mode", "Parallel dispersive")
        kw_group(meta, label)
        mi = tags.group("Microscope Info")
        mi.value("Voltage", "f32", 200000.0); mi.string("Formatted Voltage", "200kV")
        mi.string("Illumination Mode", "STEM NANOPROBE"); mi.value("STEM Camera Length", "f32", 410.0)
        return meta

    def si_tags(tags: Group):
        s = tags.group("SI").group("Acquisition").group("Survey Image")
        s.array("Spectrum Image Rect", "f32", np.array(rect, dtype=np.float32))
        s.array("Unique Image ID", "u32", np.array(survey_id, dtype=np.uint32))
        tags.group("SI").group("Acquisition").value("Pixel time (s)", "f32", DWELL_S)

    root = Group()
    il = root.group("ImageList")

    # 0 thumbnail
    il.add(image_object(name=f"Image Of {os.path.basename(path)}", dtype="rgba", dims=[tw, th], data=thumb,
                        calibrations=[(0.0, 1.0, ""), (0.0, 1.0, "")], unique_id=ids["thumb"], image_tags=Group("ImageTags")))
    # 1 survey
    t = Group("ImageTags")
    common(t, "Survey", "Image")
    t.group("Survey Image").array("Unique Image ID", "u32", np.array(survey_id, dtype=np.uint32))
    il.add(image_object(name="ADF Image (SI Survey)", dtype="u16", dims=[survey.shape[1], survey.shape[0]],
                        data=survey, calibrations=[(0.0, survey_nm, "nm")] * 2, unique_id=survey_id, image_tags=t))
    # 2 scan-grid HAADF
    t = Group("ImageTags"); common(t, "Scan Signal", "Image"); si_tags(t); sim_group(t, truth_name, seed)
    il.add(image_object(name="HAADF Image", dtype="f32", dims=[nx, ny], data=b["haadf"],
                        calibrations=[(0.0, pitch, "nm")] * 2, unique_id=ids["haadf"], image_tags=t))
    # 3 Diffraction SI
    t = Group("ImageTags"); meta = common(t, "Diffraction", "Diffraction image")
    meta.value("Data Order Swapped", "i32", 1)
    si_tags(t); sim_group(t, truth_name, seed)
    il.add(image_object(name="Diffraction SI", dtype="f32", dims=[det, det, nx, ny], data=b["cube4d"].reshape(-1),
                        calibrations=[(q_origin, q_nm, "1/nm")] * 2 + [(0.0, pitch, "nm")] * 2,
                        unique_id=ids["diff"], image_tags=t))
    # 4 EDS SI: dims [nx, ny, nch], memory (nch, ny, nx)
    t = Group("ImageTags"); common(t, "EDS", "Spectrum image", signal="X-ray"); si_tags(t); sim_group(t, truth_name, seed)
    e = t.group("EDS")
    acq = e.group("Acquisition")
    acq.value("Channels", "i32", nch); acq.value("Dispersion (eV)", "f32", sc["dispersion_ev"])
    acq.value("Exposure (s)", "f32", real_s); acq.string("Date", "10/5/2026")
    acq.string("Start time", "10:00:00 AM"); acq.string("End time", "10:00:04 AM"); acq.string("Continuous Mode", "spectrum image")
    di = e.group("Detector Info")
    di.value("Azimuthal angle", "f32", 45.0); di.value("Elevation angle", "f32", 18.0)
    di.value("Solid angle", "f32", 0.7); di.string("Detector type", "SuperX"); di.value("Stage tilt", "f32", 0.0)
    di.value("Incidence angle", "f32", 90.0)
    e.value("Solid angle", "f32", 0.7)
    e.value("Live time", "f32", real_s * (1 - DEAD_TIME)); e.value("Real time", "f32", real_s)
    il.add(image_object(name="EDS SI", dtype="u32", dims=[nx, ny, nch],
                        data=np.ascontiguousarray(b["eds"].transpose(2, 0, 1)).reshape(-1),
                        calibrations=[(0.0, pitch, "nm"), (0.0, pitch, "nm"), (sc["origin"], sc["dispersion_ev"] / 1000.0, "keV")],
                        unique_id=ids["eds"], image_tags=t, brightness_units="Counts"))
    th_g = root.group("Thumbnails")
    th_g.group("").value("ImageIndex", "i32", 0)
    s = root.group("mac4DSTEM Simulation")
    s.string("Guesses", " | ".join(GUESSES)); s.string("Generator", f"tools/demo-edx/sim_edx.py {VERSION}")
    s.value("Seed", "i32", seed)
    size = write_dm4(path, root)
    return size, rect


# ---- hspy pair + single file --------------------------------------------------------------------------------
def _axis(group, i, name, size, scale, offset, units, navigate):
    g = group.create_group(f"axis-{i}")
    g.attrs.update({"name": name, "size": size, "scale": float(scale), "offset": float(offset),
                    "units": units, "navigate": bool(navigate)})


def _experiment(f, title, signal_type, binned, tem):
    f.attrs["file_format"] = "HyperSpy"
    f.attrs["file_format_version"] = "3.3"
    ex = f.require_group("Experiments").require_group("__unnamed__")
    ex.attrs["package"] = "hyperspy"
    ex.attrs["package_version"] = "mac4DSTEM simulation (hand-written, rsciio _hierarchical layout)"
    md_ = ex.require_group("metadata")
    gen = md_.require_group("General"); gen.attrs["title"] = title
    sig = md_.require_group("Signal"); sig.attrs["signal_type"] = signal_type; sig.attrs["binned"] = bool(binned)
    ex.require_group("original_metadata"); ex.require_group("learning_results"); ex.require_group("attributes")
    return ex, md_


def write_hspy_pair(out_dir, name, b, seed, sc_label):
    import h5py
    sc = b["sc"]
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    pitch = sc["pitch_nm"]
    p_eds = os.path.join(out_dir, f"{name}_EDS.hspy")
    with h5py.File(p_eds, "w") as f:
        ex, m = _experiment(f, "EDS SI (simulated)", "EDS_TEM", True, True)
        ex.create_dataset("data", data=b["eds"], chunks=(1, min(nx, 8), nch), compression="gzip", compression_opts=4)
        _axis(ex, 0, "y", ny, pitch, 0.0, "nm", True)
        _axis(ex, 1, "x", nx, pitch, 0.0, "nm", True)
        # real figshare/Zenodo EDS files use eV with offset 0; the 1D GMS pattern (offset -origin*scale) is kept here
        _axis(ex, 2, "Energy", nch, sc["dispersion_ev"], -sc["origin"] * sc["dispersion_ev"], "eV", False)
        tem = m.require_group("Acquisition_instrument").require_group("TEM")
        tem.attrs["beam_energy"] = 200.0; tem.attrs["acquisition_mode"] = "STEM"; tem.attrs["microscope"] = "simulated Talos F200X"
        eds = tem.require_group("Detector").require_group("EDS")
        eds.attrs["azimuth_angle"] = 45.0; eds.attrs["elevation_angle"] = 18.0
        eds.attrs["live_time"] = DWELL_S * nx * ny * (1 - DEAD_TIME); eds.attrs["real_time"] = DWELL_S * nx * ny
        eds.attrs["energy_resolution_MnKa"] = 130.0
        tem.require_group("Detector").require_group("Camera").attrs["exposure"] = DWELL_S
    p_4d = os.path.join(out_dir, f"{name}_4D.hspy")
    q_nm = md.Q_PIXEL_INV_A * 10.0 * (md.DET // det)
    q_origin = md.ORIGIN if det == md.DET else (md.ORIGIN + 0.5) / (md.DET // det) - 0.5
    with h5py.File(p_4d, "w") as f:
        ex, m = _experiment(f, "Diffraction SI (simulated)", "", False, False)
        ex.create_dataset("data", data=b["cube4d"].astype(np.int32), chunks=(1, min(3, nx), det, det),
                          compression="gzip", compression_opts=4)
        _axis(ex, 0, "y", ny, pitch, 0.0, "nm", True)
        _axis(ex, 1, "x", nx, pitch, 0.0, "nm", True)
        _axis(ex, 2, "ky", det, q_nm, -q_origin * q_nm, "1/nm", False)
        _axis(ex, 3, "kx", det, q_nm, -q_origin * q_nm, "1/nm", False)
    p_one = os.path.join(out_dir, f"{name}_single.h5")
    survey, rect, survey_nm = make_survey(b)
    with h5py.File(p_one, "w") as f:
        f.attrs["note"] = "mac4DSTEM simulation; single-file variant is a GUESS for tests only"
        f.create_dataset("eds", data=b["eds"], compression="gzip", compression_opts=4)
        f.create_dataset("diffraction", data=b["cube4d"].astype(np.int32), compression="gzip", compression_opts=4)
        f.create_dataset("survey", data=survey, compression="gzip", compression_opts=4)
        sg = f.create_group("scan")
        sg.create_dataset("rect", data=np.array(rect))          # (top, left, bottom, right) in survey pixels
        sg.attrs["pitch_nm"] = pitch; sg.attrs["survey_nm_per_pixel"] = survey_nm
    return [p_eds, p_4d, p_one]


# ---- truth ------------------------------------------------------------------------------------------------------
def write_truth(path, b, seed, sizes, dm4_name, rect):
    sc = b["sc"]
    nx, ny = sc["nx"], sc["ny"]
    axis = b["axis"]
    names = b["names"]
    recipes = {}
    for r in names:
        mask = b["recipe"] == r
        npx = int(mask.sum())
        tsum = float(b["tmap"][mask].sum())
        tr = b["rtruth"][r]
        lines = {}
        for ln, d in tr["lines"].items():
            lines[ln] = dict(d)
            lines[ln]["expected_total_counts"] = d["gaussian_counts"] * tsum
            lines[ln]["expected_total_counts_incl_tail"] = d["mean_counts"] * tsum
        stray = {k: v * npx for k, v in tr["stray_counts_per_pixel"].items()}
        spec = b["specs"][r]
        metals = {k: v for k, v in spec.n.items()}
        tot = sum(metals.values())
        recipes[r] = {
            "phase": phase_of(r),
            "composition_at_pct_metals": {k: 100 * v / tot for k, v in metals.items()} if tot > 0 else {},
            "oxide_O_per_metal_atom": 0.0 if spec.vacuum else spec.oxide,
            "n_atoms_per_unit_thickness": {k: float(v) for k, v in tr["n_atoms"].items()},
            "thickness_factor": spec.thickness_factor,
            "n_pixels": npx, "sum_of_pixel_thickness_map": tsum,
            "mean_total_counts_per_pixel_at_map_thickness": float(
                (b["tmap"][mask] * b["base_mean"][r].sum() + b["stray_mean"][r].sum()).mean()) if npx else 0.0,
            "lines": lines,
            "continuum_counts_per_pixel_at_t1": tr["continuum_counts_per_pixel"],
            "si_internal_Ka_counts_per_pixel_at_t1": tr["si_internal_Ka_counts"],
            "stray_expected_total_counts": stray,
            "realised_total_eds_counts": int(b["eds"][mask].sum()) if npx else 0,
            "realised_total_4d_counts": float(b["cube4d"][mask].sum(dtype=np.float64)) if npx else 0.0,
        }
    truth = {
        "generator": {"name": "tools/demo-edx/sim_edx.py", "version": VERSION, "seed": seed,
                      "poisson_streams": "4D seed, EDS seed+1, HAADF seed+2, survey seed+3 (numpy default_rng)"},
        "files": {"dm4": dm4_name, "sizes_bytes": sizes},
        "scan": {"nx": nx, "ny": ny, "pitch_nm": sc["pitch_nm"], "dwell_s": DWELL_S, "dead_time_fraction": DEAD_TIME,
                 "note": "NOT square: nx != ny so an axis swap shows"},
        "detector_4d": {"pixels": sc["det"], "q_nm_inv_per_pixel": md.Q_PIXEL_INV_A * 10 * (md.DET // sc["det"]),
                        "make_demo_dose": {"unit_bragg_amplitude": md.S, "direct_beam_peak": md.DIRECT_BEAM_PEAK}},
        "edx": {"channels": sc["channels"], "dispersion_eV": sc["dispersion_ev"], "origin_channel": sc["origin"],
                "energy_offset_keV": -sc["origin"] * sc["dispersion_ev"] / 1000.0,
                "energy_of_channel": "(i - origin) * dispersion  (centre of channel i)", "beam_keV": 200.0,
                "FWHM_MnKa_eV": 130.0, "dtype": "uint32",
                "fwhm_law": "eXSpy utils/eds/_xray_lines.py:138-175 sqrt(2.5*(E-5.8987 keV)*1000 + FWHM_MnKa^2) eV",
                "line_table": "eXSpy exspy/material/xray_lines.json (7185a4d): Al :119, Cu :716, Mg :1725, O :1968, Si :2953",
                "dose_note": "mean total counts per pixel ~35-60 (the owner's 4D regime 25-85); Poisson per pixel",
                "rect_survey_pixels_top_left_bottom_right": list(rect)},
        "model_parameters": {
            "sensitivity_counts_per_atom_unit_per_family": xm.SENSITIVITY,
            "true_cliff_lorimer_k_for_ratio_A_over_B": "C_A/C_B = k_AB * I_A/I_B with k_AB = s_B/s_A (family sensitivities above)",
            "G_counts": xm.G_COUNTS, "continuum_total_counts_per_pixel_for_sum_nZ_13": xm.CONTINUUM_TOTAL_Z13,
            "al_k_edge_step_fraction": xm.AL_STEP, "al_k_edge_keV": xm.AL_K_EDGE,
            "al_ka_tail": {"fraction": xm.AL_KA_TAIL_FRACTION, "lambda_keV": xm.AL_KA_TAIL_LAMBDA_KEV},
            "si_internal_fluorescence_fraction_of_counts_above_SiK_edge": xm.SI_INTERNAL_FRACTION,
            "stray_Cu_Ka_per_pixel": xm.STRAY_CU_KA_PER_PIXEL, "vacuum_continuum_per_pixel": xm.VACUUM_CONTINUUM_PER_PIXEL,
            "thickness_map": "0.85 + 0.30*(x+0.5)/nx for non-vacuum pixels, 1 for vacuum; precipitates carry thickness_factor 1.3",
            "precipitate_volume_fraction": PRECIP_VOLUME_FRACTION,
            "model_features_flagged": ["al_ka_tail", "si_internal_fluorescence", "al_k_edge_step", "stray_Cu_K",
                                       "oxide_O_0.02_per_metal_atom"],
        },
        "phases_at_pct": {"Al": {k: 100 * v for k, v in MATRIX.items()},
                          "beta_double_prime_Mg5Si6": {k: 100 * v for k, v in BETA.items()},
                          "Q_Al3Cu2Mg9Si7": {k: 100 * v for k, v in Q_PHASE.items()}},
        "recipes": recipes,
        "recipe_names_in_map_order": names,
        "recipe_map": [[names.index(r) for r in row] for row in b["recipe"].tolist()],
        "grain_label_map": b["grain"].tolist(), "grain_label_codes": {"0": "A", "1": "B", "2": "C", "3": "vacuum"},
        "precipitate_map": b["precip"].tolist(),
        "precipitate_codes": {"0": "none", "1": "beta'' end-on [010]", "2": "beta'' needle [001]", "3": "Q (stand-in pattern)"},
        "precipitates": b["precip_list"],
        "stripe_mask": b["stripe"].tolist(),
        "thickness_map": np.round(b["tmap"], 6).tolist(),
        "array_sha256_of_written_arrays_C_order": b["hashes"],
        "totals_written": {"eds_counts": int(b["eds"].sum()), "diffraction_counts": float(b["cube4d"].sum(dtype=np.float64))},
        "guesses": GUESSES,
    }
    with open(path, "w") as f:
        json.dump(truth, f, indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reflections", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--tiny", action="store_true")
    ap.add_argument("--name", default=None)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    name = args.name or ("demo-edx-tiny" if args.tiny else "AlMgSi_4D_EDX")
    print("building cubes ...", file=sys.stderr)
    b = build(args)
    truth_name = f"{name}.truth.json" if args.tiny else "truth_edx.json"
    dm4_path = os.path.join(args.out_dir, f"{name}.dm4")
    print("writing .dm4 ...", file=sys.stderr)
    size, rect = write_dm4_file(dm4_path, b, args.seed, truth_name)
    sizes = {os.path.basename(dm4_path): size}
    if not args.tiny:
        print("writing .hspy pair ...", file=sys.stderr)
        for p in write_hspy_pair(args.out_dir, name, b, args.seed, ""):
            sizes[os.path.basename(p)] = os.path.getsize(p)
    write_truth(os.path.join(args.out_dir, truth_name), b, args.seed, sizes, os.path.basename(dm4_path), rect)
    for k, v in sizes.items():
        print(f"  {k}: {v / 1048576:.2f} MiB", file=sys.stderr)


if __name__ == "__main__":
    main()
