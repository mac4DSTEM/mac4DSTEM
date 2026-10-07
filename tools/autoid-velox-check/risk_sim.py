#!/usr/bin/env python3
"""WP4b T-S (2026-10-07): the seeded risk simulator. Truth by construction; 200 kV; the owner's axis (offset -1.93221348 keV, 20 eV/channel, 4096 channels);
130 eV at Mn K-alpha; an Al matrix (continuum + Al K-alpha/K-beta + the Al+Al pile-up peak) plus the planted elements; Poisson-drawn.
Needs numpy (the py4dstem env: ~/miniconda3/envs/py4dstem/bin/python). Writes `main --ladder` input: `<nn>.spectrum.u64` + `<nn>.meta.json`.

    risk_sim.py calib <dir>                         single-element spectra (each of the 9 elements alone on Al) to measure L_D per element
    risk_sim.py ld <harness --ladder --out dir> <ld.json>   reads the calibration run: L_D (counts of the alpha-line area) per element
    risk_sim.py gen <dir> <ld.json>                 the registered cases: true pairs and ghosts

What is planted. The WHOLE family of each planted element, from the app's own line table (mac4DSTEM/Core/Spectroscopy/XRayLineData.swift, which is eXSpy's
table: energies and weights relative to the family's alpha line): K family (Ka, Kb) for the K element, every L line (La, Lb1.., Lg.., Ll, Ln) for the L element,
each line at area = alpha-area x table weight, as a unit-area Gaussian of the app's width law, integrated over each channel. The M family, Si-escape peaks and
the K lines of the L elements (Hf Ka 55.8 keV ...) are NOT planted (stated limitation). The registered "L/M : K line-area ratio" is read as ALPHA area : ALPHA
area, the quantity the proposer's `net` measures (group net = the alpha line's fitted amplitude).

Doses. The weaker line's alpha area is k x L_D of that line (L_D measured by `calib` on the same matrix through the app's proposer): k = 6 ("high": clearly above
detection) and k = 1.5 ("low": near it); at ratio 1 the common area is k x the larger of the two L_D. Ghosts: the K element alone, its alpha area the largest K area
planted in any of its pairs at the high dose (ratio 0.3), i.e. the case most likely to leave a false L/M pick beside it.
Matrix. Al K-alpha alpha area 20000 counts (K-beta by table weight), continuum total (axis, E > 0.05 keV) 0.25 x that (the demo-edx ratio, 8 : 32 counts/px),
Kramers shape (E0 - E)/E x the demo-edx detector efficiency, E0 = 200 keV, Al+Al pile-up peak at 0.8 % of the Al K-alpha area (demo ladder, 10 counts/px region)."""
import json, math, os, re, sys, glob
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "../demo-edx"))
import xray_model as xm          # Axis, fwhm_kev, detector_efficiency (the demo-edx forward model)

TABLE = os.path.join(HERE, "../../mac4DSTEM/Core/Spectroscopy/XRayLineData.swift")
LINES = {}
for z, el, name, e, w in re.findall(r"^(\d+) (\w+) (\w+) ([\d.eE+-]+) ([\d.eE+-]+)$", open(TABLE).read(), re.M):
    LINES.setdefault(el, []).append((name, float(e), float(w)))
N, DISP_EV, OFFSET_KEV, E0 = 4096, 20.0, -1.93221348, 200.0
ORIGIN = -OFFSET_KEV / (DISP_EV / 1000.0)
AXIS = xm.Axis(N, DISP_EV, ORIGIN)
AL_KA_AREA, CONT_FRACTION, PILEUP_FRACTION, RES = 20000.0, 0.25, 0.008, 130.0
PAIRS = [("Hf", "La", "Cu"), ("Ta", "La", "Cu"), ("Pt", "La", "Ga"), ("Pb", "La", "As"), ("Ag", "La", "Ar")]   # (L element, its alpha, K element)
RATIOS, DOSES = [0.3, 1.0, 3.0], {"low": 1.5, "high": 6.0}
GHOSTS = ["Cu", "Ga", "As", "Ar"]
SEED0 = 20261007_000

def family_lines(el, fam):
    return [(n, e, w) for n, e, w in LINES[el] if n.startswith(fam) and AXIS.centre[0] < e < min(E0, AXIS.centre[-1])]

def line_spectrum(el, fam, alpha_area):
    out = np.zeros(N); planted = {}
    for n, e, w in family_lines(el, fam):
        a = alpha_area * w
        if a > 0:
            out += a * AXIS.gaussian(e, xm.fwhm_kev(e, RES)); planted[f"{el}_{n}"] = {"keV": e, "area": a}
    return out, planted

def matrix():
    out = np.zeros(N); planted = {}
    s, p = line_spectrum("Al", "K", AL_KA_AREA); out += s; planted.update(p)
    e = AXIS.centre; shape = np.where(e > 0.05, (E0 - e) / np.maximum(e, 1e-9) * xm.detector_efficiency(e), 0.0)
    out += shape * (CONT_FRACTION * AL_KA_AREA / shape.sum())
    pile = PILEUP_FRACTION * AL_KA_AREA
    out += pile * AXIS.gaussian(2 * 1.4865, xm.fwhm_kev(2 * 1.4865, RES)); planted["sum_Al_Ka+Al_Ka"] = {"keV": 2 * 1.4865, "area": pile}
    return out, planted

def write(dir_, i, expected, seed, meta):
    spec = np.random.default_rng(seed).poisson(expected).astype("<u8")
    spec.tofile(os.path.join(dir_, f"{i:02d}.spectrum.u64"))
    meta = dict(meta, offsetKeV=OFFSET_KEV, scaleKeV=DISP_EV / 1000.0, beamKeV=E0, seed=seed, totalCounts=int(spec.sum()), set="T-S")
    json.dump(meta, open(os.path.join(dir_, f"{i:02d}.meta.json"), "w"), indent=1)

def planted_ids(L, K):
    return [(L, "La", "L"), (K, "Ka", "K")]

def build(parts):
    """parts: [(element, family letter, alpha area)] on the Al matrix -> (expected spectrum, planted lines)"""
    exp, planted = matrix()
    for el, fam, area in parts:
        s, p = line_spectrum(el, fam, area); exp = exp + s; planted.update(p)
    return exp, planted

def calib(out):
    os.makedirs(out, exist_ok=True); i = 0
    for el, fam in sorted({(L, "L") for L, _, _ in PAIRS} | {(K, "K") for _, _, K in PAIRS}):
        exp, planted = build([(el, fam, 3000.0)])
        write(out, i, exp, SEED0 + 900 + i, {"region": i, "recipe": "calib", "dose": None, "truth": ["Al", el], "calibElement": el, "calibFamily": fam, "calibAlphaArea": 3000.0, "planted": planted}); i += 1
        print(i - 1, el, fam)

def ld(run_dir, out_json):
    table = {}
    for p in sorted(glob.glob(os.path.join(run_dir, "ladder*.json"))):
        d = json.load(open(p)); m = d["meta"]; el, fam = m["calibElement"], m["calibFamily"]
        want = f"{el}_{'La' if fam == 'L' else 'Ka'}"
        c = [x for x in d["candidates"] if x["element"] == el][0]
        assert c["group"] == want, (el, c["group"], "the element's best group is not the planted alpha group")
        table[el] = {"alphaGroup": want, "ld": c["ld"], "net": c["net"], "plantedAlphaArea": m["calibAlphaArea"], "significance": c["significance"]}
        print(el, table[el])
    json.dump(table, open(out_json, "w"), indent=1)

def gen(out, ld_json):
    LD = {k: v["ld"] for k, v in json.load(open(ld_json)).items()}
    os.makedirs(out, exist_ok=True); i = 0; k_hi03 = {}
    def areas(L, K, r, k):
        if r < 1: aL = k * LD[L]; aK = aL / r
        elif r > 1: aK = k * LD[K]; aL = r * aK
        else: aL = aK = k * max(LD[L], LD[K])
        return aL, aK
    for L, _, K in PAIRS:
        for r in RATIOS:
            for dose, k in DOSES.items():
                aL, aK = areas(L, K, r, k)
                if r == 0.3 and dose == "high": k_hi03[K] = max(k_hi03.get(K, 0.0), aK)
                exp, planted = build([(L, "L", aL), (K, "K", aK)])
                write(out, i, exp, SEED0 + i, {"region": i, "case": "pair", "pair": f"{L} La + {K} Ka", "L": L, "K": K, "ratio": r, "doseLabel": dose, "dose": f"{L}+{K} r{r} {dose}",
                      "truth": ["Al", L, K], "alphaAreaL": aL, "alphaAreaK": aK, "plantedSignificanceL": aL / LD[L], "plantedSignificanceK": aK / LD[K], "ld": LD, "planted": planted}); i += 1
    for K in GHOSTS:
        aK = k_hi03[K]; exp, planted = build([(K, "K", aK)])
        write(out, i, exp, SEED0 + i, {"region": i, "case": "ghost", "K": K, "L": None, "doseLabel": "high", "dose": f"{K} ghost", "truth": ["Al", K], "alphaAreaK": aK,
              "plantedSignificanceK": aK / LD[K], "ld": LD, "planted": planted}); i += 1
    print(f"{i} spectra in {out}")

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "calib": calib(sys.argv[2])
    elif mode == "ld": ld(sys.argv[2], sys.argv[3])
    elif mode == "gen": gen(sys.argv[2], sys.argv[3])
    else: sys.exit(__doc__)
