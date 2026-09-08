#!/usr/bin/env python
"""label_centres.py — the click tool for the frozen hand-labelled test set (C6, 2026-09-07).

Shows one scan position at a time in its NATIVE frame (the full stored pattern, e.g. 250x250 for
the bullseye cube, 128x128 for WS2 — C7 2026-09-07: labels are recorded in native pattern
coordinates, not a model-size crop, so one labels file scores any model size), log display. Left
click adds a disk CENTRE, right click removes the nearest, n/p next/previous position, w writes, q
writes and quits. Positions are drawn once from a seeded RNG so the set is frozen before anyone
looks at a heatmap; it is NEVER used for selection. Output JSON: cube, dataset, ingredient,
frame: "native", positions [{ry, rx, centres [[row, col], ...]}], and its own sha256 over the
positions — the number that goes into the evidence file with the counts. evaluate.py --labels maps
these native centres into whatever model frame it is scoring (`simulate.fit_offset`). The file is
the owner's data (tools/disk-detector/labels/ is gitignored).

    run.sh label --cube <h5> --dataset 4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data \\
                 --ingredient bullseye --out labels/bullseye-2026-09-08.json [--n 40] [--seed 1]
"""
import argparse, hashlib, json, os, sys
import numpy as np, h5py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm

ap = argparse.ArgumentParser()
ap.add_argument("--cube", required=True); ap.add_argument("--dataset", required=True)
ap.add_argument("--ingredient", choices=["bullseye", "ws2"], required=True); ap.add_argument("--out", required=True)
ap.add_argument("--n", type=int, default=40); ap.add_argument("--seed", type=int, default=1)
a = ap.parse_args()

if os.path.exists(a.out):
    L = json.load(open(a.out))
    if L.get("frame") != "native":
        raise SystemExit(f"{a.out} has frame {L.get('frame')!r}, not 'native' — it was started by an "
                          f"older label_centres.py in the model-frame crop convention; this tool only "
                          f"continues a 'native'-frame labels file (C7 2026-09-07). Start a new --out.")
else:
    with h5py.File(a.cube, "r") as f:
        sh = f[a.dataset].shape
    rng = np.random.default_rng(a.seed)
    pos = sorted({(int(y), int(x)) for y, x in zip(rng.integers(sh[0], size=4 * a.n), rng.integers(sh[1], size=4 * a.n))})[: a.n]
    L = dict(cube=os.path.abspath(a.cube), dataset=a.dataset, ingredient=a.ingredient, frame="native",
             seed=a.seed, positions=[dict(ry=y, rx=x, centres=[]) for y, x in pos])

def pattern(i):
    # the NATIVE pattern, no crop or pad (C7 2026-09-07): centres are clicked and stored in this
    # frame directly, so the same labels file scores a 128-px and a 256-px model (evaluate.py maps
    # native -> whichever model frame it is scoring, via simulate.fit_offset).
    with h5py.File(a.cube, "r") as f:
        return sm.to_counts(f[a.dataset][L["positions"][i]["ry"], L["positions"][i]["rx"]].astype(np.float64))

def save():
    L["sha256"] = hashlib.sha256(json.dumps(L["positions"], sort_keys=True).encode()).hexdigest()
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(L, open(a.out, "w"), indent=1)
    n = sum(len(p["centres"]) for p in L["positions"]); done = sum(1 for p in L["positions"] if p["centres"])
    print(f"wrote {a.out}: {len(L['positions'])} positions ({done} with labels), {n} centres, sha256 {L['sha256'][:16]}…")

import matplotlib; matplotlib.use("MacOSX"); import matplotlib.pyplot as plt
state = dict(i=0)
fig, ax = plt.subplots(figsize=(7, 7))
def draw():
    ax.clear(); p = pattern(state["i"]); ax.imshow(np.log1p(np.maximum(p - p.min(), 0)), cmap="gray")
    c = np.array(L["positions"][state["i"]]["centres"]).reshape(-1, 2)
    if len(c): ax.scatter(c[:, 1], c[:, 0], s=80, facecolors="none", edgecolors="red")
    ax.set_title(f"{state['i'] + 1}/{len(L['positions'])}  scan ({L['positions'][state['i']]['ry']},{L['positions'][state['i']]['rx']})  {len(c)} centres — click add, right-click remove, n/p, w, q")
    ax.set_axis_off(); fig.canvas.draw_idle()
def on_click(e):
    if e.inaxes is not ax or e.xdata is None: return
    cs = L["positions"][state["i"]]["centres"]
    if e.button == 1: cs.append([float(e.ydata), float(e.xdata)])
    elif e.button == 3 and cs:
        d = [np.hypot(r - e.ydata, c - e.xdata) for r, c in cs]; cs.pop(int(np.argmin(d)))
    draw()
def on_key(e):
    if e.key == "n": state["i"] = min(state["i"] + 1, len(L["positions"]) - 1); draw()
    elif e.key == "p": state["i"] = max(state["i"] - 1, 0); draw()
    elif e.key == "w": save()
    elif e.key == "q": save(); plt.close(fig)
fig.canvas.mpl_connect("button_press_event", on_click); fig.canvas.mpl_connect("key_press_event", on_key)
draw(); plt.show()
