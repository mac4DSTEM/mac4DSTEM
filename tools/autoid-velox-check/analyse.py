#!/usr/bin/env python3
"""Offline analysis of a `tools/autoid-velox-check/run.sh --out <dir>` run (lane L10, 2026-10-07): which picks are false and why, which of
Velox's elements are missed and why, and what three candidate rules would do to precision and recall on exactly this data.

    analyse.py <out dir> [<XRayLineData.swift>] [--dedupe]      (numpy only; the default line table is mac4DSTEM/Core/Spectroscopy/XRayLineData.swift)

Everything printed is computed from the per-file JSON and the pooled spectra the harness wrote. The rules are MEASUREMENTS, not changes: nothing here
touches the proposer. A threshold in a rule is named as illustrative: it was read off this one set of files (CLAUDE.md: a threshold is a property of
the dataset until measured on every dataset it will touch), so the quantity is printed beside it for the reader to judge."""
import glob, json, math, os, re, sys
from collections import Counter, defaultdict
import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith("--")]
out = args[0]
table_path = args[1] if len(args) > 1 else os.path.join(os.path.dirname(__file__), "../../mac4DSTEM/Core/Spectroscopy/XRayLineData.swift")
LINES = defaultdict(list)          # element -> [(name, energy, weight)]
for row in re.findall(r"^(\d+) (\w+) (\w+) ([\d.eE+-]+) ([\d.eE+-]+)$", open(table_path).read(), re.M):
    LINES[row[1]].append((row[2], float(row[3]), float(row[4])))
MN = 5.8987
def fwhm(e, r=130.0):
    v = 2.5 * (e - MN) * 1000 + r * r
    return math.sqrt(v) / 1000 if v > 0 else 0.1
FILES = []
for p in sorted(glob.glob(out + "/[0-9]*.json")):
    d = json.load(open(p)); d["spectrum"] = np.fromfile(p.replace(".json", ".spectrum.u64"), dtype="<u8").astype(float); d["id"] = os.path.basename(p)[:2]
    d["name"] = os.path.basename(d["file"]); d["fitTo"] = min(d["beamKeV"], 20.0, d["offsetKeV"] + d["scaleKeV"] * (d["channels"] - 1))
    FILES.append(d)
DUP = len(FILES)
if "--dedupe" in sys.argv:
    seen, kept = set(), []
    for d in FILES:                       # the same acquisition copied into two folders: same file name and the same pooled counts
        key = (d["name"], d["totalCounts"])
        if key not in seen: seen.add(key); kept.append(d)
    FILES = kept
    print(f"(--dedupe: {DUP - len(FILES)} copies of an already counted file dropped, {len(FILES)} kept)")
def prf(tp, picks, truth):
    return (tp / picks if picks else float("nan"), tp / truth if truth else float("nan"))
def fam(group): return group.split("_")[1][0]
def pct(x): return "n/a" if x != x else f"{100 * x:.1f} %"

# ---- 1. baseline
T = sum(len(f["truth"]) for f in FILES); P = sum(len(f["picks"]) for f in FILES); H = sum(len(set(f["picks"]) & set(f["truth"])) for f in FILES)
print(f"## 1. Baseline: {len(FILES)} files, velox elements {T}, app picks {P}, hits {H}")
print(f"precision {pct(H / P)}  recall {pct(H / T)}")
print(f"files with the exact set {sum(set(f['picks']) == set(f['truth']) for f in FILES)}; with every velox element found {sum(set(f['truth']) <= set(f['picks']) for f in FILES)}")
print(f"hits per file (median) {np.median([len(set(f['picks']) & set(f['truth'])) for f in FILES])}, picks per file (median) {np.median([len(f['picks']) for f in FILES])}, velox per file (median) {np.median([len(f['truth']) for f in FILES])}")

# ---- 2. false picks
def near_truth_line(f, e, exclude):
    tol = 1.5 * fwhm(e)
    best = None
    for t in f["truth"]:
        if t == exclude: continue
        for (n, le, w) in LINES[t]:
            if w >= 0.05 and abs(le - e) <= tol and le < f["fitTo"] and (best is None or abs(le - e) < best[0]): best = (abs(le - e), f"{t} {n}")
    return best[1] if best else None
def sum_energy(f, e):
    par = sorted(set(f["truth"]) | set(f["picks"]))
    al = {p: [l[1] for l in LINES[p] if l[0] in ("Ka", "La", "Ma") and l[1] < f["fitTo"]] for p in par}
    for i, a in enumerate(par):
        for b in par[i:]:
            for ea in al[a][:1]:
                for eb in al[b][:1]:
                    if abs(ea + eb - e) <= 0.06: return f"{a}+{b}"
    return None
rows = []
for f in FILES:
    for c in f["candidates"]:
        if c["picked"] and c["element"] not in f["truth"]:
            rows.append((f, c, near_truth_line(f, c["energy"], c["element"]), sum_energy(f, c["energy"])))
print(f"\n## 2. False picks: {len(rows)}")
by = defaultdict(list)
for r in rows: by[r[1]["element"]].append(r)
print("element | n | groups | alpha energies (keV) | median net/L_D | beside a truth element's line | on a sum energy")
for el, rs in sorted(by.items(), key=lambda kv: -len(kv[1]))[:12]:
    g = Counter(r[1]["group"] for r in rs).most_common(3); en = sorted(r[1]["energy"] for r in rs)
    nt = Counter(r[2] for r in rs if r[2]).most_common(2); se = Counter(r[3] for r in rs if r[3]).most_common(2)
    print(f"{el} | {len(rs)} | {', '.join(f'{k} x{v}' for k, v in g)} | {en[0]:.2f}-{en[-1]:.2f} | {np.median([r[1]['significance'] for r in rs]):.2f} | {len([r for r in rs if r[2]])} {nt} | {len([r for r in rs if r[3]])} {se}")
fc = Counter(fam(r[1]["group"]) for r in rows)
print("by family:", dict(fc), "| significance below 2:", sum(r[1]["significance"] < 2 for r in rows), "| a sum-peak conflict on the pick:", sum(bool(r[1]["sumQuestion"]) for r in rows), "| grid/FIB conflict:", sum(any(k != "sumPeak" for k in r[1]["conflicts"]) for r in rows))
print("beside any truth element's line (within 1.5 FWHM):", sum(bool(r[2]) for r in rows), "| on a sum of two truth/picked alphas:", sum(bool(r[3]) for r in rows), "| neither:", sum((not r[2]) and (not r[3]) for r in rows))
print("false picks with Z >= 89:", sum(r[1]["z"] >= 89 for r in rows), "| K-family false picks:", fc["K"], "| L:", fc["L"], "| M:", fc["M"])

# ---- 3. misses
print(f"\n## 3. Misses (velox elements the app did not pick): {T - H}")
reasons = Counter(); mrows = defaultdict(list)
for f in FILES:
    cands = {c["element"]: c for c in f["candidates"]}
    for t in f["truth"]:
        if t in f["picks"]: continue
        c = cands.get(t)
        if c is None: why = "not tested (no candidate: line below 0.45 keV, or none in the table)"
        elif c["sumQuestion"] and c["proposed"]: why = "held back as a sum-peak question"
        elif c["proposed"] and c["beside"]: why = "proposed, shown as an excess beside a listed line"
        elif c["proposed"]: why = "proposed but not picked (other)"
        elif c["net"] > c["lc"]: why = "possible only (L_C < net < L_D)"
        else: why = "below the critical level"
        reasons[why] += 1; mrows[t].append((f["name"], why, c))
for k, v in reasons.most_common(): print(f"  {v:3d}  {k}")
print("element | n missed | of n in truth | reasons | group, median net/L_D (where a candidate)")
tc = Counter(t for f in FILES for t in f["truth"])
for el, rs in sorted(mrows.items(), key=lambda kv: -len(kv[1]))[:12]:
    cs = [r[2] for r in rs if r[2]]
    print(f"{el} | {len(rs)} | {tc[el]} | {dict(Counter(r[1].split(' (')[0] for r in rs))} | {Counter(c['group'] for c in cs).most_common(1)} {np.median([c['significance'] for c in cs]) if cs else float('nan'):.2f}")

# ---- 4. rules
def score(selector):
    tp = pk = 0
    for f in FILES:
        sel = {c["element"] for c in f["candidates"] if selector(f, c)}
        pk += len(sel); tp += len(sel & set(f["truth"]))
    return prf(tp, pk, T), pk, tp
def line(label, selector):
    (p, r), pk, tp = score(selector); print(f"{label:<64s} picks {pk:4d} hits {tp:3d} precision {pct(p):>7s} recall {pct(r):>7s}")
print("\n## 4. Rules, measured on this set (nothing in the app changed)")
base = lambda f, c: c["picked"]
line("baseline: what the room picks", base)
# Rule A: an L or M pick needs a K-less reason: its element's K alpha is out of the fit range.
def k_less(f, c):
    ka = [l[1] for l in LINES[c["element"]] if l[0] == "Ka"]
    return not ka or ka[0] >= f["fitTo"]
ruleA = lambda f, c: c["picked"] and (fam(c["group"]) == "K" or k_less(f, c))
line("A. L/M pick only if the element's K alpha is above the fit range", ruleA)
line("A'. K lines only (no L or M pick at all)", lambda f, c: c["picked"] and fam(c["group"]) == "K")
line("B. Z >= 89 never", lambda f, c: c["picked"] and c["z"] < 89)
# significance curve (quantity, not a verdict)
for s in (1.0, 1.5, 2, 3, 5, 10):
    line(f"D. net / L_D at least {s:g} (illustrative)", lambda f, c, s=s: c["picked"] and c["significance"] >= s)
tru = [c["significance"] for f in FILES for c in f["candidates"] if c["picked"] and c["element"] in f["truth"]]
fal = [c["significance"] for f in FILES for c in f["candidates"] if c["picked"] and c["element"] not in f["truth"]]
q = lambda a: ", ".join(f"{np.percentile(a, p):.1f}" for p in (10, 25, 50, 75, 90))
print(f"net / L_D of picks, percentiles 10/25/50/75/90: hits {q(tru)} | false {q(fal)}")

# ---- C: the beta-peak check on the pooled spectrum
def window(f, e, half):
    s, off, sc = f["spectrum"], f["offsetKeV"], f["scaleKeV"]
    i0, i1 = int(round((e - half - off) / sc)), int(round((e + half - off) / sc)); i0 = max(i0, 0); i1 = min(i1, len(s) - 1)
    return i0, i1
def net_at(f, e):
    w = fwhm(e); i0, i1 = window(f, e, 0.75 * w); s = f["spectrum"]
    n = i1 - i0 + 1; S = s[i0:i1 + 1].sum()
    a0, a1 = window(f, e - 1.6 * w, 0.4 * w); b0, b1 = window(f, e + 1.6 * w, 0.4 * w)
    nl = (a1 - a0 + 1) + (b1 - b0 + 1); F = s[a0:a1 + 1].sum() + s[b0:b1 + 1].sum()
    B = F / nl
    return S - B * n, math.sqrt(max(S, 1) + (n / nl) ** 2 * max(F, 1))
def beta_check(f, c):
    """rho = (net at the strongest secondary line / net at the alpha line) / (table ratio); None when no secondary line is in range or visible."""
    fm = fam(c["group"]); lines = [l for l in LINES[c["element"]] if l[0][0] == fm]
    al = [l for l in lines if l[0] == c["group"].split("_")[1]]
    if not al: return None
    w_a = al[0][2] or 1.0
    sec = [l for l in lines if l[0] != al[0][0] and l[2] >= 0.05 and abs(l[1] - c["energy"]) > 1.5 * fwhm(c["energy"]) and 0.45 <= l[1] < f["fitTo"]]
    if not sec: return None
    # CLEAN lines only: another proposed element's line within 2.5 FWHM of the alpha or of the secondary would pollute the window sums
    # (the first version of this check lost 48 of 206 true picks to exactly that: Ni K-beta beside Cu K-alpha, In L-beta beside Ag L).
    others = [(l[1]) for o in f["candidates"] if o["proposed"] and o["element"] != c["element"] for l in LINES[o["element"]] if l[2] >= 0.03]
    clean = lambda e: not any(abs(x - e) <= 2.5 * fwhm(e) for x in others)
    sec = [l for l in sec if clean(l[1])]
    if not sec or not clean(c["energy"]): return None
    sec.sort(key=lambda l: -l[2]); n, e, w = sec[0][0], sec[0][1], sec[0][2]
    na, sa = net_at(f, c["energy"]); nb, sb = net_at(f, e)
    exp = na * w / w_a
    if na <= 0 or exp / sb < 3: return None            # the secondary would not be visible even at the table's ratio
    return (nb / na) / (w / w_a), sb / na / (w / w_a), n
rho = {}
for f in FILES:
    for c in f["candidates"]:
        if c["proposed"]:
            r = beta_check(f, c)
            if r: rho[(f["id"], c["element"])] = r
def rho_sel(cut, include_held=False):
    return lambda f, c: ((c["picked"] or (include_held and c["proposed"] and c["sumQuestion"])) and
                         ((f["id"], c["element"]) not in rho or rho[(f["id"], c["element"])][0] >= cut))
hit = [rho[(f["id"], c["element"])][0] for f in FILES for c in f["candidates"] if c["picked"] and c["element"] in f["truth"] and (f["id"], c["element"]) in rho]
fls = [rho[(f["id"], c["element"])][0] for f in FILES for c in f["candidates"] if c["picked"] and c["element"] not in f["truth"] and (f["id"], c["element"]) in rho]
q2 = lambda a: ", ".join(f"{np.percentile(a, p):.2f}" for p in (10, 25, 50, 75, 90)) if a else "none"
print(f"\nC. beta-peak check: rho = (secondary / alpha, measured on the pooled spectrum) / (the line table's ratio); only where the secondary would be visible")
print(f"   checkable picks: hits {len(hit)} of {sum(1 for f in FILES for c in f['candidates'] if c['picked'] and c['element'] in f['truth'])}, false {len(fls)} of {len(rows)}")
print(f"   rho percentiles 10/25/50/75/90: hits {q2(hit)} | false {q2(fls)}")
for cut in (0.2, 0.35, 0.5):
    line(f"C. a checkable pick needs rho >= {cut:g} (illustrative)", rho_sel(cut))
line("C+A. beta check at 0.35 and rule A", lambda f, c: ruleA(f, c) and rho_sel(0.35)(f, c))
line("C+A+B. as above and Z < 89", lambda f, c: ruleA(f, c) and c["z"] < 89 and rho_sel(0.35)(f, c))
# release of sum-peak questions whose family is consistent
held = [(f, c) for f in FILES for c in f["candidates"] if c["proposed"] and c["sumQuestion"] and not c["picked"]]
ht = [(f, c) for f, c in held if c["element"] in f["truth"]]
print(f"\nHeld back as sum-peak questions: {len(held)} candidates, {len(ht)} of them velox elements ({len(held) - len(ht)} not).")
chk = [(f, c) for f, c in held if (f["id"], c["element"]) in rho]
print(f"   checkable by the beta check: {len(chk)}; velox elements among them {sum(c['element'] in f['truth'] for f, c in chk)}; rho >= 0.35: velox {sum(c['element'] in f['truth'] and rho[(f['id'], c['element'])][0] >= .35 for f, c in chk)}, other {sum(c['element'] not in f['truth'] and rho[(f['id'], c['element'])][0] >= .35 for f, c in chk)}")
def released(f, c):
    return c["picked"] or (c["proposed"] and c["sumQuestion"] and (f["id"], c["element"]) in rho and rho[(f["id"], c["element"])][0] >= 0.35)
ok_rho = lambda f, c: (f["id"], c["element"]) not in rho or rho[(f["id"], c["element"])][0] >= 0.35
line("E. C+A, plus every sum-peak question whose beta is there (rho >= 0.35)", lambda f, c: released(f, c) and ruleA(f, dict(c, picked=True)) and ok_rho(f, c))

# ---- by family, and the two rules the false-pick table points at
print("\nPicks by line family (the room's own picks):")
for fm in "KLM":
    ps = [(f, c) for f in FILES for c in f["candidates"] if c["picked"] and fam(c["group"]) == fm]
    hs = [1 for f, c in ps if c["element"] in f["truth"]]
    print(f"   {fm}: picks {len(ps)}, hits {len(hs)}, precision {pct(len(hs) / len(ps)) if ps else 'n/a'}")
def nearer_k(f, c):
    """An L or M pick that sits within 1.5 FWHM of a K alpha another proposed candidate of the file carries (a K reading explains the peak)."""
    if fam(c["group"]) == "K": return False
    tol = 1.5 * fwhm(c["energy"])
    return any(o["proposed"] and o["element"] != c["element"] and fam(o["group"]) == "K" and abs(o["energy"] - c["energy"]) <= tol for o in f["candidates"])
line("H. prefer K: drop an L/M pick that sits on another proposed candidate's K alpha", lambda f, c: c["picked"] and not nearer_k(f, c))
for s in (2, 3):
    line(f"F. an L/M pick needs net / L_D >= {s} (K keeps the L_D bar; illustrative)", lambda f, c, s=s: c["picked"] and (fam(c["group"]) == "K" or c["significance"] >= s))
line("F+H. L/M need net / L_D >= 3 and prefer K", lambda f, c: c["picked"] and not nearer_k(f, c) and (fam(c["group"]) == "K" or c["significance"] >= 3))
line("F+H+A. as above, and an L/M pick needs a K-less reason", lambda f, c: c["picked"] and not nearer_k(f, c) and (fam(c["group"]) == "K" or (c["significance"] >= 3 and k_less(f, c))))

# ---- sum-peak holds: what releasing the strong ones would do, and the recall ceiling of the proposer's own bar
print("\nI. Release of sum-peak questions by net / L_D alone (illustrative thresholds; the quantity is the finding):")
htr = [c["significance"] for f, c in held if c["element"] in f["truth"]]; hfa = [c["significance"] for f, c in held if c["element"] not in f["truth"]]
print(f"   held velox elements: {len(htr)}, net / L_D percentiles 10/25/50/75/90: {q(htr)} | held others: {len(hfa)}: {q(hfa)}")
for s in (3, 10, 30):
    line(f"I. picks plus held candidates with net / L_D >= {s}", lambda f, c, s=s: c["picked"] or (c["proposed"] and c["sumQuestion"] and c["significance"] >= s))
ceil = sum(1 for f in FILES for t in f["truth"] if any(c["element"] == t and c["proposed"] for c in f["candidates"]))
print(f"\nRecall ceiling at the proposer's own L_D bar (every proposed candidate picked, none held back): {ceil} of {T} = {pct(ceil / T)}")
print(f"Velox elements the proposer cannot test at all (no candidate): {sum(1 for f in FILES for t in f['truth'] if not any(c['element'] == t for c in f['candidates']))}, by element: {dict(Counter(t for f in FILES for t in f['truth'] if not any(c['element'] == t for c in f['candidates'])))}")

# ---- the three candidate rules together (each leg illustrative; see the report's pre-registration draft)
def combined(f, c):
    held_strong = c["proposed"] and c["sumQuestion"] and not c["picked"] and c["significance"] >= 10
    if not (c["picked"] or held_strong) or c["z"] >= 89: return False
    if fam(c["group"]) != "K" and (c["significance"] < 3 or nearer_k(f, c)): return False
    return True
print()
line("R1+R2+R3: Z < 89; L/M need net / L_D >= 3 and not on a K alpha; strong sum-peak holds released (>= 10)", combined)
line("R1+R2 only (no release of sum-peak holds)", lambda f, c: c["picked"] and c["z"] < 89 and (fam(c["group"]) == "K" or (c["significance"] >= 3 and not nearer_k(f, c))))
line("R1 alone: Z < 89 and prefer K (no recall cost expected)", lambda f, c: c["picked"] and c["z"] < 89 and not nearer_k(f, c))
lmh = [c["significance"] for f in FILES for c in f["candidates"] if c["picked"] and fam(c["group"]) != "K" and c["element"] in f["truth"]]
lmf = [c["significance"] for f in FILES for c in f["candidates"] if c["picked"] and fam(c["group"]) != "K" and c["element"] not in f["truth"]]
print(f"net / L_D of L/M picks, percentiles 10/25/50/75/90: hits ({len(lmh)}) {q(lmh)} | false ({len(lmf)}) {q(lmf)}")
