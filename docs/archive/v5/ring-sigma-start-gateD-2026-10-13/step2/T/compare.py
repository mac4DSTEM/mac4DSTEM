#!/usr/bin/env python3
"""Lane T: compare DUMP lines of variants a, b, ab against head. stdlib only.
usage: compare.py   (run in the lane directory; reads logs/dump-<v>.log and work/expected.json)"""
import json, math, sys

VARIANTS = ["a", "b", "ab"]
d = json.load(open("work/expected.json"))
plant = {}
for c in d["cases"]:
    plant[c["name"]] = (c["a"], c["b"], c["theta"], c["centerQX"], c["centerQY"])
for c in d["profileCases"]:
    plant[c["name"]] = (c["a"], c["b"], c["theta"], c["centerQX"], c["centerQY"])
for c in d["spotCases"]:
    plant[c["name"]] = (c["a"], c["b"], c["theta"], c["centerQX"], c["centerQY"])
plant["spotty_ring_6_azimuths_seed3.2"] = plant["spotty_ring_6_azimuths"]
for c in d["sweepCases"]:
    plant[c["name"]] = (c["a"], c["b"], c["theta"] if c["theta"] is not None else 0.0, c["centerQX"], c["centerQY"])

def load(v):
    rows = {}
    for line in open("logs/dump-%s.log" % v, errors="replace"):
        line = line.rstrip("\n")
        i = line.find("DUMP|")
        if i < 0:
            continue
        rec = {}
        for kv in line[i + 5:].split("|"):
            if "=" in kv:
                k, val = kv.split("=", 1)
                rec[k] = val
        key = (rec["case"], rec["fn"])
        assert key not in rows, ("duplicate", v, key)
        rows[key] = rec
    return rows

def state(r):
    return ("threw " + r["threw"]) if "threw" in r else ("returned " + r["model"])

def angle_diff(x, y):
    r = abs(x - y) % math.pi
    return min(r, math.pi - r)

def mean_ab(r):
    return (float(r["a"]) + float(r["b"])) / 2

def group(key):
    c, fn = key
    if fn == "fitBestAvailable-sweep": return "sweep fitBestAvailable (48)"
    if c.startswith("sweep-") and fn == "fit1D": return "sweep fit1D (48)"
    if fn == "fit1D": return "existing cases fit1D"
    return "existing cases fitBestAvailable"

out = []
def P(s=""):
    out.append(s); print(s)

head = load("head")
P("compare.py: variants vs head; head DUMP records: %d" % len(head))
by = {}
for key in head:
    by.setdefault(group(key), []).append(key)
for g in sorted(by): P("  head group %-34s %3d records" % (g, len(by[g])))
P()
for v in VARIANTS:
    var = load(v)
    P("=" * 100)
    P("VARIANT %s   (records %d; keys equal to head's: %s)" % (v, len(var), set(var) == set(head)))
    # model / threw changes
    model_changes, threw_changes = [], []
    for key in sorted(head):
        h, x = head[key], var[key]
        ht, xt = "threw" in h, "threw" in x
        if ht != xt or (ht and h["threw"] != x["threw"]):
            threw_changes.append((key, state(h), state(x)))
        elif not ht and h["model"] != x["model"]:
            model_changes.append((key, h, x))
    P("model changes (returns in both, model differs): %d" % len(model_changes))
    for key, h, x in model_changes:
        pl = plant.get(key[0])
        extra = ""
        if pl:
            R = (pl[0] + pl[1]) / 2
            extra = " | plant R %.4f: head err %+.4f %%, variant err %+.4f %%" % (
                R, 100 * (mean_ab(h) / R - 1), 100 * (mean_ab(x) / R - 1))
        P("  %s [%s]: head %s (resid %s, sin %s, sout %s) -> %s (resid %s, fallback: %s)%s" % (
            key[0], key[1], h["model"], h["resid"], h["sin"], h["sout"], x["model"], x["resid"], x["fallback"], extra))
    P("threw changes (a call returned in one and threw in the other, or threw differently): %d" % len(threw_changes))
    for key, hs, xs in threw_changes:
        h = head[key]
        pl = plant.get(key[0])
        extra = ""
        if pl and "threw" not in h:
            R = (pl[0] + pl[1]) / 2
            extra = " | head fit err vs plant R %.4f: %+.4f %% in (a+b)/2, a/b %.5f (plant a/b %.5f), model %s, sin %s sout %s" % (
                R, 100 * (mean_ab(h) / R - 1), float(h["a"]) / float(h["b"]), pl[0] / pl[1], h["model"], h["sin"], h["sout"])
        P("  %s [%s]: head: %s -> variant: %s%s" % (key[0], key[1], hs, xs, extra))
    # numeric moves, per group, on profile fits kept both ways (and for fit1D: exact equality)
    P("numeric moves (records that return in both with the same model):")
    for g in sorted(by):
        rows = [k for k in by[g] if "threw" not in head[k] and "threw" not in var[k] and head[k]["model"] == var[k]["model"]]
        prof = [k for k in rows if head[k]["model"] == "asymmetricGaussian"]
        conic = [k for k in rows if head[k]["model"] == "conic"]
        def stats(ks):
            if not ks: return None
            mr = max((abs(mean_ab(var[k]) - mean_ab(head[k])) / mean_ab(head[k]) * 100, k) for k in ks)
            mt = max((angle_diff(float(var[k]["theta"]), float(head[k]["theta"])), k) for k in ks)
            mc = max((math.hypot(float(var[k]["cx"]) - float(head[k]["cx"]), float(var[k]["cy"]) - float(head[k]["cy"])), k) for k in ks)
            return mr, mt, mc
        s = stats(prof)
        P("  %-34s same-model returns %3d  (profile %3d, conic %3d)" % (g, len(rows), len(prof), len(conic)))
        if s:
            P("      profile kept both ways: max |d(a+b)/2| = %.3e %% of head (%s); max |dtheta| = %.3e rad (%s); max centre move = %.3e px (%s)" % (
                s[0][0], s[0][1][0], s[1][0], s[1][1][0], s[2][0], s[2][1][0]))
            # near-circle theta caveat
            circ = [(angle_diff(float(var[k]["theta"]), float(head[k]["theta"])), abs(float(head[k]["a"]) - float(head[k]["b"])) / mean_ab(head[k]), k[0]) for k in prof]
            big = [c for c in circ if c[0] > 1e-3]
            for dt, ecc, nm in big:
                P("      theta move > 1e-3 rad: %s dtheta %.3e rad at head |a-b|/mean = %.3e" % (nm, dt, ecc))
        sc = stats(conic)
        if sc:
            P("      conic (returned in both): max |d(a+b)/2| = %.3e %%; max |dtheta| = %.3e rad; max centre move = %.3e px" % (sc[0][0], sc[1][0], sc[2][0]))
        # exact string equality for fit1D group
        if g.endswith("fit1D") or g.startswith("sweep fit1D"):
            fields = ["model", "a", "b", "theta", "cx", "cy", "resid", "cres", "n", "bins"]
            diff = [k for k in by[g] if ("threw" in head[k]) != ("threw" in var[k]) or ("threw" in head[k] and head[k]["threw"] != var[k]["threw"]) or
                    ("threw" not in head[k] and any(head[k][f] != var[k][f] for f in fields))]
            P("      fit1D exact equality of all printed fields (%%.9g): %d of %d records differ%s" % (len(diff), len(by[g]), "" if not diff else " -> " + ", ".join(k[0] for k in diff)))
    # profile-vs-plant for the profile fits kept both ways in sweep (does variant also stay as right as head)
    P("accuracy vs plant R, profile fits returned by head AND variant, existing + sweep (percent error in (a+b)/2):")
    for g in sorted(by):
        ks = [k for k in by[g] if "threw" not in head[k] and "threw" not in var[k] and head[k]["model"] == var[k]["model"] == "asymmetricGaussian" and k[0] in plant]
        if not ks: continue
        eh = [abs(mean_ab(head[k]) / ((plant[k[0]][0] + plant[k[0]][1]) / 2) - 1) * 100 for k in ks]
        ev = [abs(mean_ab(var[k]) / ((plant[k[0]][0] + plant[k[0]][1]) / 2) - 1) * 100 for k in ks]
        P("  %-34s n %3d  head max %.4f %% mean %.4f %%; variant max %.4f %% mean %.4f %%" % (g, len(ks), max(eh), sum(eh) / len(eh), max(ev), sum(ev) / len(ev)))
    P()

# head: model census
P("=" * 100)
P("HEAD census (profile / conic / threw) per group:")
for g in sorted(by):
    ks = by[g]
    nt = sum("threw" in head[k] for k in ks)
    npf = sum(("threw" not in head[k]) and head[k]["model"] == "asymmetricGaussian" for k in ks)
    nc = sum(("threw" not in head[k]) and head[k]["model"] == "conic" for k in ks)
    P("  %-34s profile %3d  conic %3d  threw %3d" % (g, npf, nc, nt))
for v in VARIANTS:
    var = load(v)
    P("variant %-2s census:" % v)
    for g in sorted(by):
        ks = by[g]
        nt = sum("threw" in var[k] for k in ks)
        npf = sum(("threw" not in var[k]) and var[k]["model"] == "asymmetricGaussian" for k in ks)
        nc = sum(("threw" not in var[k]) and var[k]["model"] == "conic" for k in ks)
        P("  %-34s profile %3d  conic %3d  threw %3d" % (g, npf, nc, nt))

# ---------------------------------------------------------------- detail section
FIELDS = ["model", "a", "b", "theta", "cx", "cy", "resid", "sin", "sout", "fallback", "cres", "n", "bins", "i1", "bg"]
def same(r1, r2):
    if ("threw" in r1) != ("threw" in r2): return False
    if "threw" in r1: return r1["threw"] == r2["threw"]
    return all(r1[f] == r2[f] for f in FIELDS)
va, vb, vab = load("a"), load("b"), load("ab")
P("=" * 100)
P("CROSS-CHECKS")
d_ab_a = [k for k in head if not same(vab[k], va[k])]
d_b_head = [k for k in head if not same(vb[k], head[k])]
P("ab vs a: %d records differ (b's refusal never fires after a's start, on these calls)%s" % (len(d_ab_a), "" if not d_ab_a else " -> " + ", ".join("%s[%s]" % k for k in d_ab_a)))
P("b vs head: %d records differ%s" % (len(d_b_head), "" if not d_b_head else " -> " + ", ".join("%s[%s]" % k for k in d_b_head)))
P()
P("DETAIL: existing cases, fitBestAvailable calls (error vs plant in %% of plant (a+b)/2; sin/sout = ring sigmas; i1 = ring intensity)")
for key in sorted(k for k in head if group(k) == "existing cases fitBestAvailable"):
    pl = plant.get(key[0])
    R = (pl[0] + pl[1]) / 2 if pl else None
    def desc(r):
        if "threw" in r: return "threw %s" % r["threw"]
        e = "" if R is None else " err %+.4f %%" % (100 * (mean_ab(r) / R - 1))
        return "%s%s (a+b)/2 %.4f a/b %.5f theta %.5f sin %s sout %s i1 %s resid %s cres %s" % (
            "profile" if r["model"] == "asymmetricGaussian" else "conic", e, mean_ab(r), float(r["a"]) / float(r["b"]), float(r["theta"]), r["sin"], r["sout"], r["i1"], r["resid"], r["cres"])
    P("  %s [%s]  plant R %s" % (key[0], key[1], "%.4f" % R if R else "?"))
    P("      head: %s" % desc(head[key]))
    P("      a   : %s" % desc(va[key]))
    P("      b   : %s" % ("identical to head" if same(vb[key], head[key]) else desc(vb[key])))
    P("      ab  : %s" % ("identical to a" if same(vab[key], va[key]) else desc(vab[key])))
P()
P("DETAIL: sweep fitBestAvailable, variant a (= ab), rings that returned a profile fit in head AND in a, sorted by |d(a+b)/2|")
rows = []
for key in head:
    if key[1] != "fitBestAvailable-sweep": continue
    h, x = head[key], va[key]
    if "threw" in h or "threw" in x or h["model"] != "asymmetricGaussian" or x["model"] != "asymmetricGaussian": continue
    pl = plant[key[0]]; R = (pl[0] + pl[1]) / 2
    sc = next(c for c in d["sweepCases"] if c["name"] == key[0])
    rows.append((abs(mean_ab(x) - mean_ab(h)) / mean_ab(h) * 100, key[0], sc["eps"], sc["gapDegrees"],
                 100 * (mean_ab(h) / R - 1), 100 * (mean_ab(x) / R - 1),
                 angle_diff(float(x["theta"]), float(h["theta"])),
                 angle_diff(float(h["theta"]), pl[2]) if sc["eps"] > 0 else None,
                 angle_diff(float(x["theta"]), pl[2]) if sc["eps"] > 0 else None,
                 math.hypot(float(x["cx"]) - float(h["cx"]), float(x["cy"]) - float(h["cy"])),
                 math.hypot(float(h["cx"]) - pl[3], float(h["cy"]) - pl[4]), math.hypot(float(x["cx"]) - pl[3], float(x["cy"]) - pl[4])))
rows.sort(reverse=True)
P("  %-34s %5s %4s | %9s | head err%% a err%% | dtheta(h,a) | theta err vs plant: head, a | centre move | centre err vs plant: head, a" % ("ring", "eps", "gap", "d(a+b)/2%"))
for r in rows:
    P("  %-34s %5.2f %4g | %9.4f | %+8.4f %+8.4f | %9.2e | %s | %9.3e | %.4f %.4f" % (
        r[1], r[2], r[3], r[0], r[4], r[5], r[6],
        ("%.2e %.2e" % (r[7], r[8])) if r[7] is not None else "(circle: undefined)", r[9], r[10], r[11]))
n_move = sum(r[0] > 0.01 for r in rows)
n_th = sum(r[6] > 1e-3 for r in rows)
n_th_ell = sum(1 for r in rows if r[6] > 1e-3 and r[2] > 0)
P("  of %d kept-both-ways sweep rings: %d move > 0.01 %% in (a+b)/2; %d move > 1e-3 rad in theta (%d of them with eps > 0, %d on circles); "
  "max 'a err' %.4f %%, max 'head err' %.4f %%; worse-than-head in (a+b)/2: %d" % (
    len(rows), n_move, n_th, n_th_ell, n_th - n_th_ell, max(abs(r[5]) for r in rows), max(abs(r[4]) for r in rows),
    sum(abs(r[5]) > abs(r[4]) for r in rows)))
P()
P("P6 'within 0.1 %% before' clause on every record with a plant (head within 0.1 %% of plant in (a+b)/2, then after):")
for v, var in (("a", va), ("b", vb), ("ab", vab)):
    lost = []
    nb = 0
    for key in head:
        if key[0] not in plant: continue
        h, x = head[key], var[key]
        if "threw" in h or key[1] == "fit1D" and False: continue
        pl = plant[key[0]]; R = (pl[0] + pl[1]) / 2
        if abs(mean_ab(h) / R - 1) <= 0.001:
            nb += 1
            if "threw" in x or abs(mean_ab(x) / R - 1) > 0.001:
                lost.append(key)
    P("  variant %-2s: %d records within 0.1 %% of the plant in head; refused or outside 0.1 %% after: %d%s" % (v, nb, len(lost), "" if not lost else " -> " + ", ".join("%s[%s]" % k for k in lost)))
P("  (records counted: every DUMP record whose case has a plant radius, fit1D and fitBestAvailable alike; the spot/profile cases' plant radius is the planted (a+b)/2)")


P()
P("DETAIL: kept-both-ways sweep profile fits that move > 0.01 %% (variant a = ab): normalised residual of the accepted profile, head vs a (lower = a lower-cost optimum)")
for key in sorted(head):
    if key[1] != "fitBestAvailable-sweep": continue
    h, x = head[key], va[key]
    if h["model"] != "asymmetricGaussian" or x["model"] != "asymmetricGaussian": continue
    if abs(mean_ab(x) - mean_ab(h)) / mean_ab(h) * 100 > 0.01:
        P("  %-34s resid head %s  a %s   sin/sout head %s/%s  a %s/%s   i1 head %s a %s" % (key[0], h["resid"], x["resid"], h["sin"], h["sout"], x["sin"], x["sout"], h["i1"], x["i1"]))
P()
P("DETAIL: the %d sweep rings where head kept the conic (profile refused) and a returns the profile: head's recorded reason" % 16)
cnt = {}
for key in sorted(head):
    if key[1] != "fitBestAvailable-sweep": continue
    h, x = head[key], va[key]
    if h["model"] == "conic" and x["model"] == "asymmetricGaussian":
        cnt[h["fallback"]] = cnt.get(h["fallback"], 0) + 1
for k2, v2 in sorted(cnt.items()): P("  %2d x %s" % (v2, k2))
gap_all = [c for c in d["sweepCases"] if c["gapDegrees"] > 0]
conic_gap = [c for c in gap_all if head[(c["name"], "fitBestAvailable-sweep")]["model"] == "conic"]
P("  (the sweep holds %d gapped rings; head kept the conic on %d of them, smallest R among them %g; unbroken rings: head profile on %d of %d)" % (
    len(gap_all), len(conic_gap), min(c["radius"] for c in conic_gap),
    sum(1 for c in d["sweepCases"] if c["gapDegrees"] == 0 and head[(c["name"], "fitBestAvailable-sweep")]["model"] == "asymmetricGaussian"),
    sum(1 for c in d["sweepCases"] if c["gapDegrees"] == 0)))

open("compare-out.txt", "w").write("\n".join(out) + "\n")
