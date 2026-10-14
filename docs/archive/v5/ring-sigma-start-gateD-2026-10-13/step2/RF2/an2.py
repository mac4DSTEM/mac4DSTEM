#!/usr/bin/env python3
# RF2 own parser. usage: an2.py <set> -> per-set tables. Logs: RF/logs/<S>_<v>.log (ROW|k=v|...), truth is in the ROW itself
# (R, ba_true, sigma_true are printed by the harness from planted.json; verified against planted.json below).
import sys, json, collections, os
SP = "/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/RF"
VARS = ["head", "a", "b", "ab"]
def parse(path):
    rows = collections.OrderedDict()
    for ln in open(path):
        if not ln.startswith("ROW|"): continue
        d = {}
        for kv in ln.rstrip("\n").split("|")[1:]:
            k, _, v = kv.partition("=")
            d[k] = v
        rows[d["name"]] = d
    return rows
def fl(d, k):
    try: return float(d[k])
    except Exception: return float("nan")
def classify(d):
    st = d.get("status")
    if st == "THREW": return "threw"
    if st == "conic": return "conic"
    if st == "profile":
        e = abs(fl(d, "dR"))
        return "prof_right" if e < 0.001 else ("prof_wrong" if e > 0.01 else "prof_mid")
    return "other:" + str(st)
def load(S):
    return {v: parse("%s/logs/%s_%s.log" % (SP, S, v)) for v in VARS}
def cmp_sets(S, tiergroup=None):
    R = load(S)
    names = list(R["head"].keys())
    for v in VARS: assert list(R[v].keys()) == names, (S, v)
    return R, names
if __name__ == "__main__":
    S = sys.argv[1]
    R, names = cmp_sets(S)
    print("set", S, "plants", len(names))
    tiers = sorted(set(R["head"][n]["tier"] for n in names))
    for scope in ["ALL"] + tiers:
        sel = [n for n in names if scope == "ALL" or R["head"][n]["tier"] == scope]
        print("== %s (%d)" % (scope, len(sel)))
        for v in VARS:
            c = collections.Counter(classify(R[v][n]) for n in sel)
            print("  %-4s %s" % (v, dict(sorted(c.items()))))
