#!/usr/bin/env python
"""py4DSTEM's phase method on the SAME detected peaks mac4DSTEM used.

Holds detection fixed (peaks exported from tools/phase-map-probe --dump-peaks,
identical origin/calibration/beam-removal/reach) and varies only the INDEXING
method: py4DSTEM ACOM orientation + CrystalPhase NNLS on Al + T1 crystals.
Question: at the 252 T1 positions mac4DSTEM leaves "not indexed", what does
py4DSTEM's method say?
"""
import os, sys, json, numpy as np

# numpy-2 compat shims (py4DSTEM 0.14.19 predates numpy 2 alias removals)
for _n, _v in [("float_",np.float64),("int_",np.int64),("uint",np.uint64),
               ("bool_",np.bool_),("object_",np.object_),("str_",np.str_),
               ("complex_",np.complex128)]:
    if not hasattr(np, _n): setattr(np, _n, _v)

# force the repo's PINNED vendored py4DSTEM (0.14.19), not any installed copy
_VENDORED = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "..", "..", "..", "..")  # fallback; overridden by PYTHONPATH
REPO = "/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM"
sys.path.insert(0, os.path.join(REPO, "References/py4DSTEM-dev"))

PEAKS = sys.argv[1]
LIMIT = int(os.environ.get("LIMIT", "0"))          # 0 = all selected
SEED = 0

import py4DSTEM
assert "References/py4DSTEM-dev" in py4DSTEM.__file__, py4DSTEM.__file__
from py4DSTEM.process.diffraction import Crystal
from py4DSTEM.process.diffraction.crystal_phase import CrystalPhase
try:
    from py4DSTEM import PointListArray
except Exception:
    from emdfile import PointListArray

print("py4DSTEM", py4DSTEM.__version__)

d = json.load(open(PEAKS))
P = d["positions"]
byi = {p["i"]: p for p in P}
qpp = d["qPerPixel"]; reach = d["reach"]

# --- select an evaluation subset (packed into an (N,1) PointListArray) ---
rng = np.random.default_rng(SEED)
def sample(pred, k):
    ids = [p["i"] for p in P if pred(p)]
    ids = sorted(ids)
    if k and len(ids) > k:
        ids = list(rng.choice(ids, size=k, replace=False))
    return ids

t1_ni  = sample(lambda p: p["truth"]==3 and p["verdict"]=="notIndexed", 0)     # all 252
t1_idx = sample(lambda p: p["truth"]==3 and p["verdict"]=="indexed", 250)      # mac indexed T1
t1_mat = sample(lambda p: p["truth"]==3 and p["verdict"]=="matrix", 250)       # mac called matrix
al_pos = sample(lambda p: p["truth"]==0, 300)                                  # Al (specificity)
sel = list(t1_ni) + list(t1_idx) + list(t1_mat) + list(al_pos)
if LIMIT: sel = sel[:LIMIT]
groups = {"T1_notIndexed": set(t1_ni), "T1_indexed": set(t1_idx),
          "T1_matrix": set(t1_mat), "Al": set(al_pos)}
print(f"selected {len(sel)} positions: "
      + ", ".join(f"{k}={len(v)}" for k,v in groups.items()))

# --- build a BraggVectors (N,1) with an IDENTITY calibration, so our peaks
#     (already centered, in Å⁻¹) pass through get_vectors unchanged ---
from py4DSTEM.braggvectors import BraggVectors
from py4DSTEM.data import Calibration
dtype = np.dtype([("qx","float64"),("qy","float64"),("intensity","float64")])
N = len(sel)
pla = PointListArray(dtype=dtype, shape=(N,1))
for n, i in enumerate(sel):
    pk = byi[i]["peaks"]
    if pk:
        arr = np.array([tuple(x) for x in pk], dtype=dtype)
        pla[n,0].add(arr)
cal = Calibration(name="cal")
cal.set_Q_pixel_size(1.0)                                  # peaks already in Å⁻¹
cal.set_origin((np.zeros((N,1)), np.zeros((N,1))))          # peaks already centered
bv = BraggVectors(Rshape=(N,1), Qshape=(128,128), calibration=cal)
bv.set_raw_vectors(pla)
bv.setcal(center=True, ellipse=False, pixel=True, rotate=False)
pla = bv          # feed the BraggVectors to ACOM + CrystalPhase

# --- crystals: Al (fcc a=4.0495) and T1 (Al2CuLi P6/mmm, Thronsen Table 2) ---
al = Crystal(
    positions=np.array([[0,0,0],[0.5,0.5,0],[0.5,0,0.5],[0,0.5,0.5]], dtype=float),
    numbers=np.array([13,13,13,13]),
    cell=4.0495)
t1_positions = np.array([
    [0.333333,0.0,0.0],[0.666667,0.0,0.0],[0.0,0.333333,0.0],[0.0,0.666667,0.0],
    [0.666667,0.666667,0.0],[0.333333,0.333333,0.0],[0.0,0.0,0.4062],[0.0,0.0,0.5938],
    [0.666667,0.333333,0.1612],[0.333333,0.666667,0.8388],[0.333333,0.666667,0.1612],
    [0.666667,0.333333,0.8388],[0.5,0.0,0.3237],[0.5,0.0,0.6763],[0.0,0.5,0.3237],
    [0.0,0.5,0.6763],[0.5,0.5,0.3237],[0.5,0.5,0.6763],[0.0,0.0,0.1993],[0.0,0.0,0.8007],
    [0.333333,0.666667,0.5],[0.666667,0.333333,0.5]], dtype=float)
t1_numbers = np.array([13]*8 + [29]*10 + [3]*4)
t1 = Crystal(positions=t1_positions, numbers=t1_numbers,
             cell=np.array([4.94775,4.94775,14.14499,90,90,120], dtype=float))

KMAX = 1.0
for name, c in [("Al",al),("T1",t1)]:
    c.calculate_structure_factors(KMAX)
    print(f"{name}: {c.g_vec_all.shape[1]} structure-factor reflections to k_max={KMAX}")

# --- ACOM orientation for each crystal on the SAME peaks ---
for name, c in [("Al",al),("T1",t1)]:
    c.orientation_plan(zone_axis_range="full", angle_step_zone_axis=2.0,
                       angle_step_in_plane=2.0, accel_voltage=200e3,
                       progress_bar=False)
    c.match_orientations(pla, min_number_peaks=3, progress_bar=False)
    print(f"{name}: matched orientations")

# --- CrystalPhase NNLS decomposition onto [Al, T1] ---
phase = CrystalPhase([al, t1])
print("crystal_identity:", getattr(phase, "crystal_identity", None))
phase.quantify_phase(pla, corr_kernel_size=0.04, k_max=reach, single_phase=False,
                     progress_bar=False)

W = phase.phase_weights       # (N,1,num_fits)
res = phase.phase_residuals   # (N,1)
rel = phase.phase_reliability
ident = np.array(phase.crystal_identity)   # rows: (crystal_index, orientation_index)
print("phase_weights shape", W.shape, "crystal_identity\n", ident)

# per-fit -> per-crystal weight
def crystal_weights(w):
    aw = w[ident[:,0]==0].sum(); tw = w[ident[:,0]==1].sum()
    return aw, tw

# --- evaluate ---
def which_group(i):
    for g,s in groups.items():
        if i in s: return g
    return "?"

from collections import defaultdict
rows = defaultdict(lambda: {"n":0,"t1_present":0,"t1_dominant":0,"al_dominant":0,
                            "t1w":[], "alw":[], "res":[]})
for n, i in enumerate(sel):
    aw, tw = crystal_weights(W[n,0])
    g = which_group(i)
    r = rows[g]; r["n"]+=1
    tot = aw+tw
    tf = tw/tot if tot>0 else 0.0
    r["t1w"].append(tf); r["alw"].append(aw/tot if tot>0 else 0.0); r["res"].append(res[n,0])
    if tw > 1e-6: r["t1_present"]+=1
    if tw > aw and tw > 1e-6: r["t1_dominant"]+=1
    if aw > tw and aw > 1e-6: r["al_dominant"]+=1

print("\n== py4DSTEM CrystalPhase (Al+T1) on the same peaks ==")
print(f"{'group':16} {'n':>4} {'T1 present':>11} {'T1 dominant':>12} {'Al dominant':>12} {'medT1frac':>9} {'medRes':>8}")
for g in ["T1_notIndexed","T1_indexed","T1_matrix","Al"]:
    r = rows[g]
    if not r["n"]: continue
    def med(a): return float(np.median(a)) if a else float("nan")
    print(f"{g:16} {r['n']:4d} {r['t1_present']:5d}({100*r['t1_present']/r['n']:3.0f}%) "
          f"{r['t1_dominant']:5d}({100*r['t1_dominant']/r['n']:3.0f}%) "
          f"{r['al_dominant']:5d}({100*r['al_dominant']/r['n']:3.0f}%) "
          f"{med(r['t1w']):9.3f} {med(r['res']):8.4f}")
