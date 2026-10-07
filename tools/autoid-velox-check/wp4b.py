#!/usr/bin/env python3
"""WP4b report (2026-10-07): baseline (ProposalRules.shipped) / R1b / R2 / R1b + R2 on the three truth sets, beside the registration's hypotheses
(docs/archive/v5/wp4b-autoid-rules-preregistration-2026-10-07.md). Reads what `run.sh --ladder <in> --out <dir>` (T-Q, T-S, demo-edx ladder) and
`run.sh --out <dir> <folder>` (T-V) wrote: every JSON carries `configs` (the picks of each rule set as the Swift code made them), `withheldBy` (what each rule
withheld, with the number) and `candidates`. Stdlib only. It states numbers and the registered refuting observations; it does not say which rule ships.

    wp4b.py [--tq <dir>] [--ts <dir>] [--demo <dir>] [--tv <dir>]"""
import glob, json, os, sys
from collections import defaultdict

args = sys.argv[1:]; dirs = {}
while args:
    a = args.pop(0); dirs[a[2:]] = args.pop(0)
CFG = [("base", "w4b_base"), ("R1b", "w4b_R1b"), ("R2", "w4b_R2"), ("R1bR2", "w4b_R1bR2")]
UNREACHABLE = {"H", "He", "Li", "Be", "B", "C", "N"}      # refused by the proposer or under its 0.45 keV minimum line energy (ElementProposer.minimumLineEnergyKeV)
pct = lambda x: "n/a" if x != x else f"{100 * x:.1f} %"
div = lambda a, b: a / b if b else float("nan")

def load(d, pattern):
    out = []
    for p in sorted(glob.glob(os.path.join(d, pattern))):
        j = json.load(open(p)); j["_id"] = os.path.basename(p).split(".")[0]; out.append(j)
    return out
def name(j): return j.get("meta", {}).get("id") or j.get("meta", {}).get("dose") or os.path.basename(j.get("file", j["_id"]))
def cand(j, el): return next((c for c in j["candidates"] if c["element"] == el), None)

def score(files, truthf=lambda j: j["truth"]):
    res = {}
    for label, key in CFG:
        pk = tp = tr = 0
        for j in files:
            picks, truth = set(j["configs"][key]), set(truthf(j))
            pk += len(picks); tp += len(picks & truth); tr += len(truth)
        res[label] = (pk, tp, tr)
    return res
def table(title, files, truthf=lambda j: j["truth"]):
    print(f"\n#### {title}: {len(files)} spectra")
    s = score(files, truthf)
    print("| rule set | picks | hits | false picks | truth elements | precision | recall |"); print("|---|---|---|---|---|---|---|")
    for label, _ in CFG:
        pk, tp, tr = s[label]; print(f"| {label} | {pk} | {tp} | {pk - tp} | {tr} | {pct(div(tp, pk))} | {pct(div(tp, tr))} |")
    return s

def changes(files, truthf=lambda j: j["truth"], describe=lambda j: name(j)):
    """Every pick a rule removed against the baseline, true or false, with the rule's own number."""
    rows = []
    for j in files:
        base = j["configs"]["w4b_base"]; truth = set(truthf(j))
        for label, key in CFG[1:]:
            for el in base:
                if el in j["configs"][key]: continue
                w = [x for x in j.get("withheldBy", {}).get(key, []) if x["element"] == el]
                c = cand(j, el)
                rows.append({"file": describe(j), "rule set": label, "element": el, "true": el in truth, "group": c["group"] if c else "?", "sig": c["significance"] if c else float("nan"),
                             "why": "; ".join(f"{x['rule']}: {x['why']}" for x in w) or "(not named)"})
    return rows
def print_changes(rows, only=None):
    rows = [r for r in rows if (only is None or only(r))]
    print("| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |"); print("|---|---|---|---|---|---|---|")
    for r in rows: print(f"| {r['file']} | {r['rule set']} | {r['element']} | {'TRUE' if r['true'] else 'false'} | {r['group']} | {r['sig']:.2f} | {r['why']} |")
    if not rows: print("| (none) | | | | | | |")
    return rows

verdict = {}
print("# WP4b measurement (rule sets: baseline = ProposalRules.shipped; R1b = shipped + beside-K with the evidence guard; R2 = shipped + L/M needs net/L_D >= 3; R1b+R2)")

# ---------------------------------------------------------------- T-Q
if "tq" in dirs:
    print("\n## T-Q: DTSA-II QualSpectra (31 glass standards; SEM bulk 20-25 kV, 10 eV/ch; NOT 200 kV thin film)")
    Q = load(dirs["tq"], "ladder*.json")
    for j in Q: j["difficulty"] = j["meta"]["difficulty"]
    reach = lambda j: [e for e in j["truth"] if e not in UNREACHABLE]
    s_all = table("all classes, truth = the answers file as given (includes Li, B)", Q)
    s_all_r = table("all classes, truth without the elements the proposer cannot reach (Li, B; none of H, He, Be, C, N occurs)", Q, reach)
    byclass = {}
    for cls in ("easy", "moderate", "difficult", "very difficult"):
        byclass[cls] = (table(f"class {cls}", [j for j in Q if j["difficulty"] == cls]), table(f"class {cls}, reachable truth", [j for j in Q if j["difficulty"] == cls], reach))
    print("\n#### Every pick a rule removed against the baseline (T-Q)")
    qrows = print_changes(changes(Q, describe=lambda j: f"{j['meta']['id']} ({j['difficulty']})"))
    print("\n#### Truth elements the BASELINE does not pick (T-Q), to see what the rules could not have cost")
    miss = defaultdict(list)
    for j in Q:
        for e in j["truth"]:
            if e not in j["configs"]["w4b_base"]: miss[e].append(j["meta"]["id"])
    print("; ".join(f"{e}: {len(v)}" for e, v in sorted(miss.items(), key=lambda kv: -len(kv[1]))))
    verdict["tq"] = (Q, s_all, byclass, qrows)

# ---------------------------------------------------------------- T-S
if "ts" in dirs:
    print("\n## T-S: seeded risk simulator (200 kV, owner's axis, Al matrix; Al is in every truth)")
    S = load(dirs["ts"], "ladder*.json")
    P = [j for j in S if j["meta"]["case"] == "pair"]; G = [j for j in S if j["meta"]["case"] == "ghost"]
    print("\n#### Pairs: picks per rule set (L = the L element, K = the K element; Y = picked)")
    print("| case | ratio L:K | dose | planted net/L_D L, K | baseline L K | R1b L K | R2 L K | R1b+R2 L K | candidate net/L_D L, K |"); print("|---|---|---|---|---|---|---|---|---|")
    for j in P:
        m = j["meta"]; cells = []
        for _, key in CFG:
            pk = j["configs"][key]; cells.append(("Y" if m["L"] in pk else "-") + " " + ("Y" if m["K"] in pk else "-"))
        cl, ck = cand(j, m["L"]), cand(j, m["K"])
        print(f"| {m['pair']} | {m['ratio']} | {m['doseLabel']} | {m['plantedSignificanceL']:.1f}, {m['plantedSignificanceK']:.1f} | " + " | ".join(cells) + f" | {cl['significance']:.1f}, {ck['significance']:.1f} |")
    table("pairs, all", P); table("pairs ratio >= 1", [j for j in P if j["meta"]["ratio"] >= 1]); table("pairs ratio 0.3", [j for j in P if j["meta"]["ratio"] < 1])
    print("\n#### Pairs: every pick a rule removed against the baseline")
    prow = print_changes(changes(P, describe=lambda j: f"{j['meta']['pair']} r{j['meta']['ratio']} {j['meta']['doseLabel']}"))
    print("\n#### Ghosts (K element alone on Al at the high dose; any pick other than Al and the planted K is false)")
    print("| ghost | planted net/L_D K | baseline picks | R1b | R2 | R1b+R2 |"); print("|---|---|---|---|---|---|")
    for j in G:
        m = j["meta"]; print(f"| {m['K']} | {m['plantedSignificanceK']:.1f} | " + " | ".join(" ".join(j["configs"][k]) for _, k in CFG) + " |")
    table("ghosts", G)
    print("\n#### Ghosts: every pick a rule removed against the baseline")
    grow = print_changes(changes(G, describe=lambda j: f"{j['meta']['K']} ghost"))
    verdict["ts"] = (P, G, prow, grow)

# ---------------------------------------------------------------- demo ladder
if "demo" in dirs:
    print("\n## demo-edx dose ladder (8 regions, truth planted)")
    D = load(dirs["demo"], "ladder*.json")
    table("demo ladder", D)
    print_changes(changes(D, describe=lambda j: f"region {j['region']} ({j.get('dose')} counts/px)"))
    verdict["demo"] = D

# ---------------------------------------------------------------- T-V
if "tv" in dirs:
    print("\n## T-V: the owner's Velox selections (agreement, not truth)")
    V0 = load(dirs["tv"], "[0-9]*.json"); seen, V = set(), []
    for j in V0:
        k = (os.path.basename(j["file"]), j["totalCounts"])
        if k not in seen: seen.add(k); V.append(j)
    print(f"files scored {len(V0)}, distinct {len(V)}")
    table("T-V distinct files", V)
    print("\n#### Every pick a rule removed against the baseline (T-V)")
    vrow = print_changes(changes(V, describe=lambda j: os.path.basename(j["file"])))
    verdict["tv"] = (V, vrow)

# ---------------------------------------------------------------- registered refuting observations (stated, not judged)
print("\n## The registered refuting observations, one by one (each is a count; the verdict is the reader's)")
def lost(rows, label): return [r for r in rows if r["rule set"] == label and r["true"]]
def removed_false(rows, label): return [r for r in rows if r["rule set"] == label and not r["true"]]
if "ts" in verdict:
    P, G, prow, grow = verdict["ts"]
    ge1 = [r for r in lost(prow, "R1b") if "r1" in r["file"] or "r3" in r["file"]]
    print(f"- H5 (a): true elements dropped by R1b on T-S pairs at ratio >= 1: {len(ge1)}"); [print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"]) for r in ge1]
    le = [r for r in lost(prow, "R1b") if "r0.3" in r["file"]]
    print(f"- H5 (b): true elements dropped by R1b at ratio 0.3 (admitted cost): {len(le)}"); [print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"]) for r in le]
    bf = sum(len([e for e in j["configs"]["w4b_base"] if e not in j["truth"]]) for j in G)
    print(f"- H5 (c): ghosts: false picks the baseline makes {bf}; removed by R1b {len(removed_false(grow, 'R1b'))}")
    pf = sum(len([e for e in j["configs"]["w4b_base"] if e not in j["truth"]]) for j in P)
    print(f"  pairs: false picks the baseline makes {pf}; removed by R1b {len(removed_false(prow, 'R1b'))}")
    # The registered observation counts only true elements whose PLANTED net/L_D >= 3 (the candidate's own net/L_D is printed beside each).
    planted = {}
    for j in P:
        m = j["meta"]; name_ = f"{m['pair']} r{m['ratio']} {m['doseLabel']}"
        planted[(name_, m["L"])] = m["plantedSignificanceL"]; planted[(name_, m["K"])] = m["plantedSignificanceK"]
    # R2's own losses: every R2 drop, and the R1bR2 drops that R2 (not the beside-K guard) made.
    r2all = lost(prow, "R2") + [r for r in lost(prow, "R1bR2") if r["why"].startswith("R2")]
    r2lost = [r for r in r2all if planted.get((r["file"], r["element"]), 0) >= 3]
    print(f"- H6 (b): true elements lost by R2 (R2's own drops, incl. the R1b+R2 set) on T-S pairs with PLANTED net/L_D >= 3: {len(r2lost)} "
          f"(all true losses, any planted level: {len(r2all)}; the planted level of each is in the pairs table)")
    for r in r2lost: print("    ", r["file"], r["rule set"], r["element"], f"candidate net/L_D {r['sig']:.2f}", r["why"])
if "tq" in verdict:
    Q, s_all, byclass, qrows = verdict["tq"]
    print(f"- H5 (d): T-Q hits lost by R1b: {len(lost(qrows, 'R1b'))}; T-Q false picks removed by R1b: {len(removed_false(qrows, 'R1b'))}")
    for r in lost(qrows, "R1b"): print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"])
    b, r2 = s_all["base"], s_all["R2"]
    print(f"- H6 (a): T-Q precision baseline {pct(div(b[1], b[0]))} -> R2 {pct(div(r2[1], r2[0]))} (all classes, truth as given); easy/moderate hits lost by R2: "
          f"{len([r for r in lost(qrows, 'R2') if '(easy)' in r['file'] or '(moderate)' in r['file']])}")
    for r in [r for r in lost(qrows, "R2")]: print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"])
if "tv" in verdict:
    V, vrow = verdict["tv"]
    print(f"- H5 (d): T-V hits lost by R1b: {len(lost(vrow, 'R1b'))}; false picks removed by R1b: {len(removed_false(vrow, 'R1b'))}")
    for r in lost(vrow, "R1b"): print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"])
    print(f"- H6 (c): T-V hits lost by R2: {len(lost(vrow, 'R2'))} (registered: refuted if more than one); by R1b+R2: {len(lost(vrow, 'R1bR2'))}")
    for r in lost(vrow, "R2"): print("    ", r["file"], r["element"], f"{r['sig']:.2f}", r["why"])
if "ts" in verdict and "tq" in verdict and "tv" in verdict:
    tot = sum(len(removed_false(x, "R1b")) for x in (verdict["ts"][2], verdict["ts"][3], verdict["tq"][3], verdict["tv"][1]))
    print(f"- H5 (e): false picks removed by R1b anywhere (T-S pairs + ghosts, T-Q, T-V): {tot} (refuted if none)")
