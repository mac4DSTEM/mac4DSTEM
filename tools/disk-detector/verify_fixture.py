#!/usr/bin/env python
"""verify_fixture.py — prove the fixture before any net sees it (§3a step 1).

Runs in the pinned py4DSTEM environment. Two claims, both must hold:
  1. simulate.py's flat kernel and cross-correlation equal py4DSTEM's own
     (Probe.get_probe_kernel_flat, get_cross_correlation) on the fixture, pixel for pixel;
  2. py4DSTEM's classical detector at the 2026-09-05 bullseye settings (flat kernel from the
     given probe, minPeakSpacing 8, edgeBoundary 6, minRelativeIntensity 0.05, sigma_cc 2,
     subpixel poly) recovers the drawn centres: >= RECALL_MIN of the eligible truth within TOL px, and the matched
     residual's median is <= RESIDUAL_MEDIAN_MAX px (where a disk is found, it is where the truth says).
Eligible truth = relative intensity >= ELIGIBLE_MIN and centre >= edgeBoundary + 2 px from every edge
(the detector's own edge exclusion is not a simulator defect).
py4DSTEM is the reference here: no tools/ harness runs the app's detector on an arbitrary H5.

--break <mode> applies a deliberate defect (see simulate.make_fixture) and must make this FAIL.
Exit 0 on pass, 1 on fail.
"""
import argparse, hashlib, json, os, sys, warnings
import numpy as np
warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm
from py4DSTEM.braggvectors import Probe, find_Bragg_disks
from py4DSTEM.process.utils import get_cross_correlation

SETTINGS = dict(minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0.05, subpixel="poly", sigma_cc=2, maxNumPeaks=70)
TOL = 1.5          # px, match radius: poly refinement on a sigma-2 smoothed correlation of a tilted ring disk is not a 0.5 px measurement
ELIGIBLE_MIN = 0.10
RECALL_MIN = 0.90
RESIDUAL_MEDIAN_MAX = 0.5   # px, where a disk is found it must be where the truth says
PORT_TOL = 1e-9    # relative to the correlation maximum

ap = argparse.ArgumentParser()
ap.add_argument("--fixture", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture"))
ap.add_argument("--break", dest="break_mode", choices=["shifted-truth", "swapped-axes", "dropped-disk", "wrong-probe"])
a = ap.parse_args()

z = np.load(os.path.join(a.fixture, "fixture.npz"))
ex = json.load(open(os.path.join(a.fixture, "expected.json")))
patterns, probe, centre, truth = z["patterns"], z["probe"].astype(np.float64), tuple(ex["probe_centre"]), ex["truth"]
digest = hashlib.sha256(patterns.tobytes()).hexdigest()
print(f"fixture {patterns.shape} sha256 {digest[:16]} (expected {ex['patterns_sha256'][:16]})")
ok = digest == ex["patterns_sha256"]
if a.break_mode:
    print(f"BREAK MODE: {a.break_mode} — this run must FAIL")
    patterns, probe, centre, truth = sm.make_fixture(break_mode=a.break_mode)
    probe = probe.astype(np.float64)

# 1. port parity
k_py = Probe.get_probe_kernel_flat(probe, origin=centre)
k_me = sm.flat_kernel(probe, centre)
kd = np.abs(k_py - k_me).max()
port_worst = kd / k_py.max()
recalls, residuals, false_pos, eligible_total, recovered_total = [], [], [], 0, 0
edge = SETTINGS["edgeBoundary"] + 2
for i, t in enumerate(truth):
    p = patterns[i].astype(np.float64)
    cc_py = get_cross_correlation(p, k_py); cc_me = sm.cross_correlation(p, k_me)
    port_worst = max(port_worst, np.abs(cc_py - cc_me).max() / cc_py.max())
    q = find_Bragg_disks(p, k_py, **SETTINGS)
    peaks = np.stack([q.data["qx"], q.data["qy"]], axis=1) if len(q.data) else np.zeros((0, 2))
    cen = np.array(t["centres"]).reshape(-1, 2); inten = np.array(t["intensities"])
    elig = (inten >= ELIGIBLE_MIN * inten.max()) & (cen.min(axis=1) >= edge) & (cen.max(axis=1) < sm.S - edge)
    used = np.zeros(len(peaks), bool); hit = 0
    for r, c in cen[elig]:
        if len(peaks) == 0: break
        d = np.hypot(peaks[:, 0] - r, peaks[:, 1] - c); d[used] = np.inf
        j = int(np.argmin(d))
        if d[j] <= TOL:
            hit += 1; used[j] = True; residuals.append(d[j])
    eligible_total += int(elig.sum()); recovered_total += hit
    false_pos.append(int((~used).sum()))
    recalls.append(hit / max(elig.sum(), 1))
recall = recovered_total / max(eligible_total, 1)
res = np.array(residuals) if residuals else np.zeros(1)
print(f"port parity vs py4DSTEM: worst relative |diff| {port_worst:.2e} (limit {PORT_TOL:.0e})")
print(f"classical recovery at {SETTINGS}: {recovered_total}/{eligible_total} eligible truth within {TOL} px = {recall:.4f} (limit {RECALL_MIN})")
print(f"  per-pattern recall min {min(recalls):.3f}; matched residual median {np.median(res):.3f} px (limit {RESIDUAL_MEDIAN_MAX}), max {res.max():.3f} px; unmatched peaks per pattern median {int(np.median(false_pos))} max {max(false_pos)}")
ok = ok and port_worst <= PORT_TOL and recall >= RECALL_MIN and np.median(res) <= RESIDUAL_MEDIAN_MAX
print("FIXTURE PASS" if ok else "FIXTURE FAIL")
sys.exit(0 if ok else 1)
