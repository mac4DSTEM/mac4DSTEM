#!/usr/bin/env python
"""write_swift_fixture.py (detector env) — the committed fixture in a form Swift reads without numpy,
plus the Python reference the Swift learned path is tested against (mac4DSTEMTests/LearnedDiskDetectorTests).
C7 (2026-09-08): the reference is the SHIPPING Core ML package at the model's own size; the 128-px fixture is
fitted to it by `simulate.fit_to` (zero-padded about the probe centre), which the Swift side must reproduce.
  patterns.u16      16 x 128 x 128 little-endian uint16 (the fixture patterns, NATIVE, byte-identical to fixture.npz)
  probe.f32         128 x 128 float32 (the drawn bullseye probe, native)
  inputs-ref.f16    2 x 3 x size x size float16: simulate.model_inputs for patterns 0 and 5 in the FITTED frame
  expected.json     native and fitted probe centre, the fit offset, settings, the asset's name and sha256, and per
                    pattern the raw peak picks (3x3 maxima > threshold on the package's heatmap) and the accepted
                    refined peaks (evaluate.refine + accept) — all positions in the fitted (size x size) frame
Run: $HOME/miniconda3/envs/disk-detector/bin/python fixture/write_swift_fixture.py --coreml <heatmap .mlpackage> --threshold 0.7
"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import simulate as sm, evaluate as ev, export as ex

ap = argparse.ArgumentParser(); ap.add_argument("--coreml", required=True, help="the shipping heatmap .mlpackage (float16 x -> heatmap)")
ap.add_argument("--threshold", type=float, default=0.7); ap.add_argument("--size", type=int, default=None, help="model size (default: the package's metadata)")
ap.add_argument("--batch", type=int, default=32, help="the batch the APP sends (zero-padded): the Neural Engine specialises per shape and a "
                "batch-16 heatmap differs from a batch-32 one by up to 0.035 (check.json 2026-09-08), enough to flip picks at the threshold")
a = ap.parse_args()
import coremltools as ct
m = ct.models.MLModel(a.coreml, compute_units=ct.ComputeUnit.ALL)
size = a.size or int(m.user_defined_metadata.get("size", sm.S))
out = os.path.join(HERE, "swift"); os.makedirs(out, exist_ok=True)
z = np.load(os.path.join(HERE, "fixture.npz")); e = json.load(open(os.path.join(HERE, "expected.json")))
pats = z["patterns"].astype("<u2"); probe = z["probe"].astype(np.float64); c = tuple(e["probe_centre"])
pats.tofile(os.path.join(out, "patterns.u16")); probe.astype("<f4").tofile(os.path.join(out, "probe.f32"))
xs, ccs = [], []
probef = cf = None
for p in pats:
    pf, probef, cf = sm.fit_fixture_to(p.astype(np.float64), probe, c, size)
    k = sm.flat_kernel(probef, cf); cc = sm.cross_correlation(pf, k)
    xs.append(sm.model_inputs(pf, probef, cc)); ccs.append(cc)
xs = np.stack(xs).astype(np.float32)
xs[[0, 5]].astype("<f2").tofile(os.path.join(out, "inputs-ref.f16"))
xb = np.concatenate([xs, np.zeros((a.batch - len(xs),) + xs.shape[1:], np.float32)]) if len(xs) < a.batch else xs
H = np.asarray(m.predict({"x": xb.astype(np.float16)})["heatmap"], np.float32)[: len(xs)]   # the app's own batch shape
H = H[:, 0] if H.ndim == 4 else H
S = ev.SETTINGS; per = []
for i in range(len(xs)):
    cand = ev.pick(H[i], a.threshold, top_k=10_000)
    acc = ev.accept(ev.refine(cand, ccs[i], S["sigma_cc"]), S["minPeakSpacing"], S["edgeBoundary"], size=size)
    per.append(dict(picks=[[int(r_), int(c_), float(s_)] for r_, c_, s_ in cand], accepted=[[float(v[0]), float(v[1]), float(v[3])] for v in acc]))
r0, c0 = sm.fit_offset(c, size)
json.dump(dict(count=len(xs), native_size=int(pats.shape[1]), size=size, probe_centre=list(c), probe_centre_fit=[float(cf[0]), float(cf[1])],
               fit_offset=[int(r0), int(c0)], probe_radius=float(sm.probe_radius(probe, c)), threshold=a.threshold, settings=S,
               runtime="coreml", compute_units="all", batch=a.batch, asset=os.path.basename(a.coreml), asset_sha256=ex.sha256_tree(a.coreml),
               inputs_ref_indices=[0, 5], patterns=per), open(os.path.join(out, "expected.json"), "w"), indent=1)
print("swift fixture:", len(xs), "patterns at", size, "px; picks", sum(len(p["picks"]) for p in per), "accepted", sum(len(p["accepted"]) for p in per))
