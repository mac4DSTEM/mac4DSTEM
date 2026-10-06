#!/usr/bin/env python3
"""tools/demo-edx/sim_edx.py — builds the simulated 4D-STEM + EDX dataset (WP2 lane S + S2, ADR 055). v2.

The 4D half is `tools/demo-dataset/make_demo.py` (imported, not copied): its reflection geometry, render() and 12 recipes,
plus one more (precip_Q, see GUESSES) on a NON-square scan (64 x 48). The EDX half is `forward.py` (physical model:
per-segment numerical path-integral absorption from NIST FFAST MACs, efficiency, live time, sum/escape peaks, Ga damage) on the
recipes' compositions. Written as

  (a) a GMS-style multi-object .dm4 (thumbnail, survey, scan HAADF, "Diffraction SI", "EDS SI", one Experiment ID),
  (b) a HyperSpy-style .hspy pair (sim_EDS.hspy + sim_4D.hspy, linked only by the identical scan grid), + a single-HDF5 variant,
  (c) `truth_edx.json` (+ `truth_edx_arrays.npz` for the per-pixel arrays) with every guess,
  (d) --ladder: an EDS-only dose ladder dataset {0.3,1,3,10,30,100} counts/px (+ truth),
  (e) --regmismatch: a .dm4 whose EDS grid is binned 2x, shifted (3,-2) and mirrored in x relative to the 4D grid (+ truth with
      the planted 2x3 affine and the per-phase masks on both grids).

Usage: sim_edx.py --reflections <reflections.json> --out-dir <dir> [--tiny] [--seed 42] [--name N] [--ladder] [--regmismatch]
       [--mac <FFastMAC.csv>]   (default: mac4DSTEM/Resources/Spectroscopy/FFastMAC.csv, else $MAC_CSV)
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
import forward as fw                                     # noqa: E402
from xray_model import (MATRIX, BETA, Q_PHASE, PRECIP_VOLUME_FRACTION, PRECIP_THICKNESS_FACTOR,  # noqa: E402
                        mix, edx_spec, phase_of)
from dm4_writer import Group, image_object, write_dm4    # noqa: E402

VERSION = "2.0"
EXPERIMENT_ID = "Spectrum Imaging_10/05/2026_10:00:00 AM"
SCALE_DEFAULT = {"nx": 64, "ny": 48, "pitch_nm": 5.0, "det": 128, "channels": 4096, "dispersion_ev": 5.0,
                 "origin": 95.6, "survey": 1024, "thumb": (384, 288), "perturb": True, "dead_rows": [(0, 4, 0.30), (44, 48, 0.60)]}
SCALE_TINY = {"nx": 6, "ny": 4, "pitch_nm": 5.0, "det": 16, "channels": 512, "dispersion_ev": 20.0,
              "origin": 23.9, "survey": 64, "thumb": (16, 12), "perturb": True, "dead_rows": [(0, 2, 0.30)]}
DWELL_S = 1.0e-3
DEAD_BASE = 0.05
AXIS_PERTURB = {"offset_eV": -10.0, "gain": 0.002, "relation": "E_file = (1 + gain) * E_true + offset"}
LADDER_DOSES = [0.3, 1.0, 3.0, 10.0, 30.0, 100.0]
DEFAULT_MAC = os.path.join(HERE, "..", "..", "mac4DSTEM", "Resources", "Spectroscopy", "FFastMAC.csv")

GUESSES = [
    "G1 EDS object name 'EDS SI' and Experiment label 'EDS' (4d-edx-file-structure 1b/4a: GUESS)",
    "G2 EDS SI data type uint32 (DM code 11) and memory order energy slowest, dims [nx,ny,nch], C array (nch,ny,nx): the order is INFERRED from the owner's EELS SI 134 (float32, dims fastest-first [206,337,2048], energy slowest) and the way rsciio reads it; the dtype is a guess (single spectra are uint32)",
    "G3 channel count 4096 at 5 eV, energy axis origin 95.6 (E = (i-95.6)*0.005 keV, the 1D GMS Super-X file's pattern); the tiny fixture uses 512 ch at 20 eV, origin 23.9. In the DEFAULT file the axis is deliberately PERTURBED (-10 eV offset, +0.2 % gain, see truth edx.axis_planted)",
    "G4 EDS.Live time and EDS.Real time are per-SI scalars (real = dwell*nx*ny, live = real*mean live fraction)",
    "G5 the EDS SI sits in the SAME .dm4 as the Diffraction SI under the SAME Experiment ID, as the LAST object. The object ORDER is load-bearing for DM4Reader: it opens the FIRST Data array with more than 2 non-singleton dims, so the Diffraction SI must precede the EDS SI",
    "G6 a scan-grid 'HAADF Image' (float32 [nx,ny]) is written in a 4D+EDS run; its pixel values are a model (areal atoms x Z^1.7 contrast), not derived from the 4D data",
    # G7 (rect / Unique Image ID storage form) RESOLVED by measurement on the owner's 036: type-15 structs of four int64 (element code 11), values (14, 222, 515, 569); written that way
    "G8 EDS.Detector Info carries the PLANTED physics: Azimuthal angle 45 (segment 1 of four; all four, with their relative solid-angle weights, are under mac4DSTEM Simulation.Segments), Elevation angle 22, Stage tilt -16.87, Solid angle 0.7 (written at EDS.Solid angle and EDS.Detector Info.Solid angle), Detector type SuperX; the Titan 1D file's 45/18/0.7 were the round-1 values. The real Talos Super-X geometry is unknown",
    "G9 'Data Order Swapped' = 1 on the Diffraction SI (as in the owner files, meaning unknown) and ABSENT on the EDS SI",
    "G10 counts are binned SUMS per pixel (not averages)",
    "G11 Experiment keywords: group 1 holds 'Experiment ID', group 2 holds 'Label' (positions as seen in the owner files; the reader must not rely on them)",
    "G12 calibration Origin/Scale are float32 (as in the real 1D file); strings are ushort arrays",
    "G13 precip_Q has no reflection list in the app's crystal geometry: its 4D pattern reuses beta'' [001] rotated +45 deg on the Al [001] matrix; it is a labelled stand-in, not Q crystallography",
    "G14 continuum, efficiency eps(E), absorption (NIST FFAST MACs, depth-weighted per-segment path integral), Al Ka tail (1.5 %), Si internal fluorescence (0.4 % of ALL counts above 1.839 keV incl. stray Cu K), stray Cu K, sum peaks, escape peaks, Ga L damage, live-time ladder and the per-element sensitivities are model choices (truth lists them)",
    "G15 hspy 4D file carries axis calibrations (real figshare data carries none); y axis scale is POSITIVE (real figshare EDS files have a negative y scale)",
    "G16 the single-HDF5 variant /eds /diffraction /survey /scan/rect is for tests only",
    "G17 thumbnail pixels are the HAADF image as grey BGRA; survey is a model ADF field around the scan rectangle",
    "G18 a per-pixel live-time map is written as ImageTags EDS.Live time map (float32 array ny*nx, C order); no real GMS file is known to carry one",
    "G19 the file's energy axis is the generator's axis perturbed by E_file = 1.002 E_true - 10 eV (default dataset only)",
]


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
    """Relative thickness wedge 0.85..1.15 (1 for vacuum); physical thickness is `thickness_nm`."""
    ny = recipe.shape[0]
    t = np.ones((ny, nx))
    for y in range(ny):
        for x in range(nx):
            if recipe[y, x] != "vacuum":
                t[y, x] = fw.WEDGE[0] + fw.WEDGE[1] * (x + 0.5) / nx
    return t


def bin_pattern(p, f):
    n = p.shape[0] // f
    return p.reshape(n, f, n, f).sum(axis=(1, 3))


# ---- the 4D + EDX cubes ------------------------------------------------------------------------------
def pixel_params(recipe, nx, dead_rows, f):
    """Flat per-pixel parameters (row-major y, x): t_nm, rho, live fraction, Ga atoms/nm^2."""
    ny = recipe.shape[0]
    wedge = thickness_map(recipe, nx)
    t = np.zeros((ny, nx)); rho = np.zeros((ny, nx)); lam = np.full((ny, nx), 1.0 - DEAD_BASE); ga = np.zeros((ny, nx))
    v = PRECIP_VOLUME_FRACTION
    n_ga0 = fw.GA_LA_EDGE_COUNTS / (f.gp * xm.SENSITIVITY["Ga_L"] * float(xm.detector_efficiency(np.array([1.098]))[0]))
    for y in range(ny):
        for x in range(nx):
            r = recipe[y, x]
            if r == "vacuum":
                continue
            prec = r.startswith("precip_")
            t[y, x] = fw.THICKNESS_BASE_NM * wedge[y, x] * (fw.PRECIP_T if prec else 1.0)
            ph = "Q" if r == "precip_Q" else "beta"
            rho[y, x] = (1 - v) * fw.PHASE_DENSITY["Al"] + v * fw.PHASE_DENSITY[ph] if prec else fw.PHASE_DENSITY["Al"]
            if x >= nx - fw.GA_COLUMNS:
                ga[y, x] = n_ga0 * math.exp(-(nx - 1 - x) / fw.GA_LAMBDA_PX)
    for r0, r1, dead in dead_rows:
        lam[r0:r1, :] = 1.0 - dead
    return t, rho, lam, ga


def axis_pair(sc):
    """(generator axis, file axis (scale_eV, origin)). The file axis is perturbed in the default dataset."""
    gen = xm.Axis(sc["channels"], sc["dispersion_ev"], sc["origin"])
    if not sc["perturb"]:
        return gen, (sc["dispersion_ev"], sc["origin"])
    d_f = sc["dispersion_ev"] * (1 + AXIS_PERTURB["gain"])
    origin_f = sc["origin"] - AXIS_PERTURB["offset_eV"] / d_f
    return gen, (d_f, origin_f)


def build(args, sc_override=None):
    sc = dict(SCALE_TINY if args.tiny else SCALE_DEFAULT)
    if sc_override:
        sc.update(sc_override)
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    with open(args.reflections) as fh:
        reflections = json.load(fh)
    recipe, grain, precip, stripe, precip_list = build_grid(nx, ny, args.tiny)
    names = sorted(set(recipe.ravel().tolist()))
    bases = md.build_bases(reflections)
    bases["precip_Q"] = md.render(reflections, "Al_001", md.GRAINS["A"]["in_plane_deg"],
                                  precipitate=("betaDoublePrime_001", md.GRAINS["A"]["in_plane_deg"] + 45),
                                  extra_background=True)
    if det != md.DET:
        fct = md.DET // det
        bases = {k: bin_pattern(v, fct) for k, v in bases.items()}       # binning the mean == binning the draws
    rng4 = np.random.default_rng(args.seed)
    rng_x = np.random.default_rng(args.seed + 1)
    rng_h = np.random.default_rng(args.seed + 2)
    rng_s = np.random.default_rng(args.seed + 3)
    gen_axis, file_axis = axis_pair(sc)
    f = fw.Forward(gen_axis, args.mac)
    specs = [edx_spec(r) for r in names]
    rid = np.array([names.index(r) for r in recipe.ravel()])
    t, rho, lam, ga = pixel_params(recipe, nx, sc["dead_rows"], f)
    res = f.run(specs, rid, t.ravel(), rho.ravel(), lam.ravel(), ga.ravel(), rid, len(names), rng=rng_x)
    eds = res["counts"].reshape(ny, nx, nch)
    cube4d = np.zeros((ny, nx, det, det), dtype=np.float32)
    for y in range(ny):
        pats = np.stack([bases[r] for r in recipe[y]])
        cube4d[y] = np.clip(rng4.poisson(pats), 0, 65535).astype(np.float32)
    # HAADF model: areal atoms x Z^1.7, relative to the reference matrix pixel
    zc = np.zeros(len(names))
    for i, (x_el, mbar, wf) in enumerate(res["med"]):
        zc[i] = sum(x_el.get(e, 0.0) * xm.ATOMIC_NUMBER[e] ** 1.7 for e in x_el if e != "O")
    n_tot = rho * t * fw.NA * 1e-21 / np.array([res["med"][r][1] for r in rid]).reshape(ny, nx)
    haadf_mean = 800.0 * n_tot * zc[rid].reshape(ny, nx) / (f.n_tot_ref * 13 ** 1.7) + 5.0
    haadf = rng_h.poisson(haadf_mean).astype(np.float32)
    return dict(sc=sc, recipe=recipe, grain=grain, precip=precip, stripe=stripe, precip_list=precip_list,
                names=names, rid=rid, t_nm=t, rho=rho, lam=lam, ga=ga, cube4d=cube4d, eds=eds, haadf=haadf,
                axis=gen_axis, file_axis=file_axis, forward=f, res=res, specs=specs, rng_s=rng_s, bases=bases,
                eds_pitch=sc["pitch_nm"])


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
    return g


def write_dm4_file(path, b, seed, truth_name):
    sc = b["sc"]
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    pitch = sc["pitch_nm"]
    eds = b["eds"]
    ney, nex = eds.shape[0], eds.shape[1]
    pitch_e = b["eds_pitch"]
    d_f, origin_f = b["file_axis"]
    survey, rect, survey_nm = make_survey(b)
    import hashlib
    b["hashes"] = {k: hashlib.sha256(np.ascontiguousarray(v).tobytes()).hexdigest() for k, v in
                   {"eds_ny_nx_nch_uint32": eds, "diffraction_ny_nx_qy_qx_float32": b["cube4d"],
                    "haadf_ny_nx_float32": b["haadf"], "survey_uint16": survey}.items()}
    thumb, tw, th = make_thumbnail(b)
    survey_id = [1234567, 2345678, 3456789, 1357911]
    ids = {"thumb": [11, 12, 13, 14], "haadf": [21, 22, 23, 24], "diff": [31, 32, 33, 34], "eds": [41, 42, 43, 44]}
    q_nm = md.Q_PIXEL_INV_A * 10.0 * (md.DET // det)             # 1/nm per detector pixel
    q_origin = md.ORIGIN if det == md.DET else (md.ORIGIN + 0.5) / (md.DET // det) - 0.5
    real_s = DWELL_S * nx * ny
    lam_map = b["lam"] if b["lam"].shape == (ney, nex) else np.full((ney, nex), 1 - DEAD_BASE)

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
        acq = tags.group("SI").group("Acquisition")           # ONE SI group (two same-named groups made rsciio drop the first)
        s = acq.group("Survey Image")
        s.struct("Spectrum Image Rect", "i64", [int(v) for v in rect])
        s.struct("Unique Image ID", "i64", survey_id)
        acq.value("Pixel time (s)", "f32", DWELL_S)

    root = Group()
    il = root.group("ImageList")
    # OBJECT ORDER IS LOAD-BEARING (G5): DM4Reader opens the FIRST Data array with more than 2 non-singleton dims, so the
    # Diffraction SI (4D) must come before the EDS SI (3D); DM4Experiment is order independent (it uses labels).
    il.add(image_object(name=f"Image Of {os.path.basename(path)}", dtype="rgba", dims=[tw, th], data=thumb,
                        calibrations=[(0.0, 1.0, ""), (0.0, 1.0, "")], unique_id=ids["thumb"], image_tags=Group("ImageTags")))
    t = Group("ImageTags")
    common(t, "Survey", "Image")
    t.group("Survey Image").struct("Unique Image ID", "i64", survey_id)
    il.add(image_object(name="ADF Image (SI Survey)", dtype="u16", dims=[survey.shape[1], survey.shape[0]],
                        data=survey, calibrations=[(0.0, survey_nm, "nm")] * 2, unique_id=survey_id, image_tags=t))
    t = Group("ImageTags"); common(t, "Scan Signal", "Image"); si_tags(t); sim_group(t, truth_name, seed)
    il.add(image_object(name="HAADF Image", dtype="f32", dims=[nx, ny], data=b["haadf"],
                        calibrations=[(0.0, pitch, "nm")] * 2, unique_id=ids["haadf"], image_tags=t))
    t = Group("ImageTags"); meta = common(t, "Diffraction", "Diffraction image")
    meta.value("Data Order Swapped", "i32", 1)
    si_tags(t); sim_group(t, truth_name, seed)
    il.add(image_object(name="Diffraction SI", dtype="f32", dims=[det, det, nx, ny], data=b["cube4d"].reshape(-1),
                        calibrations=[(q_origin, q_nm, "1/nm")] * 2 + [(0.0, pitch, "nm")] * 2,
                        unique_id=ids["diff"], image_tags=t))
    t = Group("ImageTags"); common(t, "EDS", "Spectrum image", signal="X-ray"); si_tags(t); sim_g = sim_group(t, truth_name, seed)
    e = t.group("EDS")
    acq = e.group("Acquisition")
    acq.value("Channels", "i32", nch); acq.value("Dispersion (eV)", "f32", d_f)
    acq.value("Exposure (s)", "f32", real_s); acq.string("Date", "10/5/2026")
    acq.string("Start time", "10:00:00 AM"); acq.string("End time", "10:00:04 AM"); acq.string("Continuous Mode", "spectrum image")
    di = e.group("Detector Info")
    di.value("Azimuthal angle", "f32", fw.SEG_AZ[0]); di.value("Elevation angle", "f32", fw.SEG_ELEV)
    di.value("Solid angle", "f32", 0.7); di.string("Detector type", "SuperX"); di.value("Stage tilt", "f32", fw.TILT_ALPHA)
    di.value("Incidence angle", "f32", 90.0)
    e.value("Solid angle", "f32", 0.7)
    e.value("Live time", "f32", real_s * float(lam_map.mean())); e.value("Real time", "f32", real_s)
    e.array("Live time map", "f32", lam_map.astype(np.float32).reshape(-1))
    il.add(image_object(name="EDS SI", dtype="u32", dims=[nex, ney, nch],
                        data=np.ascontiguousarray(eds.transpose(2, 0, 1)).reshape(-1),
                        calibrations=[(0.0, pitch_e, "nm"), (0.0, pitch_e, "nm"), (origin_f, d_f / 1000.0, "keV")],
                        unique_id=ids["eds"], image_tags=t, brightness_units="Counts"))
    sg = sim_g.group("Segments")      # the four Super-X segments of the physics (G8)
    sg.array("Azimuth (deg)", "f32", np.array(fw.SEG_AZ, dtype=np.float32))
    sg.array("Relative solid angle", "f32", np.array(fw.SEG_WEIGHT, dtype=np.float32))
    sg.value("Elevation (deg)", "f32", fw.SEG_ELEV); sg.value("Stage tilt alpha (deg)", "f32", fw.TILT_ALPHA)
    sg.string("Convention", "eXSpy take_off_angle: azimuth 0 perpendicular to the alpha-tilt axis, positive tilt faces that detector; c = sin(el)cos(a) + cos(el)cos(az)sin(a)")
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


def _experiment(f, title, signal_type, binned):
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


def _write_eds_hspy(path, eds, pitch, d_f, origin_f, nch, live, real):
    import h5py
    ny, nx = eds.shape[:2]
    with h5py.File(path, "w") as f:
        ex, m = _experiment(f, "EDS SI (simulated)", "EDS_TEM", True)
        ex.create_dataset("data", data=eds, chunks=(1, min(nx, 8), nch), compression="gzip", compression_opts=4)
        _axis(ex, 0, "y", ny, pitch, 0.0, "nm", True)
        _axis(ex, 1, "x", nx, pitch, 0.0, "nm", True)
        _axis(ex, 2, "Energy", nch, d_f, -origin_f * d_f, "eV", False)
        tem = m.require_group("Acquisition_instrument").require_group("TEM")
        tem.attrs["beam_energy"] = 200.0; tem.attrs["acquisition_mode"] = "STEM"; tem.attrs["microscope"] = "simulated Talos F200X"
        d = tem.require_group("Detector")
        eg = d.require_group("EDS")
        eg.attrs["azimuth_angle"] = 45.0; eg.attrs["elevation_angle"] = 18.0
        eg.attrs["live_time"] = live; eg.attrs["real_time"] = real; eg.attrs["energy_resolution_MnKa"] = 130.0
        d.require_group("Camera").attrs["exposure"] = DWELL_S


def write_hspy_pair(out_dir, name, b):
    import h5py
    sc = b["sc"]
    nx, ny, det, nch = sc["nx"], sc["ny"], sc["det"], sc["channels"]
    pitch = sc["pitch_nm"]
    d_f, origin_f = b["file_axis"]
    real = DWELL_S * nx * ny
    p_eds = os.path.join(out_dir, f"{name}_EDS.hspy")
    _write_eds_hspy(p_eds, b["eds"], pitch, d_f, origin_f, nch, real * float(b["lam"].mean()), real)
    p_4d = os.path.join(out_dir, f"{name}_4D.hspy")
    q_nm = md.Q_PIXEL_INV_A * 10.0 * (md.DET // det)
    q_origin = md.ORIGIN if det == md.DET else (md.ORIGIN + 0.5) / (md.DET // det) - 0.5
    with h5py.File(p_4d, "w") as f:
        ex, m = _experiment(f, "Diffraction SI (simulated)", "", False)
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
PHASES = ["Al", "beta''", "Q", "vacuum"]


class Store:
    """Per-pixel arrays: inline JSON lists for the tiny fixture, a compressed npz beside the json otherwise."""

    def __init__(self, tiny):
        self.tiny, self.arr = tiny, {}

    def put(self, name, a):
        self.arr[name] = np.asarray(a)

    def finalize(self, truth, path_json):
        if self.tiny:
            truth["arrays"] = {k: v.tolist() for k, v in self.arr.items()}
        else:
            import hashlib
            p = path_json.replace(".json", "_arrays.npz")
            np.savez_compressed(p, **self.arr)
            truth["arrays_file"] = os.path.basename(p)
            truth["arrays_sha256"] = hashlib.sha256(open(p, "rb").read()).hexdigest()
            truth["arrays_index"] = {k: [list(v.shape), str(v.dtype)] for k, v in self.arr.items()}


def phase_masks(recipe):
    ph = np.vectorize(phase_of)(recipe.astype(str))
    return np.stack([ph == p for p in PHASES])


def physics_truth(f, mac_path, dead_rows=()):
    eps = lambda e: float(xm.detector_efficiency(np.array([e]))[0])  # noqa: E731
    fam_e = {"Al_K": 1.4865, "Mg_K": 1.2536, "Si_K": 1.7397, "Cu_K": 8.0478, "Cu_L": 0.9295, "O_K": 0.5249, "Ga_L": 1.098}
    resp = {k: f.gp * xm.SENSITIVITY[k] * eps(e) for k, e in fam_e.items()}
    mass = {"Al_K": "Al", "Mg_K": "Mg", "Si_K": "Si", "Cu_K": "Cu", "Cu_L": "Cu", "O_K": "O", "Ga_L": "Ga"}
    k_at = {f"{k}_over_Si_K": resp["Si_K"] / resp[k] for k in resp if k != "Si_K"}
    k_wt = {f"{k}_over_Si_K": resp["Si_K"] / resp[k] * fw.ATOMIC_MASS[mass[k]] / fw.ATOMIC_MASS["Si"] for k in resp if k != "Si_K"}
    return {
        "convention": fw.__doc__.split("Geometry convention")[1].strip(),
        "absorption": {
            "method": "per segment j: T_j = int_0^1 g(s) exp(-x_j * exit(s)) ds by midpoint quadrature (4096 nodes) tabulated on a fine x grid; "
                      "g(s) = 1 + beta (s - 1/2); exit(s) = s (gun-side face, c > 0) or 1 - s (far face, c < 0); x_j = mu/rho(E) * rho * 1e-7 * t_nm / |c_j|. "
                      "T_eff = sum_j W_j T_j. NOT the closed form (1 - e^-x)/x: g makes them differ (the closed form is the beta = 0 case).",
            "depth_weight_beta": fw.DEPTH_BETA, "segments_azimuth_deg": list(fw.SEG_AZ), "elevation_deg": fw.SEG_ELEV,
            "stage_tilt_alpha_deg": fw.TILT_ALPHA, "segment_cos_c_j": [float(c) for c in f.cos],
            "segment_relative_solid_angle_W_j": list(fw.SEG_WEIGHT),
            "medium": "the pixel's own composition incl. the oxide O (Ga ignored); weight-fraction mixture of FFAST mu/rho, log-log interpolation",
            "mac_source": "NIST FFAST via EPQ FFastMAC.csv (usnistgov/EPQ, public domain in the US)",
            "mac_sha256": fw.sha_file(mac_path), "mac_elements_used": ["Al", "Mg", "Si", "Cu", "O"],
            "mac_layout": "one column pair per element (energy keV, mu/rho cm^2/g), pair index = Z-1, rows padded, each list ends with a (0,0) sentinel",
        },
        "thickness": {"base_nm": fw.THICKNESS_BASE_NM, "wedge": "t = base * (0.85 + 0.30 (x+0.5)/nx); precipitate pixels x 1.3 (nm along the foil normal)",
                      "phase_density_g_cm3": fw.PHASE_DENSITY, "precipitate_volume_fraction": PRECIP_VOLUME_FRACTION,
                      "areal_atoms_per_nm2": "N_tot = rho * t_nm * N_A * 1e-21 / Mbar; N_el = x_el N_tot (x_el incl. oxide O)"},
        "line_model": {"counts": "a = live * Gp * N_el * s_family * w_line * eps(E_line) * T_eff", "Gp_per_atom_per_nm2": f.gp,
                       "sensitivity_s": xm.SENSITIVITY, "true_k": {
                           "counts_per_atom_nm2_per_family_(Gp*s*eps)": resp,
                           "k_atomic_C_X_over_C_Si=k*I_X/I_Si": k_at, "k_weight_percent": k_wt,
                           "note": "absorption-free; the effective transmission per line and pixel is in arrays"}},
        "efficiency": {"formula": "eps(E) = exp(-(0.35/E)^2.2) * (1 - exp(-(27/E)^3)), E in keV; applied to lines AND continuum",
                       "eps_at_line_energies": {k: eps(e) for k, e in fam_e.items()}},
        "continuum": {"formula": "Kc * sum_el N_el Z_el * (E0-E)/E * eps(E) * T_eff(E,p) * dE * live, E0 = 200 keV, for 0.05 < E < E0",
                      "Kc": f.kc, "reference_total_counts_per_pixel_no_absorption": fw.KC_TOTAL_REF,
                      "vacuum_continuum_counts_per_pixel": fw.VACUUM_CONT, "absorption_edges": "emerge from mu_Al(E); no step parameter"},
        "features": {"al_ka_tail": {"fraction": fw.TAIL_FRAC, "lambda_keV": fw.TAIL_LAMBDA},
                     "si_internal_fluorescence": {"fraction_of_all_counts_above_Si_K_edge": fw.SI_INT, "edge_keV": fw.SI_K_EDGE,
                                                  "basis": "the whole expected spectrum above the edge incl. stray Cu K, escape and sum peaks"},
                     "escape": {"formula": "f = 0.02 (1.839/E)^1.5 of a line above the Si K edge moves to E - 1.7397 keV", "esc0": fw.ESC0},
                     "sum_peaks": {"kappa": fw.PILE_KAPPA, "law": "s_ab = kappa a_a a_b (a != b), kappa a_a^2 / 2 (a == b); parents lose the photons",
                                   "pairs_of": ["Al_Ka", "Mg_Ka", "Si_Ka"], "energies_keV": {"Al+Mg": 1.4865 + 1.2536, "Al+Si": 1.4865 + 1.7397}},
                     "stray_Cu_K_counts_per_pixel_Ka": fw.STRAY,
                     "ga_damage": {"lines": "Ga La 1.098, Lb1, Lb3, Ll, Ln", "region": f"the last {fw.GA_COLUMNS} scan columns, N_Ga = N_Ga0 exp(-d/{fw.GA_LAMBDA_PX} px)",
                                   "Ga_La_counts_per_pixel_at_edge_absorption_free": fw.GA_LA_EDGE_COUNTS},
                     "dead_time": {"base": DEAD_BASE, "ladder_rows": [list(r) for r in dead_rows],
                                   "note": "counts scale with the live fraction (1 - dead); the sum peaks follow the live-scaled rates (a lambda^2 law), so the dead-time rows have LESS pile-up, "
                                           "the opposite of real rate-driven dead time where pile-up and dead time rise together"}},
    }


ELEMENT_LINES = ["Al_Ka", "Mg_Ka", "Si_Ka", "O_Ka", "Cu_Ka", "Cu_La", "Ga_La"]


def detectability(f, spec, comp_counts, axis):
    """Currie L_D = 2.71 + 4.65 sqrt(B) for each planted element line and each planted nuisance peak of a pool. S = the component's
    expected counts inside +-1 FWHM (98.15 % of a Gaussian), B = the expected window total minus S. Computed from truth, no data."""
    out = {"elements": {}, "conflicts": {}}
    for c in f.comps:
        if c.name in ELEMENT_LINES:
            kind = "elements"
        elif c.kind in ("sum", "escape", "internal") and not c.name.endswith("stray_escape"):
            kind = "conflicts"
        else:
            continue
        amp = comp_counts.get(c.name, 0.0)
        W = xm.window_counts(spec, axis, c.energy)[0]
        S = 0.9815 * amp
        B = max(W - S, 0.0)
        ld = 2.71 + 4.65 * math.sqrt(B)
        out[kind][c.name] = {"energy_keV": c.energy, "signal_counts": S, "window_total": W, "background": B, "L_D": ld,
                             "signal_over_L_D": S / ld, "above_L_D": bool(S >= ld), "above_3_L_D": bool(S >= 3 * ld)}
    out["elements_above_L_D"] = sorted(k for k, v in out["elements"].items() if v["above_L_D"])
    out["conflicts_above_L_D"] = sorted(k for k, v in out["conflicts"].items() if v["above_L_D"])
    out["conflicts_above_3_L_D"] = sorted(k for k, v in out["conflicts"].items() if v["above_3_L_D"])
    return out


def net_sigma(spec, axis, e):
    """Window-method net counts and their Poisson sigma on an expected spectrum (the T-check variance)."""
    W, net, bl, br, npk, (nl, nr) = xm.window_counts(spec, axis, e)
    return net, math.sqrt(W + (0.5 * npk / nl) ** 2 * bl + (0.5 * npk / nr) ** 2 * br)


def recipe_truth(b, comp_names, names):
    f = b["forward"]
    res = b["res"]
    rid = b["rid"]
    amp, a_free, t_eff = res["amp"], res["a_free"], res["t_eff"]
    out = {}
    li = {n: i for i, n in enumerate(res["line_names"])}
    for ri, r in enumerate(names):
        m = rid == ri
        npx = int(m.sum())
        spec = b["specs"][ri]
        x_el, mbar, wf = res["med"][ri]
        comps = {n: float(amp[i, m].sum()) for i, n in enumerate(comp_names)}
        lines = {}
        for n in res["line_names"]:
            e, w = xm.LINES[n.split("_")[0]][n.split("_")[1]]
            af = float(a_free[li[n], m].sum())
            lines[n] = {"energy_keV": e, "weight": w, "fwhm_eV": 1000 * xm.fwhm_kev(e, f.fwhm_ev), "expected_total_counts": comps[n],
                        "expected_absorption_free_counts": af,
                        "mean_effective_transmission": float((a_free[li[n], m] * t_eff[li[n], m]).sum() / af) if af > 0 else None}
        tot = sum(spec.n.values())
        out[r] = {
            "phase": phase_of(r),
            "composition_at_pct_metals": {k: 100 * v / tot for k, v in spec.n.items()} if tot > 0 else {},
            "atom_fraction_incl_oxide": x_el, "oxide_O_per_metal_atom": 0.0 if spec.vacuum else spec.oxide,
            "n_pixels": npx, "mean_thickness_nm": float(b["t_nm"].ravel()[m].mean()), "mean_density_g_cm3": float(b["rho"].ravel()[m].mean()),
            "mean_live_fraction": float(b["lam"].ravel()[m].mean()),
            "expected_total_eds_counts": float(res["exp_sum"][ri].sum()),
            "mean_total_counts_per_pixel": float(res["exp_sum"][ri].sum() / npx),
            "lines": lines, "components_expected_total_counts": comps,
            "mu_rho_cm2_g_at_line_energies": {n: float(f.mu_rho(wf, lines[n]["energy_keV"])) if wf else 0.0 for n in lines},
            "detectability": detectability(f, res["exp_sum"][ri], comps, b["axis"]),
            "realised_total_eds_counts": int(b["eds"].reshape(-1, b["eds"].shape[2])[m].sum()),
            "realised_total_4d_counts": float(b["cube4d"].reshape(-1, *b["cube4d"].shape[2:])[m].sum(dtype=np.float64)),
        }
    return out


def write_truth(path, b, seed, sizes, dm4_name, rect, mac_path):
    sc = b["sc"]
    nx, ny = sc["nx"], sc["ny"]
    f = b["forward"]
    names = b["names"]
    res = b["res"]
    comp_names = [c.name for c in f.comps]
    st = Store(nx * ny < 100)
    npx = ny * nx
    st.put("thickness_nm", b["t_nm"]); st.put("density_g_cm3", b["rho"]); st.put("live_fraction", b["lam"]); st.put("ga_atoms_per_nm2", b["ga"])
    st.put("component_expected_counts", res["amp"].reshape(len(comp_names), ny, nx))
    st.put("line_absorption_free_counts", res["a_free"].reshape(-1, ny, nx))
    st.put("line_effective_transmission", res["t_eff"].reshape(-1, ny, nx))
    st.put("line_transmission_by_segment", res["t_seg"].reshape(4, -1, ny, nx))
    st.put("expected_spectrum_sum_by_recipe", res["exp_sum"])
    st.put("expected_total_counts_per_pixel", res["pix_total"].reshape(ny, nx))
    st.put("energy_true_keV_of_channel", b["axis"].centre)
    st.put("efficiency_of_channel", f.eps_ch)
    st.put("phase_masks_4d_grid", phase_masks(b["recipe"]))
    d_f, origin_f = b["file_axis"]
    truth = {
        "generator": {"name": "tools/demo-edx/sim_edx.py", "version": VERSION, "seed": seed,
                      "poisson_streams": "4D seed, EDS seed+1, HAADF seed+2, survey seed+3 (numpy default_rng)"},
        "files": {"dm4": dm4_name, "sizes_bytes": sizes},
        "scan": {"nx": nx, "ny": ny, "pitch_nm": sc["pitch_nm"], "dwell_s": DWELL_S, "dead_time_fraction_base": DEAD_BASE,
                 "note": "NOT square: nx != ny so an axis swap shows"},
        "detector_4d": {"pixels": sc["det"], "q_nm_inv_per_pixel": md.Q_PIXEL_INV_A * 10 * (md.DET // sc["det"]),
                        "make_demo_dose": {"unit_bragg_amplitude": md.S, "direct_beam_peak": md.DIRECT_BEAM_PEAK}},
        "edx": {"channels": sc["channels"], "dispersion_eV": sc["dispersion_ev"], "origin_channel": sc["origin"],
                "energy_offset_keV": -sc["origin"] * sc["dispersion_ev"] / 1000.0,
                "energy_of_channel": "(i - origin) * dispersion  (centre of channel i) -- the GENERATOR (true) axis",
                "axis_file": {"dispersion_eV": d_f, "origin_channel": origin_f, "offset_keV": -origin_f * d_f / 1000.0},
                "axis_planted": ({**AXIS_PERTURB, "correction": "E_true = (E_file - offset) / (1 + gain)"} if sc["perturb"] else None),
                "beam_keV": 200.0, "FWHM_MnKa_eV": 130.0, "dtype": "uint32",
                "fwhm_law": "eXSpy utils/eds/_xray_lines.py:138-175 sqrt(2.5*(E-5.8987 keV)*1000 + FWHM_MnKa^2) eV",
                "line_table": "eXSpy exspy/material/xray_lines.json (7185a4d): Al :119, Cu :716, Ga :1038, Mg :1725, O :1968, Si :2953",
                "rect_survey_pixels_top_left_bottom_right": list(rect)},
        "forward_model": physics_truth(f, mac_path, sc["dead_rows"]),
        "component_names": comp_names,
        "line_component_names": res["line_names"],
        "phases_at_pct": {"Al": {k: 100 * v for k, v in MATRIX.items()},
                          "beta_double_prime_Mg5Si6": {k: 100 * v for k, v in BETA.items()},
                          "Q_Al3Cu2Mg9Si7": {k: 100 * v for k, v in Q_PHASE.items()}},
        "recipes": recipe_truth(b, comp_names, names),
        "recipe_names_in_map_order": names,
        "recipe_map": [[names.index(r) for r in row] for row in b["recipe"].tolist()],
        "phase_names_for_masks": PHASES,
        "grain_label_map": b["grain"].tolist(), "grain_label_codes": {"0": "A", "1": "B", "2": "C", "3": "vacuum"},
        "precipitate_map": b["precip"].tolist(),
        "precipitate_codes": {"0": "none", "1": "beta'' end-on [010]", "2": "beta'' needle [001]", "3": "Q (stand-in pattern)"},
        "precipitates": [dict(p, pattern="stand-in (beta'' [001] +45 deg), not Q crystallography") if p["zone_axis_key"] == "Q" else p
                         for p in b["precip_list"]],
        "stripe_mask": b["stripe"].tolist(),
        "nuisances": nuisance_truth(b, comp_names, names),
        "array_sha256_of_written_arrays_C_order": b["hashes"],
        "totals_written": {"eds_counts": int(b["eds"].sum()), "diffraction_counts": float(b["cube4d"].sum(dtype=np.float64))},
        "guesses": GUESSES,
    }
    st.finalize(truth, path)
    with open(path, "w") as fh:
        json.dump(truth, fh, indent=None if st.tiny else 1)


def nuisance_truth(b, comp_names, names):
    amp = b["res"]["amp"]
    tot = {n: float(amp[i].sum()) for i, n in enumerate(comp_names)}
    return {
        "expected_total_counts_whole_image": {n: v for n, v in tot.items() if n.startswith(("sum_", "Al_Ka_tail", "Si_Ka_internal")) or n.endswith(("_escape", "_stray"))},
        "sum_peaks": {"Al+Mg_keV": 2.7401, "Al+Si_keV": 3.2262, "rate_law": "kappa * a_Al * a_Mg  (per pixel, live-scaled)"},
        "cu_grid_peak": {"lines": ["Cu_Ka_stray", "Cu_Kb_stray"], "counts_per_pixel_Ka_live_scaled": fw.STRAY},
        "escape": {"Cu_Ka_escape_keV": xm.LINES["Cu"]["Ka"][0] - fw.SI_KA},
        "ga": {"expected_Ga_La_total": tot.get("Ga_La", 0.0), "region_columns": list(range(b["sc"]["nx"] - fw.GA_COLUMNS, b["sc"]["nx"]))},
    }


# ---- dose ladder (EDS only) -------------------------------------------------------------------------------------
def region_params(recipe):
    """(thickness nm, density g/cm3) of a uniform region of `recipe` at wedge 1."""
    if recipe == "A":
        return fw.THICKNESS_BASE_NM, fw.PHASE_DENSITY["Al"]
    if recipe == "beta_pure":
        return fw.THICKNESS_BASE_NM * 3.0, fw.PHASE_DENSITY["beta"]      # 240 nm: at 1.3 t the uncorrected bias is only 2.7 % (1.9 sigma)
    v = PRECIP_VOLUME_FRACTION
    ph = "Q" if recipe == "precip_Q" else "beta"
    return fw.THICKNESS_BASE_NM * fw.PRECIP_T, (1 - v) * fw.PHASE_DENSITY["Al"] + v * fw.PHASE_DENSITY[ph]


K2_SIGMA_T_REL = 0.10          # thickness uncertainty assumed in the registered K2 criterion
K2_MODEL_FORM_REL = 0.016      # model-form term (closed-form vs numerical absorption, ~1.6 %, measured in round 2)
K2_TARGET_SIGMA = 0.012        # the K2 pool is dosed until sigma_count(Mg/Si) <= 1.2 % (registered bound 1.5 %)


def build_ladder(args, out_dir):
    """EDS-only: 6 matrix regions {0.3,1,3,10,30,100} counts/px, a beta'' region at ~300 counts/px (Al+Mg and Al+Si sum peaks
    above 3 L_D), and a K2 pool (full-fraction Mg5Si6 at 3 t dosed to sigma(Mg/Si) <= 1.2 %). 16 x 16 pixels each."""
    nxl, nyl, nch = 128, 16, 4096
    gen = xm.Axis(nch, 5.0, 95.6)
    f = fw.Forward(gen, args.mac)
    recipes = ["A"] * 6 + ["precip_endon_0", "beta_pure"]
    uniq = sorted(set(recipes))
    specs = [edx_spec(r) for r in uniq]

    def one(recipe, scale):
        t, rho = region_params(recipe)
        pile = 1.0 / scale if recipe == "beta_pure" else 1.0          # the K2 pool is dosed by DWELL time: pile-up stays at the base rate
        return f.run(specs, np.array([uniq.index(recipe)]), np.array([t]), np.array([rho]), np.array([scale]), np.array([0.0]),
                     np.array([0]), 1, keep_pixel_arrays=False, pile=np.array([pile]))["exp_sum"][0]

    def bisect(pred, lo=1e-4, hi=12.0):          # above ~12 the pile-up depletion would exceed the parent counts
        for _ in range(60):
            mid = math.sqrt(lo * hi)
            if pred(mid):
                hi = mid
            else:
                lo = mid
        return math.sqrt(lo * hi)

    scales, targets = [], []
    for k, r in enumerate(recipes):
        if k < 6:
            tgt = LADDER_DOSES[k]
            scales.append(bisect(lambda s: one(r, s).sum() >= tgt)); targets.append(tgt)
        elif r == "precip_endon_0":
            scales.append(bisect(lambda s: one(r, s).sum() >= 300.0)); targets.append(300.0)
        else:
            def sig(s):
                sp = 256 * one(r, s)                     # the whole 16 x 16 region
                nm, sm = net_sigma(sp, gen, xm.LINES["Mg"]["Ka"][0]); ns, ss = net_sigma(sp, gen, xm.LINES["Si"]["Ka"][0])
                return math.sqrt((sm / nm) ** 2 + (ss / ns) ** 2)
            scales.append(bisect(lambda s: sig(s) <= K2_TARGET_SIGMA)); targets.append(None)
    region = np.repeat(np.arange(8), 16)[None, :].repeat(nyl, 0)
    rid, tt, rr, lam, pile = [], [], [], [], []
    for k in region.ravel():
        t, rho = region_params(recipes[k])
        rid.append(uniq.index(recipes[k])); tt.append(t); rr.append(rho); lam.append(scales[k])
        pile.append(1.0 / scales[k] if recipes[k] == "beta_pure" else 1.0)
    npx = nyl * nxl
    res = f.run(specs, np.array(rid), np.array(tt), np.array(rr), np.array(lam), np.zeros(npx), region.ravel(), 8,
                rng=np.random.default_rng(args.seed + 10), pile=np.array(pile))
    eds = res["counts"].reshape(nyl, nxl, nch)
    name = "AlMgSi_edx_ladder"
    path = os.path.join(out_dir, name + ".hspy")
    _write_eds_hspy(path, eds, 5.0, 5.0, 95.6, nch, DWELL_S * npx * 0.95, DWELL_S * npx)
    comp_names = [c.name for c in f.comps]
    amp = res["amp"].reshape(len(comp_names), nyl, nxl)
    regions = []
    for k in range(8):
        sl = slice(16 * k, 16 * k + 16)
        comps = {n: float(amp[i][:, sl].sum()) for i, n in enumerate(comp_names)}
        sp = res["exp_sum"][k]
        reg = {"columns": [16 * k, 16 * k + 15], "recipe": recipes[k], "thickness_nm": region_params(recipes[k])[0],
               "density_g_cm3": region_params(recipes[k])[1], "target_mean_total_counts_per_pixel": targets[k], "rate_scale": scales[k],
               "expected_total_counts": float(sp.sum()), "expected_mean_counts_per_pixel": float(sp.sum() / 256),
               "realised_total_counts": int(eds[:, sl].sum()), "components_expected_total_counts": comps,
               "detectability": detectability(f, sp, comps, gen)}
        regions.append(reg)
    # the registered K2 criterion on the pure Mg5Si6 pool (region 8)
    k2r = regions[7]
    sp = res["exp_sum"][7]
    li = res["line_names"]
    m = (region.ravel() == 7)
    a_free = {n: float(res["a_free"][li.index(n)][m].sum()) for n in ("Mg_Ka", "Si_Ka")}
    t_eff = {n: float((res["a_free"][li.index(n)][m] * res["t_eff"][li.index(n)][m]).sum() / a_free[n]) for n in a_free}
    nm_, sm_ = net_sigma(sp, gen, xm.LINES["Mg"]["Ka"][0]); ns_, ss_ = net_sigma(sp, gen, xm.LINES["Si"]["Ka"][0])
    sig_count = math.sqrt((sm_ / nm_) ** 2 + (ss_ / ns_) ** 2)
    # d ln(T_Mg/T_Si) / d ln t by a central finite difference of the generator's own T_eff at the region's thickness
    t0, rho0 = region_params("beta_pure")
    x_el, mbar, wf = res["med"][uniq.index("beta_pure")]
    def lnr(tn):
        r_ = []
        for n in ("Mg_Ka", "Si_Ka"):
            e = xm.LINES[n[:2]]["Ka"][0]
            r_.append(f.effective_T(f.mu_rho(wf, e) * 1e-7 * rho0, tn)[0])
        return math.log(r_[0] / r_[1])
    dlnr = (lnr(t0 * 1.01) - lnr(t0 * 0.99)) / (math.log(1.01) - math.log(0.99))
    bias_rel = t_eff["Mg_Ka"] / t_eff["Si_Ka"] - 1.0
    sig_t = abs(dlnr) * K2_SIGMA_T_REL
    sig_total = math.sqrt(sig_count ** 2 + sig_t ** 2 + K2_MODEL_FORM_REL ** 2)
    window_factor = (nm_ / ns_) / (a_free["Mg_Ka"] * t_eff["Mg_Ka"] / (a_free["Si_Ka"] * t_eff["Si_Ka"]))
    k2r["k2"] = {
        "criterion": "K2 (registered): at the planted thickness the absorption-CORRECTED Mg/Si ratio has |pull_corrected| <= 2, with "
                     "sigma_total = sigma_count (+) sigma_t (+) 1.6 % (model form, quadrature), AND the UNCORRECTED ratio has |pull_uncorrected| >= 3 "
                     "(pull_uncorrected = relative bias / sigma_count). The pool is full-fraction Mg5Si6 (no Al, no matrix) at 3 t = 240 nm (at 1.3 t the uncorrected bias would be 2.7 % = 1.9 sigma, too weak).",
        "true_atomic_ratio_Mg_over_Si": 5 / 6, "mean_effective_transmission": t_eff, "absorption_free_counts": a_free,
        "uncorrected_relative_bias_Mg_over_Si": bias_rel, "sigma_count_rel_Mg_over_Si_window_method": sig_count,
        "dlnR_dlnt": dlnr, "sigma_t_rel_assumed": K2_SIGMA_T_REL, "sigma_t_rel_in_ratio": sig_t, "model_form_rel": K2_MODEL_FORM_REL,
        "sigma_total_rel": sig_total, "expected_pull_uncorrected": bias_rel / sig_count,
        "window_method_factor_net_ratio_over_true_count_ratio": window_factor,
        "note": "the window-method factor (estimator vs true counts, from the expected spectrum) is part of the 1.6 % model form",
    }
    truth = {
        "generator": {"name": "tools/demo-edx/sim_edx.py --ladder", "version": VERSION, "seed": args.seed + 10},
        "file": os.path.basename(path), "shape_ny_nx_nch": [nyl, nxl, nch],
        "note": "EDS-only: regions 1-6 matrix recipe A (80 nm) at {0.3..100} counts/px, region 7 beta'' (precip_endon_0, 104 nm) at ~300 counts/px, "
                "region 8 the K2 pool (pure Mg5Si6, 240 nm). 'rate_scale' multiplies every rate (not a live fraction); regions 1-7 raise the RATE (sum peaks grow as rate^2), region 8 is dosed by dwell time (counts x rate_scale, pile-up per count unchanged). The file axis equals the "
                "generator axis (no planted perturbation).",
        "regions": regions,
        "component_names": comp_names, "energy_axis": {"dispersion_eV": 5.0, "origin_channel": 95.6},
        "forward_model": physics_truth(f, args.mac),
        "detection_limit": "Currie L_D = 2.71 + 4.65 sqrt(B), B the expected window background (the window total minus the planted signal), window = +-1 FWHM",
    }
    st = Store(False)
    st.put("expected_spectrum_sum_by_region", res["exp_sum"])
    st.finalize(truth, os.path.join(out_dir, "truth_edx_ladder.json"))
    with open(os.path.join(out_dir, "truth_edx_ladder.json"), "w") as fh:
        json.dump(truth, fh, indent=1)
    return path


# ---- registration-mismatch variant ------------------------------------------------------------------------------
REG = {"nxe": 32, "nye": 24, "X0": 66, "Y0": -2, "pitch_e": 10.0}


def reg_affine():
    """2 x 3 affine mapping a 4D-grid pixel centre (x, y) to the EDS-grid pixel centre (u, v): u = -x/2 + (X0-0.5)/2, v = y/2 - (Y0+0.5)/2."""
    return [[-0.5, 0.0, (REG["X0"] - 0.5) / 2], [0.0, 0.5, -(REG["Y0"] + 0.5) / 2]]


def build_regmismatch(args, out_dir):
    b = build(args, {"det": 32, "perturb": False, "dead_rows": []})
    nx, ny, nch = b["sc"]["nx"], b["sc"]["ny"], b["sc"]["channels"]
    nxe, nye, X0, Y0 = REG["nxe"], REG["nye"], REG["X0"], REG["Y0"]
    vv, uu, jj, ii = np.meshgrid(np.arange(nye), np.arange(nxe), np.arange(2), np.arange(2), indexing="ij")
    xs, ys = X0 - 2 * uu - ii, Y0 + 2 * vv + jj
    outside = (xs < 0) | (xs >= nx) | (ys < 0) | (ys >= ny)
    idx = (np.clip(ys, 0, ny - 1) * nx + np.clip(xs, 0, nx - 1)).reshape(-1)
    ph4 = np.vectorize(phase_of)(b["recipe"].astype(str)).ravel()[idx].reshape(nye, nxe, 4)
    frac = np.stack([(ph4 == p).mean(-1) for p in PHASES])                 # (4, nye, nxe)
    group = frac.argmax(0)                                                  # majority phase (ties: lowest index)
    f = b["forward"]
    res = f.run(b["specs"], b["rid"][idx], b["t_nm"].ravel()[idx], b["rho"].ravel()[idx], b["lam"].ravel()[idx], b["ga"].ravel()[idx],
                group.ravel(), 4, rng=np.random.default_rng(args.seed + 20), footprint=4)
    eds_e = res["counts"].reshape(nye, nxe, nch)
    b["eds"], b["eds_pitch"] = eds_e, REG["pitch_e"]
    name = "AlMgSi_4D_EDX_regmismatch"
    path = os.path.join(out_dir, name + ".dm4")
    size, rect = write_dm4_file(path, b, args.seed, "truth_edx_regmismatch.json")
    truth = {
        "generator": {"name": "tools/demo-edx/sim_edx.py --regmismatch", "version": VERSION, "seed": args.seed},
        "file": os.path.basename(path), "size_bytes": size,
        "note": "4D grid 64 x 48 (detector binned to 32^2); the EDS SI is on a DIFFERENT grid: binned 2x (10 nm pixels, 32 x 24), shifted and mirrored in x. "
                "The file does not tell a reader: the EDS object's scan axes say 10 nm, the HAADF and Diffraction SI 5 nm.",
        "grids": {"4d": {"nx": nx, "ny": ny, "pitch_nm": 5.0}, "eds": {"nx": nxe, "ny": nye, "pitch_nm": REG["pitch_e"]}},
        "planted_transform": {
            "affine_2x3_4d_pixel_centre_to_eds_pixel_centre": reg_affine(),
            "definition": "EDS pixel (u, v) = the sum of the four 4D pixels x = X0 - 2u - i, y = Y0 + 2v + j (i, j in {0,1}); X0 = 66, Y0 = -2",
            "bin": 2, "mirror_x": True, "shift_4d_px": [3, -2],
            "shift_note": "the EDS window starts at 4D x = 66 (3 px past the right edge) and 4D y = -2 (2 px above the top); 4D pixels outside the grid are replicated from the nearest edge pixel",
            "outside_4d_grid": "eds_outside_fraction (arrays)"},
        "phase_names": PHASES, "eds_group_names": PHASES + [], "eds_group_rule": "majority phase of the 4 footprint pixels, ties to the lowest index",
        "recipe_names_in_map_order": b["names"], "recipe_map_4d": [[b["names"].index(r) for r in row] for row in b["recipe"].tolist()],
        "expected_total_eds_counts_by_group": [float(res["exp_sum"][g].sum()) for g in range(4)],
        "realised_total_eds_counts_by_group": [int(eds_e[group == g].sum()) for g in range(4)],
        "n_eds_pixels_by_group": [int((group == g).sum()) for g in range(4)],
        "array_sha256_of_written_arrays_C_order": b["hashes"],
        "guesses": GUESSES,
    }
    st = Store(False)
    st.put("phase_masks_4d_grid", phase_masks(b["recipe"]))
    st.put("eds_phase_fraction", frac)
    st.put("eds_outside_fraction", outside.mean((-1, -2)) if outside.ndim == 4 else outside)
    st.put("eds_group_map", group)
    st.put("expected_spectrum_sum_by_group", res["exp_sum"])
    st.put("eds_expected_total_counts_per_pixel", res["pix_total"].reshape(nye, nxe))
    st.finalize(truth, os.path.join(out_dir, "truth_edx_regmismatch.json"))
    with open(os.path.join(out_dir, "truth_edx_regmismatch.json"), "w") as fh:
        json.dump(truth, fh, indent=1)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reflections", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--tiny", action="store_true")
    ap.add_argument("--name", default=None)
    ap.add_argument("--ladder", action="store_true")
    ap.add_argument("--regmismatch", action="store_true")
    ap.add_argument("--mac", default=None)
    args = ap.parse_args()
    args.mac = args.mac or (DEFAULT_MAC if os.path.exists(DEFAULT_MAC) else os.environ.get("MAC_CSV"))
    if not args.mac or not os.path.exists(args.mac):
        sys.exit("FFastMAC.csv not found: pass --mac or set MAC_CSV (mac4DSTEM/Resources/Spectroscopy/FFastMAC.csv once lane K lands)")
    os.makedirs(args.out_dir, exist_ok=True)
    if args.ladder:
        print("ladder:", build_ladder(args, args.out_dir), file=sys.stderr); return
    if args.regmismatch:
        print("regmismatch:", build_regmismatch(args, args.out_dir), file=sys.stderr); return
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
        for p in write_hspy_pair(args.out_dir, name, b):
            sizes[os.path.basename(p)] = os.path.getsize(p)
    write_truth(os.path.join(args.out_dir, truth_name), b, args.seed, sizes, os.path.basename(dm4_path), rect, args.mac)
    for k, v in sizes.items():
        print(f"  {k}: {v / 1048576:.2f} MiB", file=sys.stderr)


if __name__ == "__main__":
    main()
