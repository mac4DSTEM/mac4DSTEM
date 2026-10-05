#!/usr/bin/env python3
"""tools/demo-edx/check_edx.py — S1 / S2 checks of the simulated dataset (needs rsciio + h5py + numpy; no scipy).

S1  rsciio's digitalmicrograph reader returns the arrays the generator wrote (SHA-256 of C-order bytes in truth_edx.json),
    and the .hspy pair / single-file variant equal them.
S2  per recipe, window-method line counts from the summed EDS spectrum recover the model's expected counts within exact
    Poisson 95 % intervals:  (a) peak-window total vs the exact Poisson interval of its expected value;
    (b) window NET counts, z-score with the propagated Poisson variance;  (c) line ratio to Al Ka by the exact conditional
    binomial interval;  (d) whole-spectrum and 4D totals per recipe.
    Window method (xray_model.window_counts): peak = line +- 1 FWHM; background = mean of two side windows
    [E-2.5F,E-1.5F) and [E+1.5F,E+2.5F) scaled to the peak width.
Usage: check_edx.py <dir> [--name AlMgSi_4D_EDX]
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
_lg = np.frompyfunc(math.lgamma, 1, 1)


def lgamma(x):
    return _lg(np.asarray(x, dtype=np.float64)).astype(np.float64)


def poisson_tails(k, mu):
    """(P(X<=k), P(X>=k)) for X ~ Poisson(mu), exact, in float64 via log-pmf sums."""
    if mu <= 0:
        return (1.0, 1.0 if k == 0 else 0.0)
    hi = int(max(k, mu) + 12 * math.sqrt(max(k, mu) + 1) + 20)
    j = np.arange(0, hi + 1, dtype=np.float64)
    logp = j * math.log(mu) - mu - lgamma(j + 1)
    p = np.exp(logp)
    c = np.cumsum(p)
    kk = int(k)
    return float(c[min(kk, hi)]), float(1.0 - (c[kk - 1] if kk >= 1 else 0.0))


def binom_tails(k, n, p):
    j = np.arange(0, n + 1, dtype=np.float64)
    logp = math.lgamma(n + 1) - lgamma(j + 1) - lgamma(n - j + 1) + j * math.log(p) + (n - j) * math.log1p(-p)
    pm = np.exp(logp)
    c = np.cumsum(pm)
    kk = int(k)
    return float(c[kk]), float(1.0 - (c[kk - 1] if kk >= 1 else 0.0))


def inside(tails, alpha):
    lo, hi = tails
    return lo >= alpha / 2 and hi >= alpha / 2


def sha(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--name", default="AlMgSi_4D_EDX")
    ap.add_argument("--truth", default="truth_edx.json")
    args = ap.parse_args()
    d = args.dir
    truth = json.load(open(os.path.join(d, args.truth)))
    res = {"S1": {}, "S2": {}}
    ok_all = True

    # ---------------- S1: rsciio reads the .dm4 back ----------------
    from rsciio.digitalmicrograph import file_reader
    sigs = file_reader(os.path.join(d, truth["files"]["dm4"]))
    by = {s["metadata"]["General"]["title"]: s for s in sigs}
    sc = truth["scan"]; nx, ny = sc["nx"], sc["ny"]
    nch = truth["edx"]["channels"]
    exp_hash = truth["array_sha256_of_written_arrays_C_order"]
    s1 = res["S1"]
    s1["objects_rsciio"] = {k: [list(v["data"].shape), str(v["data"].dtype)] for k, v in by.items()}
    diff = by["Diffraction SI"]["data"]
    eds_raw = by["EDS SI"]["data"]                      # rsciio: (nch, ny, nx), energy slowest
    eds = np.ascontiguousarray(eds_raw.transpose(1, 2, 0))
    s1["diffraction_shape_is_ny_nx_qy_qx"] = diff.shape[:2] == (ny, nx)
    s1["eds_raw_shape_is_nch_ny_nx"] = tuple(eds_raw.shape) == (nch, ny, nx)
    s1["sha_diffraction_equal"] = sha(diff) == exp_hash["diffraction_ny_nx_qy_qx_float32"]
    s1["sha_eds_equal"] = sha(eds) == exp_hash["eds_ny_nx_nch_uint32"]
    s1["sha_haadf_equal"] = sha(by["HAADF Image"]["data"]) == exp_hash["haadf_ny_nx_float32"]
    s1["sha_survey_equal"] = sha(by["ADF Image (SI Survey)"]["data"]) == exp_hash["survey_uint16"]
    s1["eds_sum_equals_truth_total"] = int(eds.astype(np.int64).sum()) == truth["totals_written"]["eds_counts"]
    s1["diffraction_sum_equals_truth_total"] = float(diff.astype(np.float64).sum()) == truth["totals_written"]["diffraction_counts"]
    ax = {a["name"]: a for a in by["EDS SI"]["axes"]}
    s1["energy_axis"] = {"scale_keV": float(by["EDS SI"]["axes"][0]["scale"]), "offset_keV": float(by["EDS SI"]["axes"][0]["offset"]),
                         "units": by["EDS SI"]["axes"][0]["units"]}
    s1["energy_axis_matches_truth"] = (abs(s1["energy_axis"]["scale_keV"] - truth["edx"]["dispersion_eV"] / 1000) < 1e-7
                                       and abs(s1["energy_axis"]["offset_keV"] - truth["edx"]["energy_offset_keV"]) < 1e-6)
    om = by["EDS SI"]["original_metadata"]
    s1["meta_signal_xray"] = by["EDS SI"]["metadata"]["Signal"]["signal_type"] == "EDS_TEM"
    # hspy pair + single file
    if os.path.exists(os.path.join(d, args.name + "_EDS.hspy")):
        import h5py
        with h5py.File(os.path.join(d, args.name + "_EDS.hspy")) as f:
            e2 = f["Experiments/__unnamed__/data"][()]
        with h5py.File(os.path.join(d, args.name + "_4D.hspy")) as f:
            c2 = f["Experiments/__unnamed__/data"][()]
        with h5py.File(os.path.join(d, args.name + "_single.h5")) as f:
            e3, c3, sv3, rect3 = f["eds"][()], f["diffraction"][()], f["survey"][()], f["scan/rect"][()]
        s1["hspy_eds_equals_dm4"] = bool(np.array_equal(e2, eds)) and e2.shape == (ny, nx, nch)
        s1["hspy_4d_equals_dm4"] = bool(np.array_equal(c2, diff.astype(np.int32))) and c2.shape == (ny, nx) + diff.shape[2:]
        s1["single_equals_dm4"] = bool(np.array_equal(e3, eds) and np.array_equal(c3, diff.astype(np.int32))
                                       and np.array_equal(sv3, by["ADF Image (SI Survey)"]["data"]))
        from rsciio.hspy import file_reader as hs
        h1 = hs(os.path.join(d, args.name + "_EDS.hspy"))[0]; h2 = hs(os.path.join(d, args.name + "_4D.hspy"))[0]
        s1["rsciio_hspy_reads_pair"] = (h1["data"].shape == (ny, nx, nch) and h2["data"].shape == diff.shape
                                        and np.array_equal(h1["data"], eds) and np.array_equal(h2["data"], diff.astype(np.int32)))
        s1["hspy_energy_axis"] = {"scale_eV": h1["axes"][2]["scale"], "offset_eV": h1["axes"][2]["offset"], "signal_type": h1["metadata"]["Signal"].get("signal_type")}
    r = truth["edx"]["rect_survey_pixels_top_left_bottom_right"]
    s1["rect_aspect_equals_scan_aspect"] = abs((r[3] - r[1]) / (r[2] - r[0]) - nx / ny) < 1e-9
    s1["pass"] = all(v for k, v in s1.items() if k.startswith(("sha", "eds_sum", "diffraction_s", "hspy_eds", "hspy_4d", "single", "rsciio_hspy", "energy_axis_m", "meta_", "eds_raw", "diffraction_shape", "rect_aspect")) and isinstance(v, bool))
    ok_all &= s1["pass"]

    # ---------------- S2 ----------------
    sc2 = res["S2"]
    e = truth["edx"]
    axis = xm.Axis(nch, e["dispersion_eV"], e["origin_channel"])
    names = truth["recipe_names_in_map_order"]
    rmap = np.array(truth["recipe_map"])
    tmap = np.array(truth["thickness_map"])
    cube4 = diff
    rows = []
    for ri, r in enumerate(names):
        mask = rmap == ri
        npx = int(mask.sum())
        if npx == 0:
            continue
        spec = xm.edx_spec(r)
        base, stray, tr = xm.base_spectrum(spec, axis)
        tsum_expected = float(tmap[mask].sum())
        exp_spec = tsum_expected * base + npx * stray
        data_spec = eds[mask].sum(axis=0).astype(np.float64)
        # (d) totals
        tot_d, tot_e = float(data_spec.sum()), float(exp_spec.sum())
        rows.append({"recipe": r, "kind": "total_eds", "line": "all", "data": tot_d, "expected": tot_e,
                     "p95": inside(poisson_tails(tot_d, tot_e), 0.05), "p999": inside(poisson_tails(tot_d, tot_e), 0.001)})
        # truth totals vs the written file
        rows.append({"recipe": r, "kind": "truth_total_equals_written", "line": "all", "data": tot_d,
                     "expected": truth["recipes"][r]["realised_total_eds_counts"],
                     "p95": tot_d == truth["recipes"][r]["realised_total_eds_counts"], "p999": tot_d == truth["recipes"][r]["realised_total_eds_counts"]})
        # 4D total vs the model mean: only the base pattern means are unknown here -> use the recipe's own truth sum when
        # available; the checker compares data to the generator's truth realised total instead
        rows.append({"recipe": r, "kind": "truth_total_equals_written_4d", "line": "all", "data": float(cube4[mask].astype(np.float64).sum()),
                     "expected": truth["recipes"][r]["realised_total_4d_counts"],
                     "p95": float(cube4[mask].astype(np.float64).sum()) == truth["recipes"][r]["realised_total_4d_counts"],
                     "p999": float(cube4[mask].astype(np.float64).sum()) == truth["recipes"][r]["realised_total_4d_counts"]})
        wd, we = {}, {}
        for el, ln in LINES:
            en = xm.LINES[el][ln][0]
            if en > axis.centre[-1] - 0.5:
                continue
            wd[(el, ln)] = xm.window_counts(data_spec, axis, en)
            we[(el, ln)] = xm.window_counts(exp_spec, axis, en)
        for (el, ln), (W, net, bl, br, npk, (nl, nr)) in wd.items():
            We, nete, ble, bre = we[(el, ln)][:4]
            t = poisson_tails(W, We)
            sig2 = We + (0.5 * npk / nl) ** 2 * ble + (0.5 * npk / nr) ** 2 * bre
            z = (net - nete) / math.sqrt(sig2) if sig2 > 0 else 0.0
            name = f"{el}_{ln}"
            gtruth = truth["recipes"][r]["lines"].get(name, {}).get("gaussian_counts", 0.0) * tsum_expected
            # everything the model puts under that line, not only the sample's own Gaussian: stray Cu K and Si internal fluorescence
            gtruth += truth["recipes"][r]["stray_expected_total_counts"].get(name, 0.0)
            if name == "Si_Ka":
                gtruth += truth["recipes"][r]["si_internal_Ka_counts_per_pixel_at_t1"] * tsum_expected
            rows.append({"recipe": r, "kind": "window_total", "line": name, "data": W, "expected": We,
                         "p95": inside(t, 0.05), "p999": inside(t, 0.001)})
            rows.append({"recipe": r, "kind": "window_net_z", "line": name, "data": net, "expected": nete, "z": z,
                         "p95": abs(z) < 1.96, "p999": abs(z) < 3.29,
                         "net_expected_over_truth_line_counts": (nete / (0.9815 * gtruth)) if gtruth > 0 else None})
        wa, wae = wd[("Al", "Ka")][0], we[("Al", "Ka")][0]
        if wae >= 5:
            for (el, ln), (W, *_r) in wd.items():
                if (el, ln) == ("Al", "Ka"):
                    continue
                We = we[(el, ln)][0]
                if We < 1:
                    continue
                n_ = int(W + wa)
                p_ = We / (We + wae)
                t = binom_tails(int(W), n_, p_)
                rows.append({"recipe": r, "kind": "ratio_to_AlKa_binomial", "line": f"{el}_{ln}", "data": W / max(wa, 1), "expected": We / wae,
                             "p95": inside(t, 0.05), "p999": inside(t, 0.001)})
    sc2["n_checks"] = len(rows)
    n95 = sum(1 for x in rows if x["p95"]); n999 = sum(1 for x in rows if x["p999"])
    sc2["inside_95_fraction"] = n95 / len(rows)
    sc2["outside_99.9_count"] = len(rows) - n999
    byk = {}
    for x in rows:
        k = byk.setdefault(x["kind"], [0, 0, 0])
        k[0] += 1; k[1] += x["p95"]; k[2] += x["p999"]
    sc2["by_kind_n_in95_in999"] = byk
    sc2["outside_99.9"] = [x for x in rows if not x["p999"]]
    eff = [(x["recipe"], x["line"], x["net_expected_over_truth_line_counts"]) for x in rows
           if x["kind"] == "window_net_z" and x.get("net_expected_over_truth_line_counts")]
    sc2["window_net_over_truth_line_counts_noise_free"] = {f"{a}|{b}": round(c, 4) for a, b, c in eff if a in ("A", "precip_Q", "precip_endon_0", "precip_needle_0")}
    sc2["dose_mean_total_counts_per_pixel_by_recipe"] = {r: round(v["mean_total_counts_per_pixel_at_map_thickness"], 1) for r, v in truth["recipes"].items()}
    sc2["pass"] = (0.88 <= sc2["inside_95_fraction"]) and sc2["outside_99.9_count"] == 0
    ok_all &= sc2["pass"]
    json.dump({"summary": res, "S2_rows": rows}, open(os.path.join(d, "check_edx_result.json"), "w"), indent=1, default=str)
    print(json.dumps(res, indent=1, default=str))
    print("ALL PASS" if ok_all else "FAIL")
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
