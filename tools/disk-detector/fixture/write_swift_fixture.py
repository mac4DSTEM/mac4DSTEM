#!/usr/bin/env python
"""write_swift_fixture.py (detector env) — the committed fixture in a form Swift reads without numpy,
plus the Python reference the Swift learned path is tested against (mac4DSTEMTests/LearnedDiskDetectorTests):
  patterns.u16      16 x 128 x 128 little-endian uint16 (the fixture patterns, byte-identical to fixture.npz)
  probe.f32         128 x 128 float32 (the drawn bullseye probe)
  inputs-ref.f16    2 x 3 x 128 x 128 float16: simulate.model_inputs for patterns 0 and 5
  expected.json     probe centre/radius, settings, and per pattern the raw peak picks (3x3 maxima > threshold
                    on the committed asset's heatmap) and the accepted refined peaks (evaluate.refine + accept)
Run: $HOME/miniconda3/envs/disk-detector/bin/python fixture/write_swift_fixture.py --asset <heatmap .aimodel>
"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm, evaluate as ev, check_export as ce

ap = argparse.ArgumentParser(); ap.add_argument("--asset", required=True); ap.add_argument("--threshold", type=float, default=0.9)
a = ap.parse_args()
out = os.path.join(HERE, "swift"); os.makedirs(out, exist_ok=True)
z = np.load(os.path.join(HERE, "fixture.npz")); e = json.load(open(os.path.join(HERE, "expected.json")))
pats = z["patterns"].astype("<u2"); probe = z["probe"].astype(np.float64); c = tuple(e["probe_centre"])
pats.tofile(os.path.join(out, "patterns.u16")); probe.astype("<f4").tofile(os.path.join(out, "probe.f32"))
k = sm.flat_kernel(probe, c)
xs = np.stack([sm.model_inputs(p.astype(np.float64), probe, sm.cross_correlation(p.astype(np.float64), k)) for p in pats]).astype(np.float32)
xs[[0, 5]].astype("<f2").tofile(os.path.join(out, "inputs-ref.f16"))
x = np.concatenate([xs, np.zeros((32 - len(xs),) + xs.shape[1:], np.float32)])
work = os.path.join(out, "work"); os.makedirs(work, exist_ok=True)
if os.path.exists(os.path.join(work, "x.npz")): os.remove(os.path.join(work, "x.npz"))
r = ce.run_coreai_subprocess(a.asset, x, "ane", "heatmap", work)
H = r["heatmap"]; H = (H[:, 0] if H.ndim == 4 else H)[: len(xs)]
S = ev.SETTINGS; per = []
for i in range(len(xs)):
    cand = ev.pick(H[i], a.threshold, top_k=10_000)
    cc = sm.cross_correlation(pats[i].astype(np.float64), k)
    acc = ev.accept(ev.refine(cand, cc, S["sigma_cc"]), S["minPeakSpacing"], S["edgeBoundary"])
    per.append(dict(picks=[[int(r_), int(c_), float(s_)] for r_, c_, s_ in cand], accepted=[[float(v[0]), float(v[1]), float(v[3])] for v in acc]))
json.dump(dict(count=len(xs), size=sm.S, probe_centre=list(c), probe_radius=float(sm.probe_radius(probe, c)), threshold=a.threshold,
               settings=S, asset=os.path.basename(a.asset), inputs_ref_indices=[0, 5], patterns=per), open(os.path.join(out, "expected.json"), "w"), indent=1)
import shutil; shutil.rmtree(work)
print("swift fixture:", len(xs), "patterns; picks", sum(len(p["picks"]) for p in per), "accepted", sum(len(p["accepted"]) for p in per))
