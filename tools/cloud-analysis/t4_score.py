#!/usr/bin/env python3
"""t4_score.py -- score a stride-3 phase map under the adopted T4 object-level bar (ADR 040).

Registration: docs/archive/v4/t4-first-scored-run-2026-09-28.md (committed before any run).
Bar: docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md. Objects, cleanup and
split/merge/vanished/spurious are direction_check.py's own functions (the app's object
definition, cross-checked against the Swift probe row for row), imported, not re-implemented.

"Within the published range" = no worse than the WORST of the four published methods at stride 3
(docs/cloud/2026-09-23/T2-T3-report-output.md): error counts <= the published maximum; ratios
|r - 1| <= the largest published |r - 1|. Raw metrics use the raw rows, the rest "stride then P/9".
Ratios are taken against the truth under the SAME convention (truth · P/9: T1 34 objects, median
29.6745 px, area 0.217161), so a perfect map scores exactly 1; the published limits are those four
methods' P/9 rows against that same reference (amendment of 2026-09-28, registered before any
app number was read: the first version used the raw truth, and the truth itself failed it).

usage: t4_score.py APP_LABELS_JSON TRUTH_STRIDE3_JSON
  APP_LABELS_JSON from tools/phase-map-probe --object-table --dump-labels ("guarded" is scored,
  "baseline" reported). Exit 0 always when it ran; the verdict is printed, not signalled.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import direction_check as dc  # noqa: E402

STRIDE = 3
EDGE, FACE, T1 = 1, 2, 3
NAMES = {EDGE: "θ′ edge-on", FACE: "θ′ face-on", T1: "T1"}

# Published limits at stride 3 (T2-T3-report-output.md § Stride 3). Keys: (class, metric).
LIMITS = {
    (T1, "raw spurious"): ("count", 13), (FACE, "raw spurious"): ("count", 113), (EDGE, "raw spurious"): ("count", 5),
    (T1, "raw merge"): ("count", 1), (FACE, "raw merge"): ("count", 0),
    (T1, "P/9 split"): ("count", 2), (T1, "P/9 merge"): ("count", 0), (T1, "P/9 vanished"): ("count", 5),
    (FACE, "P/9 split"): ("count", 0), (FACE, "P/9 merge"): ("count", 0), (FACE, "P/9 vanished"): ("count", 0),
    # Against truth · P/9 (T1 34 / 29.6745 px / 0.217161; face-on 3 / 22.2271 / 0.033173; edge-on area
    # 0.014261), from the published P/9 rows: T1 counts 36 36 34 35, medians 27.21 27.20 30.77 27.20,
    # areas .2147 .2129 .2063 .2148; face-on medians 21.56 22.97 22.35 22.46, areas .0332 .0347
    # .0354 .0352; edge-on areas .0153 .0125 .0186 .0194.
    (T1, "count ratio"): ("ratio", 0.0588), (FACE, "count ratio"): ("ratio", 0.0),
    (T1, "median ratio"): ("ratio", 0.0834), (FACE, "median ratio"): ("ratio", 0.0334),
    (T1, "area ratio"): ("ratio", 0.0500), (FACE, "area ratio"): ("ratio", 0.0671), (EDGE, "area ratio"): ("ratio", 0.3604),
}
REPORTED_ONLY = [(EDGE, "raw merge")]


def metrics(labels, truth, not_indexed, rule="P", round_up=True, face_conn=None):
    """Every T4 number for one map. round_up / face_conn exist only for the convention breaks."""
    out = {}
    tclasses, _ = dc.objects(truth, set())
    raw, _ = dc.objects(labels, not_indexed)
    for c in NAMES:
        split, merge, vanished, spurious = dc.smv(tclasses[c]["objects"], raw[c]["objects"])
        out[(c, "raw spurious")] = spurious
        out[(c, "raw merge")] = merge
    saved = dict(dc.RULES[rule])
    grid = {}
    for c, (area, conn) in saved.items():
        if c == FACE and face_conn is not None:
            conn = face_conn
        a = area / STRIDE ** 2
        grid[c] = (max(1, math.ceil(a) if round_up else math.floor(a)), conn)
    dc.RULES["_t4"] = grid
    try:
        cleaned = dc.cleanup(labels, "_t4")
        truth_cleaned = dc.cleanup(truth, "_t4")
    finally:
        del dc.RULES["_t4"]
    cl, _ = dc.objects(cleaned, not_indexed)
    tcl, _ = dc.objects(truth_cleaned, set())
    for c in NAMES:
        split, merge, vanished, spurious = dc.smv(tclasses[c]["objects"], cl[c]["objects"])
        out[(c, "P/9 split")], out[(c, "P/9 merge")], out[(c, "P/9 vanished")] = split, merge, vanished
        p, t = dc.lengths(cl[c]["objects"]), dc.lengths(tcl[c]["objects"])
        out[(c, "count ratio")] = len(p) / len(t)
        out[(c, "median ratio")] = dc.q(p, 1, 2) / dc.q(t, 1, 2) if p else float("nan")
        out[(c, "area ratio")] = cl[c]["area_fraction"] / tcl[c]["area_fraction"]
    return out


def judge(m):
    rows, all_pass = [], True
    for key, (kind, limit) in LIMITS.items():
        v = m[key]
        ok = (v <= limit) if kind == "count" else (abs(v - 1) <= limit + 1e-9)
        all_pass &= ok
        shown = "%d" % v if kind == "count" else "%.3f" % v
        lim = "≤ %d" % limit if kind == "count" else "|r−1| ≤ %.3f" % limit
        rows.append((NAMES[key[0]], key[1], shown, lim, "pass" if ok else "**FAIL**"))
    return rows, all_pass


def table(title, m):
    rows, ok = judge(m)
    print("### %s — %s\n" % (title, "PASS" if ok else "FAIL"))
    print("| class | metric | value | published limit | |\n|---|---|---|---|---|")
    for r in rows:
        print("| %s |" % " | ".join(r))
    for key in REPORTED_ONLY:
        print("| %s | %s | %d | reported only | |" % (NAMES[key[0]], key[1], m[key]))
    print()
    return ok


def main(app_json, truth_json):
    d = json.load(open(app_json))
    w, h = d["width"], d["height"]
    ni = set(d["notIndexedLabels"])
    truth = np.array(json.load(open(truth_json))["labels"], dtype=np.int32)
    assert truth.shape == (h, w), (truth.shape, (h, w))
    guarded = np.array(d["guarded"], dtype=np.int32).reshape(h, w)
    baseline = np.array(d["baseline"], dtype=np.int32).reshape(h, w)
    print("# t4_score.py — %s\n" % os.path.basename(app_json))
    print("Per-position error: guarded %.2f %%, unguarded %.2f %%\n"
          % tuple(100.0 * np.count_nonzero(x != truth) / truth.size for x in (guarded, baseline)))

    # Validity 0 (added in the amendment): the truth itself must PASS, and the truth with its
    # largest T1 object deleted must FAIL, or the bar is miscalibrated.
    from scipy import ndimage
    self_ok = judge(metrics(truth, truth, set()))[1]
    lab, _ = ndimage.label(truth == T1, structure=np.ones((3, 3)))
    sizes = np.bincount(lab.ravel()); sizes[0] = 0
    deleted = truth.copy(); deleted[lab == sizes.argmax()] = 0
    delete_ok = judge(metrics(deleted, truth, set()))[1]
    print("Validity 0: the truth itself %s (must PASS); one T1 object deleted %s (must FAIL)\n"
          % ("PASSES" if self_ok else "FAILS", "PASSES" if delete_ok else "FAILS"))

    scored = metrics(guarded, truth, ni)
    verdict = table("Scored: guarded map (k = 1), P/9", scored)
    table("Bracket: guarded map, H/9", metrics(guarded, truth, ni, rule="H"))
    table("Reported: unguarded map, P/9", metrics(baseline, truth, ni))

    # Validity 1: the null must fail. Truth with Al positions flipped at the scored map's own rates.
    al = truth == 0
    n_al = np.count_nonzero(al)
    rate_face = np.count_nonzero(al & (guarded == FACE)) / n_al
    rate_t1 = np.count_nonzero(al & (guarded == T1)) / n_al
    rng = np.random.default_rng(20260928)
    null = truth.copy().ravel()
    idx = np.flatnonzero(al.ravel())
    r = rng.random(len(idx))
    null[idx[r < rate_face]] = FACE
    null[idx[(r >= rate_face) & (r < rate_face + rate_t1)]] = T1
    null = null.reshape(truth.shape)
    print("Null: stride-3 truth with Al → face-on at %.5f and Al → T1 at %.5f (the scored map's own rates), seed 20260928\n"
          % (rate_face, rate_t1))
    null_ok = table("Validity 1: the null map (must FAIL)", metrics(null, truth, set()))

    # Validity 3 (S10, registered 2026-09-30): a null with edge-on flips must fail. The edge-on class has
    # published limits (raw spurious <= 5, area |r-1| <= 0.360); flip 0.2 % of the truth-Al positions to
    # edge-on (about 55 isolated positions), so the bar must see them. Seed 20260930.
    rng3 = np.random.default_rng(20260930)
    edge_null = truth.copy().ravel()
    pick = idx[rng3.random(len(idx)) < 0.002]
    edge_null[pick] = EDGE
    edge_null = edge_null.reshape(truth.shape)
    print("Edge-on null: stride-3 truth with %d Al positions → edge-on (0.2 %% of Al), seed 20260930\n" % len(pick))
    edge_null_ok = table("Validity 3: the edge-on-flipping null (must FAIL)", metrics(edge_null, truth, set()))

    # Validity 2: breaking the convention must move at least one number.
    moved = {}
    for name, kwargs in (("÷ 9 rounded down", {"round_up": False}), ("face-on 8-connected", {"face_conn": 8})):
        b = metrics(guarded, truth, ni, **kwargs)
        moved[name] = [k for k in scored if not (scored[k] == b[k] or (isinstance(b[k], float) and math.isnan(b[k]) and math.isnan(scored[k])))]
        print("Validity 2, break '%s': %d number(s) move%s" % (name, len(moved[name]),
              (": " + ", ".join("%s %s %s→%s" % (NAMES[k[0]], k[1], scored[k], b[k]) for k in moved[name][:4])) if moved[name] else ""))
    print()
    valid = self_ok and not delete_ok and (not null_ok) and (not edge_null_ok) and any(moved.values())
    reason = ("the bar fails the truth" if not self_ok else "the bar passes a deleted object" if delete_ok
              else "the null passed" if null_ok else "the edge-on null passed" if edge_null_ok else "no convention break moved anything")
    print("## Verdict: %s — run %s\n" % ("PASS" if verdict else "FAIL", "counts" if valid else "DOES NOT COUNT (%s)" % reason))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
