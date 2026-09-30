#!/usr/bin/env python
"""compare_peaks.py A.json B.json [--tol 0.05] — compare two scan-bench `--peaks` files.
Per threshold: total peaks of A and B, the number of positions whose peak counts differ, and a greedy nearest matching
per position (repeatedly take the closest unmatched A-B pair, distance in px, until none is within --tol): how many of
A's peaks have a B peak within tol, how many of B's are unmatched, and the worst matched distance. Then the classical
comparison, which must be identical between runs (same code, CPU only) — the line says so, or says it is not.
Plain python; exit 0 always (a report, not a gate)."""
import argparse, json, math

def match(pa, pb, tol):
    """Greedy nearest matching of two peak lists [x, y, i]: returns (matched pairs' distances)."""
    pairs = sorted((math.hypot(a[0] - b[0], a[1] - b[1]), i, j) for i, a in enumerate(pa) for j, b in enumerate(pb))
    ua, ub, dists = set(), set(), []
    for d, i, j in pairs:
        if d > tol: break
        if i in ua or j in ub: continue
        ua.add(i); ub.add(j); dists.append(d)
    return dists

def compare(PA, PB, tol):
    assert len(PA) == len(PB), "different position counts: %d vs %d" % (len(PA), len(PB))
    ta = sum(map(len, PA)); tb = sum(map(len, PB))
    cdiff = sum(1 for a, b in zip(PA, PB) if len(a) != len(b))
    matched = 0; worst = 0.0
    for a, b in zip(PA, PB):
        d = match(a, b, tol); matched += len(d); worst = max([worst] + d)
    return dict(A=ta, B=tb, pos_count_differs=cdiff, positions=len(PA), A_matched=matched, A_unmatched=ta - matched, B_unmatched=tb - matched, worst=worst)

ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b"); ap.add_argument("--tol", type=float, default=0.05)
o = ap.parse_args()
A, B = json.load(open(o.a)), json.load(open(o.b))
print("A %s (units %s) vs B %s (units %s), tol %.3f px" % (o.a.split("/")[-1], A.get("units"), o.b.split("/")[-1], B.get("units"), o.tol))
tb = {round(t["threshold"], 4): t for t in B["thresholds"]}
for ta in A["thresholds"]:
    k = round(ta["threshold"], 4)
    if k not in tb: print("threshold %.2f: missing in B" % k); continue
    r = compare(ta["positions"], tb[k]["positions"], o.tol)
    print("threshold %.2f: A %d B %d | positions with different counts %d/%d | A matched %d/%d within tol, A unmatched %d, B unmatched %d | worst matched distance %.4f px"
          % (k, r["A"], r["B"], r["pos_count_differs"], r["positions"], r["A_matched"], r["A"], r["A_unmatched"], r["B_unmatched"], r["worst"]))
if A.get("classical") and B.get("classical"):
    r = compare(A["classical"], B["classical"], o.tol)
    same = (A["classical"] == B["classical"])
    print("classical: A %d B %d | positions with different counts %d/%d | A unmatched %d, B unmatched %d | worst matched distance %.4f px | %s"
          % (r["A"], r["B"], r["pos_count_differs"], r["positions"], r["A_unmatched"], r["B_unmatched"], r["worst"],
             "IDENTICAL (exact)" if same else "NOT IDENTICAL (classical must not differ between runs)"))
else:
    print("classical: not in both files")
