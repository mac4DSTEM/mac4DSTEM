#!/usr/bin/env python
"""check_export.py — each export against PyTorch, pixel for pixel, on the same inputs (§3a step 2).

Inputs: the committed fixture (16 patterns) plus simulated samples, run through
  (a) the PyTorch net in float32 (the reference) and in float16 (what a float16 runtime can hope for),
  (b) the Core AI asset through coreai-core's Python runtime (coreai.runtime), per compute-unit
      preference — neural engine, cpu only, gpu — with the first-load specialisation and per-batch
      times, and
  (c) every Core ML package through coremltools' predict — the shipping heatmap package first of all (C7).
Reports max |diff| of the heatmap in float16 terms (the float16 reference's own error against float32
is printed beside it) and whether the in-graph peaks equal the numpy peak-picking.

    run.sh check --run <run dir> [--batches 20]
"""
from __future__ import annotations
import argparse, asyncio, json, os, sys, time
os.environ.setdefault("USE_OS_COREAI", "1")   # macOS 27's own Core AI runtime: the in-package runtime has no compute-unit delegates
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm, train as tr, export as ex

def load_inputs(run, batch, n_batches, seed=4242, size=None):
    """Fixture first (fitted to `size` through fit_to when it differs from the fixture's native 128
    -- C7 2026-09-07), then simulated samples at `size` with real ingredients (the run's own npz).
    `size` defaults to the run's own config.json (falls back to sm.S for an older run)."""
    cfg = json.load(open(os.path.join(run, "config.json")))
    size = size if size is not None else int(cfg.get("config", {}).get("size", sm.S))
    z = np.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture", "fixture.npz"))
    e = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture", "expected.json")))
    probe_centre = tuple(e["probe_centre"])
    xs = []
    for p in z["patterns"]:
        pf, probef, cf = sm.fit_fixture_to(p.astype(np.float64), z["probe"].astype(np.float64), probe_centre, size)
        fk = sm.flat_kernel(probef, cf)
        xs.append(sm.model_inputs(pf, probef, sm.cross_correlation(pf, fk)))
    probes, bgs = tr.load_ingredients(cfg["args"]["ingredients"])
    rng = np.random.default_rng(seed)
    while len(xs) < batch * n_batches:
        probe, centre, _ = probes[rng.integers(len(probes))]
        s = sm.simulate_one(rng, probe, centre, sm.SimConfig(size=size), background=bgs[rng.integers(len(bgs))] if rng.random() < 0.7 else None)
        xs.append(sm.model_inputs(s.pattern, s.probe, s.correlation))
    return np.stack(xs[: batch * n_batches]).astype(np.float32)

def peak_agreement(got, ref, tol=1.0):
    """got/ref: per-input arrays of (row, col[, score]). Fraction of reference peaks with a got peak
    within tol px, the fraction of got peaks that match nothing, and the count difference."""
    hit = tot = extra = ntot = 0; diffs = []
    for g, rf in zip(got, ref):
        g = np.asarray(g).reshape(-1, g.shape[-1] if len(g) else 2)[:, :2]; rf = np.asarray(rf).reshape(-1, 3)[:, :2]
        used = np.zeros(len(g), bool)
        for r, c in rf:
            tot += 1
            if len(g):
                d = np.hypot(g[:, 0] - r, g[:, 1] - c); d[used] = np.inf; j = int(np.argmin(d))
                if d[j] <= tol: hit += 1; used[j] = True
        extra += int((~used).sum()); ntot += len(g); diffs.append(len(g) - len(rf))
    return dict(recall=hit / max(tot, 1), extra=extra / max(ntot, 1), count_diff_median=float(np.median(diffs)) if diffs else 0.0)


def report(name, ref, got, scale_note=""):
    d = np.abs(ref.astype(np.float64) - got.astype(np.float64))
    print(f"  {name}: max |diff| {d.max():.3e}, mean {d.mean():.3e}, 99.9th pct {np.percentile(d, 99.9):.3e}{scale_note}")
    return d.max()

WORKER_PREFER = {"cpu": "cpu", "ane": "ane", "gpu": "gpu", "default": "default"}

async def _worker(asset, prefer, xin, xout, function, state_probe=None):
    from coreai.runtime import AIModel, NDArray, SpecializationOptions, ComputeUnitKind
    if prefer == "cpu": opts = SpecializationOptions.cpu_only()
    elif prefer == "default": opts = SpecializationOptions.default()
    else: opts = SpecializationOptions.from_preferred_compute_unit_kind({"ane": ComputeUnitKind.neural_engine, "gpu": ComputeUnitKind.gpu}[prefer]())
    x = np.load(xin)["x"]
    t0 = time.perf_counter(); model = await AIModel.load(asset, specialization_options=opts); load_s = time.perf_counter() - t0
    fn = model.load_function(function); names = fn.desc.input_names
    dt = str(fn.desc.input_descriptor(names[0]).dtype); npdt = np.float16 if "16" in dt else np.float32
    batch = fn.desc.input_descriptor(names[0]).shape[0]
    if state_probe is not None:
        sp = model.load_function("set_probe"); await sp(inputs={sp.desc.input_names[0]: NDArray(np.ascontiguousarray(state_probe.astype(npdt)))})
    outs, times = {}, []
    for b in range(0, len(x), batch):
        xb = np.ascontiguousarray(x[b:b + batch].astype(npdt))
        t0 = time.perf_counter(); out = await fn(inputs={names[0]: NDArray(xb)}); times.append(time.perf_counter() - t0)
        for k, v in out.items(): outs.setdefault(k, []).append(v.numpy().astype(np.float32))
    np.savez(xout, load_s=load_s, times=np.array(times), options=str(opts), input_dtype=dt, batch=batch, **{k: np.concatenate(v) for k, v in outs.items()})


def run_coreai_subprocess(asset, x, prefer, function, workdir, state_probe=None):
    """Runs the asset in a child process; a Neural Engine program-load failure kills the process
    (seen 2026-09-06, com.apple.appleneuralengine code 6, 0x10004), so the parent must survive it."""
    import subprocess
    xin, xout = os.path.join(workdir, "x.npz"), os.path.join(workdir, f"out-{os.path.basename(asset)}-{prefer}.npz")
    if not os.path.exists(xin): np.savez(xin, x=x)
    if os.path.exists(xout): os.remove(xout)
    cmd = [sys.executable, os.path.abspath(__file__), "--worker", asset, prefer, xin, xout, function]
    if state_probe is not None:
        np.save(os.path.join(workdir, "probe.npy"), state_probe); cmd.append(os.path.join(workdir, "probe.npy"))
    for attempt in (1, 2):
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if r.returncode == 0 and os.path.exists(xout): break
        err = [l for l in (r.stderr + r.stdout).splitlines() if "Error" in l or "error" in l or "assertion" in l]
        msg = err[0][:300] if err else (r.stderr[-300:] or "no output")
        # The runtime's cache goes stale between processes (~/Library/Caches/coreai-cache: written by
        # a specialisation in one client, then `load_function` in the next fails with the generic
        # ObjC error; recorded 2026-09-06/07, seen again 2026-09-07 21:25 one call after a passing
        # check). The Swift side purges its cache entry once and retries; this is the same remedy.
        cache = os.path.expanduser("~/Library/Caches/coreai-cache")
        if attempt == 1 and "GenericObjCError" in msg and os.path.isdir(cache):
            stale = cache + f".stale-{time.strftime('%Y%m%d-%H%M%S')}"; os.rename(cache, stale)
            print(f"  coreai cache stale ({msg[:80]}); moved to {stale}, retrying once", flush=True); continue
        raise RuntimeError(f"exit {r.returncode}: " + msg)
    z = np.load(xout, allow_pickle=False)
    return {k: (z[k] if z[k].ndim else z[k].item()) for k in z.files}


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        asset, prefer, xin, xout, function = sys.argv[2:7]
        probe = np.load(sys.argv[7]) if len(sys.argv) > 7 else None
        asyncio.run(_worker(asset, prefer, xin, xout, function, probe)); return
    ap = argparse.ArgumentParser(); ap.add_argument("--run", required=True); ap.add_argument("--batches", type=int, default=8)
    ap.add_argument("--prefer", nargs="+", default=["ane", "cpu", "gpu"])
    ap.add_argument("--skip-coreai", action="store_true"); ap.add_argument("--skip-coreml", action="store_true")
    ap.add_argument("--tolerance", type=float, default=0.1, help="max |heatmap diff| vs PyTorch float16 any runtime may show (the heatmap is in [0,1]; run3's ANE showed 0.062 against a 0.009 float16 floor)")
    ap.add_argument("--min-peak-recall", type=float, default=0.98, help="fraction of numpy's peaks an in-graph peak output must reproduce within 1 px")
    a = ap.parse_args()
    meta = json.load(open(os.path.join(a.run, "export", "export.json")))
    B = meta["batch"]; size = meta.get("size", ex.run_size(a.run))
    x = load_inputs(a.run, B, a.batches, size=size)
    print(f"inputs {x.shape} (fixture 16 + simulated), batch {B}, size {size}")
    model = ex.load_model(a.run).eval()
    det = ex.Detector(model, threshold=meta["threshold"], top_k=meta["top_k"], size=size).eval()
    with torch.no_grad():
        ref = [det(torch.from_numpy(x[b:b + B])) for b in range(0, len(x), B)]
        heat32 = torch.cat([r[0] for r in ref]).numpy(); coords32 = torch.cat([r[1] for r in ref]).numpy(); scores32 = torch.cat([r[2] for r in ref]).numpy()
        det16 = ex.Detector(ex.load_model(a.run).eval().half(), threshold=meta["threshold"], top_k=meta["top_k"], size=size).eval()
        heat16 = torch.cat([det16(torch.from_numpy(x[b:b + B]).half())[0].float() for b in range(0, len(x), B)]).numpy()
    print("PyTorch float16 vs float32 (the floor any float16 runtime can reach):")
    fp16_floor = report("heatmap", heat32, heat16)
    npk = [tr.pick_peaks(heat32[i, 0], meta["threshold"], meta["top_k"]) for i in range(len(x))]
    agree = np.mean([set(map(tuple, np.round(coords32[i][scores32[i] > 0]).astype(int))) == set(map(tuple, npk[i][:, :2].astype(int))) for i in range(len(x))])
    print(f"in-graph peak-picking == numpy pick_peaks on {agree * 100:.1f}% of inputs (float32 PyTorch)")
    results = dict(inputs=list(x.shape), batch=B, fp16_floor=float(fp16_floor), peaks_agree_torch=float(agree))
    work = os.path.join(a.run, "export", "check-work"); os.makedirs(work, exist_ok=True)
    if not a.skip_coreai:
        for key, asset in sorted(meta.get("coreai_assets", {}).items()):
            variant, bsz = key.rsplit("-b", 1); bsz = int(bsz)
            for prefer in a.prefer:
                tag = f"coreai {key} [{prefer}]"
                try:
                    r = run_coreai_subprocess(asset, x, prefer, variant, work)
                    t = r["times"][1:] if len(r["times"]) > 1 else r["times"]
                    print(f"{tag}: load+specialise {r['load_s']:.2f} s; per batch of {bsz}: median {np.median(t) * 1000:.2f} ms, min {t.min() * 1000:.2f} ms -> {np.median(t) / bsz * 1000:.3f} ms/pattern, {np.median(t) / bsz * 65536:.1f} s per 65 536 (input {r['input_dtype']})")
                    d = report("heatmap vs PyTorch float32", heat32, r["heatmap"]); d16 = report("heatmap vs PyTorch float16", heat16, r["heatmap"])
                    res = dict(load_s=float(r["load_s"]), ms_per_batch_median=float(np.median(t) * 1000), ms_per_pattern=float(np.median(t) / bsz * 1000), s_per_65536=float(np.median(t) / bsz * 65536), max_diff_fp32=float(d), max_diff_fp16=float(d16), options=str(r["options"]))
                    got = None
                    if "coords" in r: got = [r["coords"][i][r["scores"][i] > 0] for i in range(len(x))]; what = "in-graph top-k peaks"
                    if "scoremap" in r: got = [np.argwhere(r["scoremap"][i, 0] > 0).astype(np.float32) for i in range(len(x))]; what = "score-map non-zeros"
                    if got is not None:
                        pa = peak_agreement(got, npk)
                        print(f"  {what} vs numpy peaks on the float32 heatmap: {pa['recall'] * 100:.1f}% of numpy peaks found within 1 px, {pa['extra'] * 100:.1f}% extra, count diff median {pa['count_diff_median']:+.0f}")
                        res["peaks"] = pa
                    results[f"{key}_{prefer}"] = res
                except Exception as err:
                    print(f"{tag} FAILED: {err}"); results[f"{key}_{prefer}"] = dict(error=str(err)[:400])
        if meta.get("coreai_stateful"):
            try:
                r = run_coreai_subprocess(meta["coreai_stateful"], x[:B][:, [0, 2]], "default", "detect", work, state_probe=x[0:1, 1:2])
                spread = np.abs(x[:B, 1] - x[0, 1]).max()
                d = report(f"stateful detect (probe as model state, set once) vs PyTorch float32, first batch (probe channel spread {spread:.2e})", heat32[:B], r["heatmap"])
                results["coreai_stateful"] = dict(max_diff=float(d), probe_spread=float(spread), load_s=float(r["load_s"]))
            except Exception as err:
                print(f"Core AI stateful FAILED: {err}"); results["coreai_stateful"] = dict(error=str(err)[:400])
    if not a.skip_coreml:
        import coremltools as ct
        def predict(m, xb):
            try: return m.predict({"x": xb})["heatmap"]
            except Exception: return m.predict({"x": xb.astype(np.float16)})["heatmap"]   # a float16-input package (C7 heatmap)
        # every Core ML package the export wrote: the detect variant (macOS 15), the shipping heatmap
        # package and the several-shape attempt (C7). The flexible-batch ones are also run at batch 1.
        for key in ("coreml", "coreml_heatmap", "coreml_heatmap_shapes"):
            if not meta.get(key): continue
            for cu in [("all", ct.ComputeUnit.ALL), ("cpu_and_ne", ct.ComputeUnit.CPU_AND_NE), ("cpu_only", ct.ComputeUnit.CPU_ONLY)]:
                tag = f"{key} [{cu[0]}]"
                try:
                    t0 = time.perf_counter(); m = ct.models.MLModel(meta[key], compute_units=cu[1]); load_s = time.perf_counter() - t0
                    heats, times = [], []
                    for b in range(0, len(x), B):
                        t0 = time.perf_counter(); out = predict(m, x[b:b + B]); times.append(time.perf_counter() - t0); heats.append(np.asarray(out, np.float32))
                    h = np.concatenate(heats); t = np.array(times[1:]) if len(times) > 1 else np.array(times)
                    print(f"Core ML {tag}: load {load_s:.2f} s; per batch median {np.median(t) * 1000:.2f} ms -> {np.median(t) / B * 1000:.3f} ms/pattern (coremltools predict, includes Python overhead)")
                    d = report("heatmap vs PyTorch float32", heat32, h); d16 = report("heatmap vs PyTorch float16", heat16, h)
                    res = dict(load_s=load_s, ms_per_pattern=float(np.median(t) / B * 1000), max_diff=float(d), max_diff_fp16=float(d16))
                    if key != "coreml":   # flexible batch: one pattern alone must give the same heatmap as inside a batch
                        h1 = np.asarray(predict(m, x[:1]), np.float32)
                        res["batch1_vs_batched_max_diff"] = float(np.abs(h1[0] - h[0]).max())
                        print(f"  batch 1 vs batched, pattern 0: max |diff| {res['batch1_vs_batched_max_diff']:.4f}")
                    results[f"{key}_{cu[0]}"] = res
                except Exception as err:
                    print(f"Core ML {tag} FAILED: {type(err).__name__}: {err}"); results[f"{key}_{cu[0]}"] = dict(error=f"{type(err).__name__}: {err}"[:400])
    # The verdict (C6, 2026-09-07): before this the script could not fail. A runtime that raised, a
    # heatmap beyond --tolerance of the float16 reference, or an in-graph peak output below
    # --min-peak-recall makes the check exit 1; the JSON records every number either way.
    failures = []
    for key, r in results.items():
        if not isinstance(r, dict): continue
        if "error" in r: failures.append(f"{key}: {r['error'][:120]}")
        d = r.get("max_diff_fp16", r.get("max_diff"))
        if d is not None and d > a.tolerance: failures.append(f"{key}: max |diff| {d:.3f} > tolerance {a.tolerance}")
        if "peaks" in r and r["peaks"]["recall"] < a.min_peak_recall: failures.append(f"{key}: in-graph peaks reproduce {r['peaks']['recall']:.3f} of numpy's < {a.min_peak_recall}")
    results["verdict"] = dict(tolerance=a.tolerance, min_peak_recall=a.min_peak_recall, failures=failures, checked=[k for k, v in results.items() if isinstance(v, dict) and "error" not in v and k != "verdict"])
    json.dump(results, open(os.path.join(a.run, "export", "check.json"), "w"), indent=1)
    print("wrote", os.path.join(a.run, "export", "check.json"))
    if not results["verdict"]["checked"]:
        print("CHECK INCONCLUSIVE: no exported runtime was checked (every one skipped or failed)"); sys.exit(1)
    if failures:
        print("CHECK FAIL:\n  " + "\n  ".join(failures)); sys.exit(1)
    print(f"CHECK PASS: {len(results['verdict']['checked'])} runtime(s) within tolerance {a.tolerance}")

if __name__ == "__main__":
    main()
