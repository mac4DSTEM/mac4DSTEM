#!/usr/bin/env python3
"""Join the four variants' search logs; classify; print counts and the candidate plants.
usage: an.py <tag> [tag...]   (tag = the suffix of logs/search-<variant>-<tag>.log)"""
import sys, os, collections
SP = os.environ["SP"]
V = ["head", "a", "b", "ab"]
def parse(line):
    d = {}
    for kv in line.strip().split("|")[1:]:
        k, _, v = kv.partition("=")
        d[k] = v
    return d
data = {v: {} for v in V}
for tag in sys.argv[1:]:
    for v in V:
        with open(f"{SP}/lanes/F/logs/search-{v}-{tag}.log") as f:
            for line in f:
                if line.startswith("ROW|"):
                    d = parse(line); data[v][d["id"]] = d
ids = [i for i in data["head"] if all(i in data[v] for v in V)]
def fl(d, k): return float(d[k]) if k in d else float("nan")
def wrong(d): return d["status"] == "profile" and abs(fl(d, "dR")) > 0.01
def right(d): return d["status"] == "profile" and abs(fl(d, "dR")) <= 0.001
def minsig(d): return min(fl(d, "sin"), fl(d, "sout"))
def kind(d):
    if not wrong(d): return None
    if minsig(d) <= 0.30: return "dead"
    if min(fl(d, "sin"), fl(d, "sout")) >= 1.0: return "drift"
    return "other"
print(f"plants joined: {len(ids)}")
for v in V:
    c = collections.Counter(data[v][i]["status"] for i in ids)
    print(f"  {v}: status {dict(c)}; wrong {sum(wrong(data[v][i]) for i in ids)}; within0.1% {sum(right(data[v][i]) for i in ids)}")
# by noise and gap
for noise in sorted({data['head'][i]['noise'] for i in ids}):
    for gap in ("0", "60"):
        sub = [i for i in ids if data["head"][i]["noise"] == noise and data["head"][i]["gap"] == gap]
        k = collections.Counter(kind(data["head"][i]) for i in sub)
        print(f"  noise {noise} gap {gap}: {len(sub)} plants, head wrong {sum(wrong(data['head'][i]) for i in sub)} (dead {k['dead']}, drift {k['drift']}, other {k['other']})")
for size in sorted({data['head'][i]['size'] for i in ids}, key=int):
    sub = [i for i in ids if data["head"][i]["size"] == size]
    k = collections.Counter(kind(data["head"][i]) for i in sub)
    print(f"  size {size}: {len(sub)} plants, head wrong {sum(wrong(data['head'][i]) for i in sub)} (dead {k['dead']}, drift {k['drift']}, other {k['other']})")
# rescues across all head-wrong
hw = [i for i in ids if wrong(data["head"][i])]
print(f"head-wrong {len(hw)}: under a within 0.1%: {sum(right(data['a'][i]) for i in hw)}, a wrong: {sum(wrong(data['a'][i]) for i in hw)}; "
      f"b wrong: {sum(wrong(data['b'][i]) for i in hw)}, b conic: {sum(data['b'][i]['status']=='conic' for i in hw)}, b threw: {sum(data['b'][i]['status']=='THREW' for i in hw)}; "
      f"ab wrong: {sum(wrong(data['ab'][i]) for i in hw)}")
# right on head turned wrong / not right
hr = [i for i in ids if right(data["head"][i])]
for v in V[1:]:
    print(f"head within 0.1% ({len(hr)}): under {v}: not within 0.1% {sum(not right(data[v][i]) for i in hr)}, wrong {sum(wrong(data[v][i]) for i in hr)}, conic {sum(data[v][i]['status']=='conic' for i in hr)}, threw {sum(data[v][i]['status']=='THREW' for i in hr)}")
def row(i):
    out = [i]
    for v in V:
        d = data[v][i]
        if d["status"] == "profile":
            out.append(f"{v}:P dR={fl(d,'dR'):+.4f} dba={fl(d,'dba'):+.4f} c={fl(d,'cerr'):.2f} s={fl(d,'sin'):.2f}/{fl(d,'sout'):.2f} I1={fl(d,'I1'):.3f}")
        elif d["status"] == "conic":
            out.append(f"{v}:C dR={fl(d,'dR'):+.4f} dba={fl(d,'dba'):+.4f} c={fl(d,'cerr'):.2f}")
        else:
            out.append(f"{v}:{d['status']}")
    return "\n    ".join(out)
def cand(name, pred):
    cs = [i for i in ids if pred(i)]
    # prefer big error, small size
    cs.sort(key=lambda i: (int(data['head'][i]['size']), int(data['head'][i]['R']), -abs(fl(data['head'][i], 'dR'))))
    print(f"\n{name}: {len(cs)} plants")
    for i in cs[:int(os.environ.get('TOP', '12'))]: print("  " + row(i))
H, A, B, AB = (data[v] for v in V)
cand("DEAD (head wrong, min sigma <= 0.30; a within 0.1%; b not wrong-profile)",
     lambda i: kind(H[i]) == "dead" and right(A[i]) and not wrong(B[i]))
cand("DEAD, b conic only", lambda i: kind(H[i]) == "dead" and right(A[i]) and B[i]["status"] == "conic")
cand("DRIFT (head wrong, both sigma >= 1; a within 0.1%; b still wrong)",
     lambda i: kind(H[i]) == "drift" and right(A[i]) and wrong(B[i]))
cand("OTHER wrong on head", lambda i: kind(H[i]) == "other")
