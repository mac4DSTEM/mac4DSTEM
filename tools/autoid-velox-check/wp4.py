#!/usr/bin/env python3
"""WP4 report (lane L12, 2026-10-07): the registered Auto ID rules (ProposalRules R1-R3) measured against the owner's Velox element selections, split by
acquisition date (fit set <= 2026-05-31, hold-out >= 2026-06-01), beside the registration's predictions; H3 on the demo-edx dose ladder; H4 (Mg on the
Mg-richest 1 % of pixels). Reads what `run.sh --h4 --out <dir>` wrote (every <n>.json carries the picks of each rule set as the Swift implementation made
them: `configs`) and, for H3, `run.sh --ladder <ladder dir> --out <ladder out>`. numpy not needed.

    wp4.py <out dir> [<ladder out dir>] [--real <run.sh --h4 out dir>]

<out dir> is either a `run.sh` output or a `run.sh --replay <earlier out> --out <dir>` output (the current rule code re-selecting among the candidates an earlier
run recorded, for files that are not at hand). With --real, the acquisition date and the H4 diagnostic of a live run are joined in by (file name, pooled counts), and
the live run's candidates and picks are compared with the recorded ones."""
import glob, json, os, sys, math
from collections import Counter, defaultdict

argv = sys.argv[1:]; real = None
if "--real" in argv: i = argv.index("--real"); real = argv[i + 1]; del argv[i:i + 2]
out = argv[0]; ladder_out = argv[1] if len(argv) > 1 else None
CONFIGS = ["base", "R1", "R2", "R3", "R1R2", "R1R2R3"]
LABEL = {"base": "baseline (the proposer's own picks)", "R1": "R1 alone", "R2": "R2 alone", "R3": "R3 alone", "R1R2": "R1 + R2", "R1R2R3": "R1 + R2 + R3 (registered)"}
PRED = {"R1": (539 - 74, 0.396, 0.455), "R1R2": (363, 0.496, 0.446), "R1R2R3": (402, 0.515, 0.512)}   # registration: precision, recall on the 78 files
FIT_LAST, HOLD_FIRST = "2026-05-31", "2026-06-01"
pct = lambda x: "n/a" if x != x else f"{100 * x:.1f} %"

ALL = []
for p in sorted(glob.glob(out + "/[0-9]*.json")):
    d = json.load(open(p)); d["id"] = os.path.basename(p)[:2]; d["name"] = os.path.basename(d["file"]); ALL.append(d)
if real:
    live = {}
    for p in sorted(glob.glob(real + "/[0-9]*.json")):
        d = json.load(open(p)); live[(os.path.basename(d["file"]), d["totalCounts"])] = d
    joined = same = 0
    for d in ALL:
        l = live.get((d["name"], d["totalCounts"]))
        if not l: continue
        joined += 1
        for k in ("acquired", "acquiredSource", "h4"):
            if k in l: d[k] = l[k]
        # the live proposer run and the recorded one must agree, or the replay is not of the same proposer
        if l["picks"] == d["picks"] and all(abs(a["net"] - b["net"]) <= 1e-9 * max(1, abs(a["net"])) and a["element"] == b["element"] for a, b in zip(l["candidates"], d["candidates"])) \
                and l["configs"] == d["configs"]: same += 1
    print(f"live run joined to {joined} of {len(ALL)} recorded files; proposer picks, candidate nets and every rule set's picks identical in {same} of them")
seen, FILES = set(), []
for d in ALL:                       # the same acquisition copied into two folders: same file name and the same pooled counts
    k = (d["name"], d["totalCounts"])
    if k not in seen: seen.add(k); FILES.append(d)
print(f"files with a stored selection that the proposer scored: {len(ALL)}; distinct: {len(FILES)}")
def al_mg_si(d): t = set(d["truth"]); return {"Mg", "Al", "Si"} <= t and "C" not in t and "O" not in t
def date(d): return d.get("acquired")
src = Counter(d.get("acquiredSource", "?") for d in FILES)
print("acquisition date source (distinct files):", dict(src))
mism = [(d["name"], d["acquired"]) for d in FILES if d.get("acquiredSource") == "metadata" and any(c.isdigit() for c in d["name"]) and
        __import__("re").search(r"20\d{6}", d["name"]) and __import__("re").search(r"20\d{6}", d["name"]).group(0) != d["acquired"].replace("-", "")]
print(f"file-name date differs from the metadata date: {len(mism)} {mism[:6]}")
fit = [d for d in FILES if date(d) and date(d) <= FIT_LAST]
hold = [d for d in FILES if date(d) and date(d) >= HOLD_FIRST]
undated = [d for d in FILES if not date(d)]
print(f"split by acquisition date: fit set (<= {FIT_LAST}) {len(fit)} files, hold-out (>= {HOLD_FIRST}) {len(hold)} files, undated {len(undated)} (counted in the fit set: {len(undated)})")
fit += undated
print(f"hold-out files: Al-Mg-Si {sum(map(al_mg_si, hold))} of {len(hold)}; fit set: Al-Mg-Si {sum(map(al_mg_si, fit))} of {len(fit)}")
print("hold-out by date:", dict(Counter(date(d) for d in hold)))

def score(files, cfg):
    tp = pk = tr = 0
    for d in files:
        picks, truth = set(d["configs"][cfg]), set(d["truth"])
        pk += len(picks); tp += len(picks & truth); tr += len(truth)
    return pk, tp, tr
def table(title, files):
    print(f"\n### {title}: {len(files)} files")
    b = score(files, "base")
    print(f"truth elements {b[2]}")
    print("| rule set | picks | hits | precision | recall |"); print("|---|---|---|---|---|")
    for c in CONFIGS:
        pk, tp, tr = score(files, c)
        print(f"| {LABEL[c]} | {pk} | {tp} | {pct(tp / pk if pk else float('nan'))} | {pct(tp / tr if tr else float('nan'))} |")
table("all distinct files", FILES)
table("fit set", fit); table("hold-out (June 2026)", hold)
table("supplementary, NOT registered: Al-Mg-Si files", [d for d in FILES if al_mg_si(d)])
table("supplementary, NOT registered: every other file", [d for d in FILES if not al_mg_si(d)])
table("supplementary, NOT registered: fit set without Al-Mg-Si files", [d for d in fit if not al_mg_si(d)])

print("\n### Predicted (registration, 78 files) beside measured (this run, all distinct files)")
print("| rule set | predicted picks | predicted precision / recall | measured picks | measured precision / recall |"); print("|---|---|---|---|---|")
for c in ("R1", "R1R2", "R1R2R3"):
    pk, tp, tr = score(FILES, c)
    print(f"| {LABEL[c]} | {PRED[c][0]} | {pct(PRED[c][1])} / {pct(PRED[c][2])} | {pk} | {pct(tp / pk)} / {pct(tp / tr)} |")

print("\n### Refuting observations")
lost = [(d["name"], sorted((set(d["configs"]["base"]) & set(d["truth"])) - set(d["configs"]["R1"]))) for d in FILES]
lost = [x for x in lost if x[1]]
print(f"H1 refuted if any file loses a hit: files losing a hit under R1: {len(lost)} {lost}")
for label, files in (("fit set", fit), ("hold-out", hold)):
    pk, tp, tr = score(files, "R1R2")
    print(f"H2 on the {label}: R1+R2 precision {pct(tp / pk)}, recall {pct(tp / tr)} (refuted if recall < 43 % or precision < 45 % on the hold-out)")
rel = [(d["name"], d["released"]) for d in FILES if d.get("released")]
rel_true = sum(1 for d in FILES for e in d.get("released", []) if e in d["truth"]); rel_all = sum(len(d.get("released", [])) for d in FILES)
print(f"R3 released {rel_all} elements on the Velox files, {rel_true} of them in Velox's selection ({rel_all - rel_true} not)")

# precision/recall of the picks the Swift configs made, per file, vs the offline replication of the registration (analyse.py's `combined`): how many files differ
# is a diagnostic of the beside-a-listed-line and availability filters the room applies and the offline model does not.
print("\n### Files whose R1+R2+R3 picks differ from the base picks:", sum(set(d["configs"]["R1R2R3"]) != set(d["configs"]["base"]) for d in FILES))

print("\n### H4: Auto ID on the Mg-richest 1 % of pixels (the Mg K-alpha window map), Al-Mg-Si files")
h = [d for d in FILES if "h4" in d]
n = len(h); mg = [d for d in h if d["h4"]["mgBase"]]
print(f"files with the diagnostic: {n} (Al-Mg-Si files: {sum(map(al_mg_si, FILES))}); Mg found on the top 1 %: {len(mg)}; Mg found on the whole map by the same proposer: {sum('Mg' in d['configs']['base'] for d in h)}")
print(f"mean net Mg window counts per pixel, top 1 % vs all pixels (median over files): {sorted(d['h4']['meanNetTop'] for d in h)[n // 2]:.2f} vs {sorted(d['h4']['meanNetAll'] for d in h)[n // 2]:.3f}" if n else "no H4 data")
print("pixels pooled (min / median / max):", (min(d["h4"]["pixels"] for d in h), sorted(d["h4"]["pixels"] for d in h)[n // 2], max(d["h4"]["pixels"] for d in h)) if n else "-")
print("registered (H4 predicted >= 20 of 26; refuted below 10 of 26)")

if ladder_out:
    print("\n### H3: the demo-edx dose ladder (truth known; releasing >= 10 L_D must add no element absent from truth)")
    bad = 0
    print("| region | counts/px | planted elements | proposer picks | R1+R2+R3 picks | released | released and absent from truth |"); print("|---|---|---|---|---|---|---|")
    for p in sorted(glob.glob(ladder_out + "/ladder*.json")):
        d = json.load(open(p)); r = d["released"]; absent = [e for e in r if e not in d["truth"]]; bad += len(absent)
        print(f"| {d['region']} | {d['dose']} | {' '.join(d['truth'])} | {' '.join(d['configs']['base'])} | {' '.join(d['configs']['R1R2R3'])} | {' '.join(r) or 'none'} | {' '.join(absent) or 'none'} |")
    print(f"H3 {'REFUTED' if bad else 'not refuted'}: {bad} released element(s) absent from truth")
