#!/usr/bin/env python3
# usage: an.py <prefix> <variantA> <variantB> ...  — pairs ROW lines by id across variants (logs/<prefix>-<v>-p*.log)
import sys, glob, collections
prefix, variants = sys.argv[1], sys.argv[2:]
def rows(v):
    d = {}
    for f in sorted(glob.glob(f"logs/{prefix}-{v}-p*.log")):
        for line in open(f):
            if not line.startswith("ROW|"): continue
            kv = dict(x.split("=", 1) for x in line.strip().split("|")[1:])
            d[kv["id"]] = kv
    return d
R = {v: rows(v) for v in variants}
ids = sorted(R[variants[0]])
print({v: len(R[v]) for v in variants})
def dr(kv): return abs(float(kv["dR"])) if "dR" in kv else None
head = R["head"]
def right(kv): return kv["status"] == "profile" and dr(kv) <= 0.001
nright = [i for i in ids if right(head[i])]
print("head right (profile, |dR|<=0.1%):", len(nright), "of", len(ids))
for v in variants:
    if v == "head": continue
    wrong = [i for i in nright if R[v][i]["status"] == "THREW" or dr(R[v][i]) is None or dr(R[v][i]) > 0.01]
    print(f"{v}: right-at-head and |dR|>1%: {len(wrong)}")
    by = collections.Counter()
    for i in wrong:
        h = head[i]; by[(h["noise"], h["tail"])] += 1
    print("   by (noise,tail):", dict(sorted(by.items())))
    for i in wrong:
        r = R[v][i]; h = head[i]
        print(f"   {i}  head dR={h['dR']} dba={h['dba']} cerr={h['cerr']} | {v} {r['status']} dR={r.get('dR')} dba={r.get('dba')} cerr={r.get('cerr')} sin={r.get('sin')} sout={r.get('sout')}")
# head wrong
hw = [i for i in ids if head[i]["status"] != "THREW" and float(head[i]["dR"]) and abs(float(head[i]["dR"])) > 0.01]
print("head wrong >1%:", len(hw))
