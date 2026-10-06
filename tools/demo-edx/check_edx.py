#!/usr/bin/env python3
"""tools/demo-edx/check_edx.py — checks of the simulated dataset (needs rsciio + h5py + numpy; no scipy).

S1  rsciio's DM reader returns the arrays the generator wrote (SHA-256 in truth), the .hspy pair / single file equal them.
S2  per recipe, window-method line counts from the summed EDS spectrum vs the model's expected spectrum within exact Poisson 95 %
    intervals (window total; window net z; ratio to Al Ka by the exact conditional binomial; totals).
    Window method (xray_model.window_counts): peak = line +- 1 FWHM; background = mean of the side windows [E-2.5F,E-1.5F), [E+1.5F,E+2.5F).
T1  transmission recomputed INDEPENDENTLY (96-point Gauss-Legendre, own MAC parser, own geometry from the truth parameters) equals the stored
    per-pixel per-line per-segment arrays; the Al K edge emerges; the closed form is NOT what the generator used.
T2  live-time ladder: counts scale with the live fraction (exact Poisson per region); the file's live-time map equals truth.
T3  nuisances: sum-peak product law, escape fraction, Ga edge decay (algebra on truth arrays) and data windows at 2.740 / 2.973 / 3.226 / 6.308 / 1.098 keV.
T4  planted energy axis: the file axis equals truth; line centroids in the file follow E_file = (1+g) E_true + o; gain/offset recovered.
T5  (--regmismatch file) the planted 2x3 affine reproduces the EDS-grid phase fractions from the 4D-grid masks; EDS counts follow the transformed HAADF.
T6  (--ladder file) dose ladder: region totals vs exact Poisson; sum peaks superlinear.
--fault NAME injects one defect in memory (transmission, convention, live, nuisance_law, nuisance_data, axis, affine, masks, ladder, k2) so each new check is seen red.
Pass rules (parameter-free, registered round 3): every statistical check inside its exact 99.9 % interval AND the count inside the 95 % interval
>= the binomial 5th percentile of n at p = 0.95; T4 within 3 sigma_Fisher of the planted axis (Cramer-Rao sigma of each line position from the expected
spectrum; F4 re-registered as within 2 sigma_Fisher, reported); T5 the planted affine maximises the correlation over {mirror_x} x shifts [-4,4]^2;
T3 scores Al+Al and Ga La as data tests, the other nuisances as exact-rate algebra.
Usage: check_edx.py <dir> [--mac FFastMAC.csv] [--fault NAME]
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xray_model as xm  # noqa: E402

LINES = [("Al", "Ka"), ("Mg", "Ka"), ("Si", "Ka"), ("O", "Ka"), ("Cu", "Ka"), ("Cu", "Kb"), ("Cu", "La")]
MASS = {"Al": 26.9815, "Mg": 24.305, "Si": 28.0855, "Cu": 63.546, "O": 15.999, "Ga": 69.723}
Z = {"Al": 13, "Mg": 12, "Si": 14, "Cu": 29, "O": 8, "Ga": 31}
_lg = np.frompyfunc(math.lgamma, 1, 1)
FAULT = None


def lgamma(x):
    return _lg(np.asarray(x, dtype=np.float64)).astype(np.float64)


def poisson_tails(k, mu):
    if mu <= 0:
        return (1.0, 1.0 if k == 0 else 0.0)
    hi = int(max(k, mu) + 12 * math.sqrt(max(k, mu) + 1) + 20)
    j = np.arange(0, hi + 1, dtype=np.float64)
    p = np.exp(j * math.log(mu) - mu - lgamma(j + 1))
    c = np.cumsum(p)
    kk = int(k)
    return float(c[min(kk, hi)]), float(1.0 - (c[kk - 1] if kk >= 1 else 0.0))


def binom_tails(k, n, p):
    j = np.arange(0, n + 1, dtype=np.float64)
    pm = np.exp(math.lgamma(n + 1) - lgamma(j + 1) - lgamma(n - j + 1) + j * math.log(p) + (n - j) * math.log1p(-p))
    c = np.cumsum(pm)
    kk = int(k)
    return float(c[kk]), float(1.0 - (c[kk - 1] if kk >= 1 else 0.0))


def inside(tails, alpha):
    return tails[0] >= alpha / 2 and tails[1] >= alpha / 2


def binom_ppf(q, n, p):
    j = np.arange(0, n + 1, dtype=np.float64)
    pm = np.exp(math.lgamma(n + 1) - lgamma(j + 1) - lgamma(n - j + 1) + j * math.log(p) + (n - j) * math.log1p(-p))
    c = np.cumsum(pm)
    return int(np.searchsorted(c, q))


def coverage_ok(flags95, flags999):
    n = len(flags95)
    return bool(all(flags999) and sum(flags95) >= binom_ppf(0.05, n, 0.95)), {"n": n, "inside_95": int(sum(flags95)), "min_inside_95": binom_ppf(0.05, n, 0.95),
                                                                              "outside_99.9": int(n - sum(flags999))}


def sha(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


def load_truth(d, name):
    t = json.load(open(os.path.join(d, name)))
    if "arrays" in t:
        a = {k: np.array(v) for k, v in t["arrays"].items()}
    else:
        z = np.load(os.path.join(d, t["arrays_file"]))
        a = {k: z[k] for k in z.files}
        assert hashlib.sha256(open(os.path.join(d, t["arrays_file"]), "rb").read()).hexdigest() == t["arrays_sha256"], "npz hash"
    return t, a


def own_mac(path):
    """Own parser of the EPQ FFastMAC.csv (pair per element, pair index Z-1, (0,0) sentinel)."""
    rows = [l.rstrip("\n").split(",") for l in open(path)]
    out = {}
    for el, z in Z.items():
        e, m = [], []
        for r in rows:
            if len(r) >= 2 * z and r[2 * z - 2].strip() and r[2 * z - 1].strip():
                a, b = float(r[2 * z - 2]), float(r[2 * z - 1])
                if a == 0 and b == 0:
                    continue
                e.append(a); m.append(b)
        out[el] = (np.log(np.array(e)), np.log(np.array(m)))
    return out


def mu_rho(mac, wf, energy):
    return sum(w * np.exp(np.interp(math.log(energy), *mac[el])) for el, w in wf.items())


def gl_T(x, beta, sign, n=96):
    """int_0^1 g(s) exp(-x e(s)) ds by Gauss-Legendre; x any array."""
    nodes, w = np.polynomial.legendre.leggauss(n)
    s, w = 0.5 * (nodes + 1), 0.5 * w
    g = 1 + beta * (s - 0.5)
    e = s if sign > 0 else 1 - s
    return (w * g * np.exp(-np.asarray(x)[..., None] * e)).sum(-1)


def segment_cos(fm, convention="exspy", tilt_sign=1.0):
    """Exit cosine c_j to the gun-side normal. 'exspy' = eXSpy take_off_angle written literally (beta tilt 0, theta = -elevation):
    sin(TOA) = sin(alpha) cos(phi) cos(theta) - cos(alpha) sin(theta). 'round2' = the round-2 formula (a pair swap of the azimuths)."""
    ab = fm["absorption"]
    el, al = math.radians(ab["elevation_deg"]), math.radians(tilt_sign * ab["stage_tilt_alpha_deg"])
    out = []
    for p in ab["segments_azimuth_deg"]:
        ph = math.radians(p)
        if convention == "exspy":
            th = -el
            out.append(math.sin(al) * math.cos(ph) * math.cos(th) - math.cos(al) * math.sin(th))
        else:
            out.append(-math.cos(el) * math.sin(ph) * math.sin(al) + math.sin(el) * math.cos(al))
    return np.array(out)


_DM_CACHE = {}


def read_dm_sigs(d, t):
    p = os.path.join(d, t["files"]["dm4"])
    if p not in _DM_CACHE:
        _DM_CACHE[p] = read_dm(p)
    return _DM_CACHE[p]


def read_dm(path):
    from rsciio.digitalmicrograph import file_reader
    return {s["metadata"]["General"]["title"]: s for s in file_reader(path)}


def window_total(spec, axis, e):
    return xm.window_counts(spec, axis, e)


# ======================================================================================================
def s1(d, t, A, res):
    r = res["S1"] = {}
    sigs = read_dm(os.path.join(d, t["files"]["dm4"]))
    nx, ny, nch = t["scan"]["nx"], t["scan"]["ny"], t["edx"]["channels"]
    h = t["array_sha256_of_written_arrays_C_order"]
    diff = sigs["Diffraction SI"]["data"]
    eds_raw = sigs["EDS SI"]["data"]
    eds = np.ascontiguousarray(eds_raw.transpose(1, 2, 0))
    r["diffraction_shape_is_ny_nx_qy_qx"] = diff.shape[:2] == (ny, nx)
    r["eds_raw_shape_is_nch_ny_nx"] = tuple(eds_raw.shape) == (nch, ny, nx)
    r["sha_diffraction_equal"] = sha(diff) == h["diffraction_ny_nx_qy_qx_float32"]
    r["sha_eds_equal"] = sha(eds) == h["eds_ny_nx_nch_uint32"]
    r["sha_haadf_equal"] = sha(sigs["HAADF Image"]["data"]) == h["haadf_ny_nx_float32"]
    r["sha_survey_equal"] = sha(sigs["ADF Image (SI Survey)"]["data"]) == h["survey_uint16"]
    r["eds_sum_equals_truth_total"] = int(eds.astype(np.int64).sum()) == t["totals_written"]["eds_counts"]
    r["diffraction_sum_equals_truth_total"] = float(diff.astype(np.float64).sum()) == t["totals_written"]["diffraction_counts"]
    ax = sigs["EDS SI"]["axes"][0]
    af = t["edx"]["axis_file"]
    r["energy_axis"] = {"scale_keV": float(ax["scale"]), "offset_keV": float(ax["offset"])}
    r["energy_axis_matches_truth_file_axis"] = bool(abs(ax["scale"] - af["dispersion_eV"] / 1000) < 1e-7 and abs(ax["offset"] - af["offset_keV"]) < 1e-6)
    r["meta_signal_xray"] = sigs["EDS SI"]["metadata"]["Signal"]["signal_type"] == "EDS_TEM"
    rr = t["edx"]["rect_survey_pixels_top_left_bottom_right"]
    r["rect_aspect_equals_scan_aspect"] = abs((rr[3] - rr[1]) / (rr[2] - rr[0]) - nx / ny) < 1e-9
    # live-time map tag equals truth
    om = sigs["EDS SI"]["original_metadata"]
    try:
        tags = om["ImageList"]["TagGroup0"]["ImageTags"]["EDS"]
        lm = np.asarray(tags["Live_time_map"] if "Live_time_map" in tags else tags["Live time map"]).reshape(ny, nx)
        r["live_time_map_tag_equals_truth"] = bool(np.allclose(lm, A["live_fraction"], atol=1e-6))
    except Exception as e:  # noqa: BLE001
        r["live_time_map_tag_equals_truth"] = f"unreadable: {e!r}"
    # the file's detector tags equal the PLANTED physics (round 3: the file used to contradict truth); rect/ID read as int tuples
    try:
        tg = om["ImageList"]["TagGroup0"]["ImageTags"]
        di = tg["EDS"]["Detector Info"]
        ab = t["forward_model"]["absorption"]
        sim = tg["mac4DSTEM Simulation"]
        seg = sim["Segments"]
        r["detector_tags_equal_planted_physics"] = bool(
            abs(di["Azimuthal angle"] - ab["segments_azimuth_deg"][0]) < 1e-4 and abs(di["Elevation angle"] - ab["elevation_deg"]) < 1e-4
            and abs(di["Stage tilt"] - ab["stage_tilt_alpha_deg"]) < 1e-4
            and np.allclose(list(seg["Azimuth (deg)"]), ab["segments_azimuth_deg"], atol=1e-4)
            and np.allclose(list(seg["Relative solid angle"]), ab["segment_relative_solid_angle_W_j"], atol=1e-6))
        rect_tag = read_dm_sigs(d, t)["Diffraction SI"]["original_metadata"]["ImageList"]["TagGroup0"]["ImageTags"]["SI"]["Acquisition"]
        rr_ = rect_tag["Survey Image"]["Spectrum Image Rect"]
        r["rect_struct_int_tuple_equals_truth"] = [int(v) for v in rr_] == [int(v) for v in t["edx"]["rect_survey_pixels_top_left_bottom_right"]]
    except Exception as e:  # noqa: BLE001
        r["detector_tags_equal_planted_physics"] = f"unreadable: {e!r}"; r["rect_struct_int_tuple_equals_truth"] = False
    p = os.path.join(d, os.path.basename(t["files"]["dm4"]).replace(".dm4", "_EDS.hspy"))
    if os.path.exists(p):
        import h5py
        from rsciio.hspy import file_reader as hs
        with h5py.File(p) as f:
            e2 = f["Experiments/__unnamed__/data"][()]
        with h5py.File(p.replace("_EDS", "_4D")) as f:
            c2 = f["Experiments/__unnamed__/data"][()]
        with h5py.File(p.replace("_EDS.hspy", "_single.h5")) as f:
            e3, c3, sv3 = f["eds"][()], f["diffraction"][()], f["survey"][()]
        r["hspy_eds_equals_dm4"] = bool(np.array_equal(e2, eds)) and e2.shape == (ny, nx, nch)
        r["hspy_4d_equals_dm4"] = bool(np.array_equal(c2, diff.astype(np.int32)))
        r["single_equals_dm4"] = bool(np.array_equal(e3, eds) and np.array_equal(c3, diff.astype(np.int32)) and np.array_equal(sv3, sigs["ADF Image (SI Survey)"]["data"]))
        h1 = hs(p)[0]
        r["rsciio_hspy_reads_pair"] = bool(np.array_equal(h1["data"], eds))
        r["hspy_energy_axis_eV"] = {"scale": h1["axes"][2]["scale"], "offset": h1["axes"][2]["offset"]}
        r["hspy_axis_matches_file_axis"] = bool(abs(h1["axes"][2]["scale"] - af["dispersion_eV"]) < 1e-9 and abs(h1["axes"][2]["offset"] - af["offset_keV"] * 1000) < 1e-6)
    for k in list(r):
        if isinstance(r[k], (np.bool_,)):
            r[k] = bool(r[k])
    r["pass"] = all(v is True for k, v in r.items() if isinstance(v, bool)) and r["live_time_map_tag_equals_truth"] is True and r["detector_tags_equal_planted_physics"] is True
    return sigs, eds


def s2(d, t, A, eds, res):
    r = res["S2"] = {}
    e = t["edx"]
    axis = xm.Axis(e["channels"], e["dispersion_eV"], e["origin_channel"])
    names = t["recipe_names_in_map_order"]
    rmap = np.array(t["recipe_map"])
    exp_by = A["expected_spectrum_sum_by_recipe"]
    rows = []
    for ri, rn in enumerate(names):
        mask = rmap == ri
        npx = int(mask.sum())
        if npx == 0:
            continue
        exp_spec = exp_by[ri]
        data_spec = eds[mask].sum(axis=0).astype(np.float64)
        td, te = float(data_spec.sum()), float(exp_spec.sum())
        rows.append({"recipe": rn, "kind": "total_eds", "line": "all", "data": td, "expected": te,
                     "p95": inside(poisson_tails(td, te), 0.05), "p999": inside(poisson_tails(td, te), 0.001)})
        wd, we = {}, {}
        for el, ln in LINES:
            en = xm.LINES[el][ln][0]
            wd[(el, ln)] = xm.window_counts(data_spec, axis, en)
            we[(el, ln)] = xm.window_counts(exp_spec, axis, en)
        for (el, ln), (W, net, bl, br, npk, (nl, nr)) in wd.items():
            We, nete, ble, bre = we[(el, ln)][:4]
            tl = poisson_tails(W, We)
            sig2 = We + (0.5 * npk / nl) ** 2 * ble + (0.5 * npk / nr) ** 2 * bre
            z = (net - nete) / math.sqrt(sig2) if sig2 > 0 else 0.0
            nm = f"{el}_{ln}"
            rows.append({"recipe": rn, "kind": "window_total", "line": nm, "data": W, "expected": We, "p95": inside(tl, 0.05), "p999": inside(tl, 0.001)})
            rows.append({"recipe": rn, "kind": "window_net_z", "line": nm, "data": net, "expected": nete, "z": z, "p95": abs(z) < 1.96, "p999": abs(z) < 3.29})
        wa, wae = wd[("Al", "Ka")][0], we[("Al", "Ka")][0]
        if wae >= 5:
            for (el, ln), (W, *_x) in wd.items():
                if (el, ln) == ("Al", "Ka"):
                    continue
                We = we[(el, ln)][0]
                if We < 1:
                    continue
                tl = binom_tails(int(W), int(W + wa), We / (We + wae))
                rows.append({"recipe": rn, "kind": "ratio_to_AlKa_binomial", "line": f"{el}_{ln}", "data": W / max(wa, 1), "expected": We / wae,
                             "p95": inside(tl, 0.05), "p999": inside(tl, 0.001)})
    n95 = sum(1 for x in rows if x["p95"]); n999 = sum(1 for x in rows if x["p999"])
    r["n_checks"] = len(rows); r["inside_95_fraction"] = n95 / len(rows); r["outside_99.9_count"] = len(rows) - n999
    r["outside_99.9"] = [x for x in rows if not x["p999"]]
    r["dose_mean_total_counts_per_pixel_by_recipe"] = {k: round(v["mean_total_counts_per_pixel"], 1) for k, v in t["recipes"].items()}
    ok, info = coverage_ok([x["p95"] for x in rows], [x["p999"] for x in rows])
    r["coverage_rule"] = info
    r["pass"] = ok
    return rows


def t1(d, t, A, mac_path, res):
    r = res["T1"] = {}
    fm = t["forward_model"]
    mac = own_mac(mac_path)
    r["mac_sha256_equals_truth"] = hashlib.sha256(open(mac_path, "rb").read()).hexdigest() == fm["absorption"]["mac_sha256"]
    names = t["recipe_names_in_map_order"]
    rmap = np.array(t["recipe_map"])
    conv = "round2" if FAULT == "convention" else "exspy"
    cj = segment_cos(fm, conv)
    r["segment_cos"] = [float(c) for c in cj]
    r["segment_cos_equals_truth_under_exspy_convention"] = bool(np.allclose(cj, fm["absorption"]["segment_cos_c_j"], atol=1e-12))
    W = np.array(fm["absorption"]["segment_relative_solid_angle_W_j"])
    r["segment_weights_unequal"] = bool(np.ptp(W) > 0.05)
    beta = fm["absorption"]["depth_weight_beta"]
    t_eff, t_seg = A["line_effective_transmission"].copy(), A["line_transmission_by_segment"].copy()
    if FAULT == "transmission":
        t_eff = t_eff * 1.01
    th, rho = A["thickness_nm"], A["density_g_cm3"]
    worst, worst_cf, n = 0.0, 0.0, 0
    sw = {"pair_swapped_round2_convention": 0.0, "tilt_sign_error": 0.0}
    c_swap, c_sign = segment_cos(fm, "round2"), segment_cos(fm, "exspy", -1.0)
    ln_names = t["line_component_names"]
    for ri, rn in enumerate(names):
        rec = t["recipes"][rn]
        if rec["phase"] == "vacuum":
            continue
        m = rmap == ri
        x_el = rec["atom_fraction_incl_oxide"]
        mbar = sum(x_el[k] * MASS[k] for k in x_el)
        wf = {k: x_el[k] * MASS[k] / mbar for k in x_el}
        for li, ln in enumerate(ln_names):
            e = xm.LINES[ln.split("_")[0]][ln.split("_")[1]][0]
            kap = mu_rho(mac, wf, e) * 1e-7
            xs = kap * rho[m] * th[m]
            T = np.stack([gl_T(xs / abs(c), beta, 1 if c > 0 else -1) for c in cj])
            teff = np.tensordot(W, T, axes=1)
            worst = max(worst, float(np.max(np.abs(T / t_seg[:, li][:, m] - 1))), float(np.max(np.abs(teff / t_eff[li][m] - 1))))
            xx = xs[None, :] / np.abs(cj)[:, None]
            cf = np.where(xx > 1e-9, (1 - np.exp(-xx)) / np.maximum(xx, 1e-9), 1.0)
            worst_cf = max(worst_cf, float(np.max(np.abs(T - cf) / T)))
            n += T.size
            for key, c2 in (("pair_swapped_round2_convention", c_swap), ("tilt_sign_error", c_sign)):
                T2 = np.stack([gl_T(xs / abs(c), beta, 1 if c > 0 else -1) for c in c2])
                sw[key] = max(sw[key], float(np.max(np.abs(np.tensordot(W, T2, axes=1) / teff - 1))))
    r["max_rel_diff_vs_generator"] = worst
    r["n_values"] = n
    r["max_rel_diff_numeric_vs_closed_form"] = worst_cf
    r["not_the_closed_form"] = worst_cf > 1e-3
    r["T_eff_max_rel_diff_under_wrong_convention"] = sw
    r["wrong_conventions_detectable_over_1pct"] = bool(min(sw.values()) > 0.01)
    rec = t["recipes"]["A"]
    x_el = rec["atom_fraction_incl_oxide"]; mbar = sum(x_el[k] * MASS[k] for k in x_el)
    wf = {k: x_el[k] * MASS[k] / mbar for k in x_el}
    lo, hi = [np.tensordot(W, np.stack([gl_T(mu_rho(mac, wf, e) * 1e-7 * 2.70 * 80.0 / abs(c), beta, 1 if c > 0 else -1) for c in cj]), axes=1) for e in (1.55, 1.57)]
    r["edge_ratio_T_1.57_over_T_1.55"] = float(hi / lo)
    r["edge_emerges"] = bool(0.6 < hi / lo < 0.99 and "no step parameter" in fm["continuum"]["absorption_edges"])
    r["pass"] = bool(r["mac_sha256_equals_truth"] and r["segment_cos_equals_truth_under_exspy_convention"] and r["segment_weights_unequal"] and worst < 2e-5
                     and r["not_the_closed_form"] and r["edge_emerges"] and r["wrong_conventions_detectable_over_1pct"])


def t2(d, t, A, eds, res):
    r = res["T2"] = {}
    lam, tot = A["live_fraction"], A["expected_total_counts_per_pixel"]
    data = eds.sum(2).astype(np.float64)
    vals = sorted(set(np.round(lam.ravel(), 6)))
    if FAULT == "live":
        data = data.copy(); data[lam < 0.9] *= 1.25
    f95, f999 = [], []
    r["regions"] = {}
    for v in vals:
        m = np.abs(lam - v) < 1e-6
        dd, ee = float(data[m].sum()), float(tot[m].sum())
        tl = poisson_tails(dd, ee)
        r["regions"][f"live_{v:.2f}"] = {"pixels": int(m.sum()), "data": dd, "expected": ee, "p95": inside(tl, 0.05), "p999": inside(tl, 0.001)}
        f95.append(inside(tl, 0.05)); f999.append(inside(tl, 0.001))
    # same recipe, same column, different live fraction: the expected total scales with the live fraction (pile-up ~lambda^2 makes it slightly sub-linear)
    rmap = np.array(t["recipe_map"])
    ok_ratio = True
    best = None
    for x in range(lam.shape[1]):
        for y0 in range(lam.shape[0]):
            for y1 in range(y0 + 1, lam.shape[0]):
                if rmap[y0, x] == rmap[y1, x] and abs(lam[y0, x] - lam[y1, x]) > 0.2 and t["recipes"][t["recipe_names_in_map_order"][rmap[y0, x]]]["phase"] != "vacuum":
                    best = (y0, y1, x); break
            if best: break
        if best: break
    if best:
        y0, y1, x = best
        ratio = tot[y0, x] / tot[y1, x]; lr = lam[y0, x] / lam[y1, x]
        r["expected_ratio_same_column_vs_live_ratio"] = [float(ratio), float(lr)]
        ok_ratio = abs(ratio / lr - 1) < 0.03
    r["scales_with_live_fraction"] = bool(ok_ratio)
    ok, info = coverage_ok(f95, f999)
    r["coverage_rule"] = info
    r["pass"] = bool(ok and ok_ratio)


def t3(d, t, A, eds, res):
    r = res["T3"] = {}
    fm = t["forward_model"]
    names = t["component_names"]
    amp = {n: A["component_expected_counts"][i] for i, n in enumerate(names)}
    kappa = fm["features"]["sum_peaks"]["kappa"]
    if FAULT == "nuisance_law":
        amp = dict(amp); amp["sum_Al_Ka+Si_Ka"] = amp["sum_Al_Ka+Si_Ka"] * 1.5
    trio = ["Al_Ka", "Mg_Ka", "Si_Ka"]
    pairs = [(a, b) for i, a in enumerate(trio) for b in trio[i:]]
    tot = {a: amp[a] + (amp["Al_Ka_tail"] if a == "Al_Ka" else 0) for a in trio}
    for a, b in pairs:
        s_ = amp[f"sum_{a}+{b}"]
        tot[a] = tot[a] + s_ * (2 if a == b else 1) if a == b else tot[a] + s_
        if a != b:
            tot[b] = tot[b] + s_
    worst = 0.0
    for a, b in pairs:
        s_ = amp[f"sum_{a}+{b}"]
        want = kappa * tot[a] * tot[b] * (0.5 if a == b else 1.0)
        m = want > 0
        worst = max(worst, float(np.max(np.abs(s_[m] / want[m] - 1))))
    r["sum_peak_product_law_max_rel_error"] = worst
    esc0 = fm["features"]["escape"]["esc0"]
    we = 0.0
    for p in ("Cu_Ka", "Cu_Kb", "Cu_Ka_stray", "Cu_Kb_stray"):
        e0 = xm.LINES["Cu"][p[3:5]][0]
        f = esc0 * (1.839 / e0) ** 1.5
        main, esc = amp[p], amp[p + "_escape"]
        m = main > 0
        we = max(we, float(np.max(np.abs(esc[m] / (main[m] + esc[m]) / f - 1))))
    r["escape_fraction_max_rel_error"] = we
    li = t["line_component_names"].index("Ga_La")
    ga, lam = A["ga_atoms_per_nm2"], A["live_fraction"]
    gp = fm["line_model"]["Gp_per_atom_per_nm2"]; s_ga = fm["line_model"]["sensitivity_s"]["Ga_L"]
    eps = fm["efficiency"]["eps_at_line_energies"]["Ga_L"]
    af = A["line_absorption_free_counts"][li]
    r["ga_absorption_free_max_rel_error"] = float(np.max(np.abs(af[ga > 0] / (lam * gp * ga * s_ga * 1.0 * eps)[ga > 0] - 1)))
    cols = t["nuisances"]["ga"]["region_columns"]
    row = ga[min(10, ga.shape[0] - 1)]
    r["ga_column_ratio_toward_edge"] = float(np.mean([row[c + 1] / row[c] for c in cols[:-1]])); r["ga_ratio_expected"] = math.exp(0.5)
    e = t["edx"]
    axis = xm.Axis(e["channels"], e["dispersion_eV"], e["origin_channel"])
    data_spec = eds.sum(axis=(0, 1)).astype(np.float64)
    exp_spec = A["expected_spectrum_sum_by_recipe"].sum(0)
    if FAULT == "nuisance_data":
        c = xm.channel_range(axis, 2.9730 - 0.1, 2.9730 + 0.1)          # zero the Al+Al window: the data test must fail
        data_spec = data_spec.copy(); data_spec[c] = 0
    wins, data_ok = {}, True
    tiny = t["scan"]["nx"] * t["scan"]["ny"] < 100
    for nm, en, scored in (("Al+Al_2.973", 2.9730, True), ("Ga_La_1.098", 1.098, True), ("Al+Mg_2.740", 2.7401, False), ("Al+Si_3.226", 3.2262, False),
                           ("Cu_Ka_escape_6.308", 6.3081, False)):
        W, *_ = xm.window_counts(data_spec, axis, en)
        We, *_ = xm.window_counts(exp_spec, axis, en)
        tl = poisson_tails(W, We)
        wins[nm] = {"data": W, "expected": We, "p95": inside(tl, 0.05), "p999": inside(tl, 0.001), "scored_as_data_test": scored and not tiny}
        if scored and not tiny:
            data_ok &= inside(tl, 0.001)
    r["windows"] = wins
    r["whole_image_expected_component_counts"] = {n: float(amp[n].sum()) for n in ("sum_Al_Ka+Mg_Ka", "sum_Al_Ka+Si_Ka", "sum_Al_Ka+Al_Ka", "Cu_Ka_escape", "Ga_La")}
    r["note"] = "Al+Mg, Al+Si and Cu Ka escape are scored as exact-rate algebra only: they are not detectable in the whole-image sum (see truth detectability)"
    r["pass"] = bool(worst < 1e-9 and we < 1e-9 and r["ga_absorption_free_max_rel_error"] < 1e-6 and abs(r["ga_column_ratio_toward_edge"] - r["ga_ratio_expected"]) < 1e-6 and data_ok)


def t4(d, t, A, eds, res):
    """Planted energy axis. Per line the position is the centroid of the data on the FILE axis against the expected spectrum on the true axis; the
    per-line sigma is the Cramer-Rao (Fisher) bound for a known-shape position from the expected spectrum: 1 / sqrt(sum (d lambda/dE)^2 / lambda)."""
    r = res["T4"] = {}
    e = t["edx"]
    pl = e["axis_planted"]
    if pl is None:
        r["planted"] = False; r["pass"] = True; return
    g, o = pl["gain"], pl["offset_eV"] / 1000.0
    if FAULT == "axis":
        o = -0.020
    gen = xm.Axis(e["channels"], e["dispersion_eV"], e["origin_channel"])
    af = e["axis_file"]
    file_c = (np.arange(e["channels"]) - af["origin_channel"]) * af["dispersion_eV"] / 1000.0
    r["file_axis_equals_planted_relation"] = bool(np.allclose(file_c, (1 + g) * gen.centre + (-0.010 if FAULT == "axis" else o), atol=1e-9))
    data = eds.sum(axis=(0, 1)).astype(np.float64)
    exp = A["expected_spectrum_sum_by_recipe"].sum(0)

    def centroid(spec, ax, e0):
        f = xm.fwhm_kev(e0)
        m = (ax >= e0 - 1.2 * f) & (ax <= e0 + 1.2 * f)
        w = spec[m]
        return float((w * ax[m]).sum() / w.sum())

    def fisher_sigma(e0):
        f = xm.fwhm_kev(e0)
        m = (gen.centre >= e0 - 1.5 * f) & (gen.centre <= e0 + 1.5 * f)
        grad = np.gradient(exp, gen.centre)
        return 1.0 / math.sqrt(float((grad[m] ** 2 / np.maximum(exp[m], 1e-12)).sum()))

    out, pts = {}, []
    for nm, e0 in (("O_Ka", 0.5249), ("Al_Ka", 1.4865), ("Cu_Ka", 8.0478)):
        ct = centroid(exp, gen.centre, e0)
        cm = centroid(data, file_c, (1 + g) * e0 + pl["offset_eV"] / 1000.0)
        sg = fisher_sigma(e0)
        pred = (1 + g) * ct + o
        out[nm] = {"centroid_true_expected_keV": ct, "predicted_file_keV": pred, "measured_file_keV": cm, "sigma_fisher_eV": 1000 * sg, "diff_eV": 1000 * (cm - pred)}
        pts.append((ct, cm, sg))
    X = np.array([[p[0], 1.0] for p in pts]); y = np.array([p[1] for p in pts]); w = np.array([1 / p[2] ** 2 for p in pts])
    cov = np.linalg.inv(X.T @ (X * w[:, None])); a_b = cov @ (X.T @ (w * y))
    gain_rec, off_rec = a_b[0] - 1, a_b[1] * 1000
    sg_g, sg_o = math.sqrt(cov[0, 0]), 1000 * math.sqrt(cov[1, 1])
    r["lines"] = out
    r["recovered_gain"] = gain_rec; r["gain_sigma_fisher"] = sg_g; r["planted_gain"] = pl["gain"]
    r["recovered_offset_eV"] = off_rec; r["offset_sigma_fisher_eV"] = sg_o; r["planted_offset_eV"] = pl["offset_eV"]
    r["gain_pull"] = (gain_rec - pl["gain"]) / sg_g; r["offset_pull"] = (off_rec - pl["offset_eV"]) / sg_o
    r["within_2_sigma_fisher_F4"] = bool(abs(r["gain_pull"]) <= 2 and abs(r["offset_pull"]) <= 2)
    tiny = t["scan"]["nx"] * t["scan"]["ny"] < 100
    r["pass"] = bool(r["file_axis_equals_planted_relation"] and (tiny or (abs(r["gain_pull"]) <= 3 and abs(r["offset_pull"]) <= 3
                                                                           and all(abs(v["diff_eV"]) <= 3 * v["sigma_fisher_eV"] for v in out.values()))))
    if tiny:
        r["note"] = "tiny fixture: too few counts, the statistical part is informational"


def t5(d, tn, res, args):
    r = res["T5"] = {}
    t, A = load_truth(d, "truth_edx_regmismatch.json")
    sigs = read_dm(os.path.join(d, t["file"]))
    nxe, nye = t["grids"]["eds"]["nx"], t["grids"]["eds"]["ny"]
    nx, ny = t["grids"]["4d"]["nx"], t["grids"]["4d"]["ny"]
    eds_raw = sigs["EDS SI"]["data"]
    eds = np.ascontiguousarray(eds_raw.transpose(1, 2, 0))
    r["shapes"] = {"eds_nch_ny_nx": list(eds_raw.shape), "haadf": list(sigs["HAADF Image"]["data"].shape)}
    r["sha_eds_equal"] = sha(eds) == t["array_sha256_of_written_arrays_C_order"]["eds_ny_nx_nch_uint32"]
    r["scan_axis_nm_eds_vs_haadf"] = [sigs["EDS SI"]["axes"][1]["scale"], sigs["HAADF Image"]["axes"][1]["scale"]]
    M4 = A["phase_masks_4d_grid"].copy()
    if FAULT == "masks":
        M4 = np.roll(M4, 7, axis=1)
    aff = np.array(t["planted_transform"]["affine_2x3_4d_pixel_centre_to_eds_pixel_centre"])
    if FAULT == "affine":
        aff = aff.copy(); aff[0, 2] += 1.0
    frac = np.zeros((4, nye, nxe)); cnt = np.zeros((nye, nxe))
    ys, xs = np.mgrid[0:ny, 0:nx]
    u = np.floor(aff[0, 0] * xs + aff[0, 1] * ys + aff[0, 2] + 0.5).astype(int)
    v = np.floor(aff[1, 0] * xs + aff[1, 1] * ys + aff[1, 2] + 0.5).astype(int)
    ok = (u >= 0) & (u < nxe) & (v >= 0) & (v < nye)
    for p in range(4):
        np.add.at(frac[p], (v[ok], u[ok]), M4[p][ok] / 4.0)
    np.add.at(cnt, (v[ok], u[ok]), 0.25)
    inside_all = A["eds_outside_fraction"] == 0
    r["pixels_fully_inside_4d_grid"] = int(inside_all.sum()); r["pixels_with_outside_footprint"] = int((~inside_all).sum())
    r["affine_reproduces_eds_phase_fractions"] = bool(np.allclose(frac[:, inside_all], A["eds_phase_fraction"][:, inside_all], atol=1e-12) and np.allclose(cnt[inside_all], 1.0))
    # the planted transform maximises corr(EDS total, transformed HAADF) over {mirror_x} x shifts [-4,4]^2; the origin is derived from the affine
    X0 = int(round(2 * aff[0, 2] + 0.5))                      # u = -x/2 + (X0 - 0.5)/2
    Y0 = int(round(-2 * aff[1, 2] - 0.5))                     # v = y/2 - (Y0 + 0.5)/2
    hd = sigs["HAADF Image"]["data"].astype(float)
    tot = eds.sum(2).astype(float)
    uu, vv, ii, jj = np.meshgrid(np.arange(nxe), np.arange(nye), np.arange(2), np.arange(2))

    def corr(mirror, dx, dy):
        x = (X0 + dx - 2 * uu - ii) if mirror else (X0 + dx - 2 * (nxe - 1) - 1 + 2 * uu + ii)
        y = Y0 + dy + 2 * vv + jj
        tr = hd[np.clip(y, 0, ny - 1), np.clip(x, 0, nx - 1)].sum((2, 3))
        return float(np.corrcoef(tot.ravel(), tr.ravel())[0, 1])

    grid = {(mi, dx, dy): corr(mi, dx, dy) for mi in (True, False) for dx in range(-4, 5) for dy in range(-4, 5)}
    best = max(grid, key=grid.get)
    ident = float(np.corrcoef(tot.ravel(), hd.reshape(nye, 2, nxe, 2).sum((1, 3)).ravel())[0, 1])
    r["corr_at_planted"] = grid[(True, 0, 0)]; r["argmax_over_mirror_and_shifts"] = [bool(best[0]), best[1], best[2]]
    r["corr_identity_naive_2x_binning"] = ident
    r["planted_is_argmax"] = bool(best == (True, 0, 0)) and ident < grid[best]
    gs = []
    for gi in range(4):
        m = A["eds_group_map"] == gi
        if not m.any():
            continue
        dd, ee = float(eds[m].sum()), float(A["expected_spectrum_sum_by_group"][gi].sum())
        tl = poisson_tails(dd, ee)
        gs.append({"group": t["phase_names"][gi], "data": dd, "expected": ee, "p95": inside(tl, 0.05), "p999": inside(tl, 0.001)})
    r["group_sums"] = gs
    r["pass"] = bool(r["sha_eds_equal"] and r["affine_reproduces_eds_phase_fractions"] and r["planted_is_argmax"] and all(x["p999"] for x in gs))


def t6(d, res):
    r = res["T6"] = {}
    t, A = load_truth(d, "truth_edx_ladder.json")
    from rsciio.hspy import file_reader as hs
    s = hs(os.path.join(d, t["file"]))[0]
    data = s["data"].astype(np.int64)
    r["shape"] = list(data.shape)
    if FAULT == "ladder":
        data = data.copy(); data[:, 48:64] *= 2
    f95, f999, r["regions"] = [], [], []
    ok_t = True
    for k, reg in enumerate(t["regions"]):
        dd = int(data[:, 16 * k:16 * k + 16].sum())
        ee = reg["expected_total_counts"]
        tl = poisson_tails(dd, ee)
        f95.append(inside(tl, 0.05)); f999.append(inside(tl, 0.001))
        tgt = reg["target_mean_total_counts_per_pixel"]
        te = (abs(reg["expected_mean_counts_per_pixel"] / tgt - 1) < 1e-6) if tgt else True
        ok_t &= te
        r["regions"].append({"recipe": reg["recipe"], "target_mean": tgt, "expected_mean": reg["expected_mean_counts_per_pixel"], "data_mean": dd / 256,
                             "p95": f95[-1], "p999": f999[-1], "target_equals_expected": te})
    ok, info = coverage_ok(f95, f999)
    r["coverage_rule"] = info
    s_hi = t["regions"][5]["components_expected_total_counts"]["sum_Al_Ka+Si_Ka"]; s_mid = t["regions"][4]["components_expected_total_counts"]["sum_Al_Ka+Si_Ka"]
    r["sum_peak_Al+Si_ratio_dose100_over_dose30"] = s_hi / s_mid
    # region 7: Al+Mg and Al+Si above 3 L_D, recomputed from the truth numbers (S, B -> L_D)
    reg7 = t["regions"][6]["detectability"]["conflicts"]
    ld = {n: 2.71 + 4.65 * math.sqrt(reg7[n]["background"]) for n in ("sum_Al_Ka+Mg_Ka", "sum_Al_Ka+Si_Ka")}
    r["region7_signal_over_L_D"] = {n: reg7[n]["signal_counts"] / ld[n] for n in ld}
    r["region7_above_3_L_D"] = bool(all(v >= 3 for v in r["region7_signal_over_L_D"].values()))
    # region 8: the registered K2 criterion on the data
    k2 = t["regions"][7]["k2"]
    sl = slice(112, 128)
    dsp = data[:, sl].sum(axis=(0, 1)).astype(np.float64)
    axis = xm.Axis(4096, 5.0, 95.6)
    nm_, _ = net_sigma_data(dsp, axis, 1.2536); ns_, _ = net_sigma_data(dsp, axis, 1.7397)
    wf = k2["window_method_factor_net_ratio_over_true_count_ratio"]
    R_true = k2["absorption_free_counts"]["Mg_Ka"] / k2["absorption_free_counts"]["Si_Ka"]
    T = k2["mean_effective_transmission"]
    t_ratio = 1.0 if FAULT == "k2" else T["Mg_Ka"] / T["Si_Ka"]
    R_obs = nm_ / ns_
    pull_corr = (R_obs / wf / t_ratio / R_true - 1) / k2["sigma_total_rel"]
    pull_unc = (R_obs / wf / R_true - 1) / k2["sigma_count_rel_Mg_over_Si_window_method"]
    r["k2"] = {"sigma_count_rel": k2["sigma_count_rel_Mg_over_Si_window_method"], "sigma_count_le_1.5pct": k2["sigma_count_rel_Mg_over_Si_window_method"] <= 0.015,
               "pull_corrected": pull_corr, "pull_uncorrected": pull_unc, "criterion_met": bool(abs(pull_corr) <= 2 and abs(pull_unc) >= 3)}
    r["pass"] = bool(ok and ok_t and s_hi / s_mid > 6.0 and r["region7_above_3_L_D"] and r["k2"]["sigma_count_le_1.5pct"] and r["k2"]["criterion_met"])


def net_sigma_data(spec, axis, e):
    W, net, bl, br, npk, (nl, nr) = xm.window_counts(spec, axis, e)
    return net, math.sqrt(W + (0.5 * npk / nl) ** 2 * bl + (0.5 * npk / nr) ** 2 * br)


def main():
    global FAULT
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--name", default="AlMgSi_4D_EDX")
    ap.add_argument("--truth", default="truth_edx.json")
    ap.add_argument("--mac", default=None)
    ap.add_argument("--fault", default=None)
    args = ap.parse_args()
    FAULT = args.fault
    d = args.dir
    mac = args.mac or os.environ.get("MAC_CSV") or os.path.join(HERE, "..", "..", "mac4DSTEM", "Resources", "Spectroscopy", "FFastMAC.csv")
    t, A = load_truth(d, args.truth)
    res = {}
    sigs, eds = s1(d, t, A, res)
    rows = s2(d, t, A, eds, res)
    if t["scan"]["nx"] * t["scan"]["ny"] < 100:      # the tiny fixture has too few counts for the statistical S2; informational there
        res["S2"]["pass"] = True; res["S2"]["note"] = "tiny fixture: informational only"
    t1(d, t, A, mac, res)
    t2(d, t, A, eds, res); t3(d, t, A, eds, res); t4(d, t, A, eds, res)
    if os.path.exists(os.path.join(d, "truth_edx_regmismatch.json")) and t["scan"]["nx"] == 64:
        t5(d, t, res, args)
    if os.path.exists(os.path.join(d, "truth_edx_ladder.json")) and t["scan"]["nx"] == 64:
        t6(d, res)
    ok = all(v.get("pass", True) for v in res.values())
    if not args.fault:
        json.dump({"summary": res, "S2_rows": rows}, open(os.path.join(d, "check_edx_result.json"), "w"), indent=1, default=str)
    brief = {k: v.get("pass") for k, v in res.items()}
    print(json.dumps(res, indent=1, default=str) if not args.fault else json.dumps(brief))
    print("ALL PASS" if ok else "FAIL " + ",".join(k for k, v in res.items() if not v.get("pass", True)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
