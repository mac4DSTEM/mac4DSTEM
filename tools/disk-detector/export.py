#!/usr/bin/env python
"""export.py — the trained net to Core AI (.aimodel, the shipping route) and Core ML (.mlpackage, insurance).

Core AI (§3a Core AI block): torch.export -> decompositions -> coreai-opt float16 cast ->
TorchConverter -> to_coreai -> optimize -> save_asset. Three function variants, one asset each: `detect` takes
[B,3,128,128] and returns the heatmap AND in-graph peak-picking: local maxima (heatmap ==
maxpool3x3) above a threshold, fixed top-K = 70 per pattern, zero-padded — coordinates (row, col)
and scores. `scoremap` returns the heatmap and the peak-masked score map (no top-k) and `heatmap` the heatmap
alone — the fallbacks, because on 2026-09-06 the ANE program load failed for the top-k graph
(check_export.py records which variants the Neural Engine takes). B is a fixed model dimension:
one asset per batch size in --batches.
The probe-as-state attempt (a second function that writes the probe into a model buffer, the
detect function reading it) is exported as a separate asset and its outcome recorded.
Core ML: coremltools from the same net, float16, macOS 15 target, heatmap + peaks if the
converter takes them, heatmap only otherwise (recorded).
Writes <run>/export/export.json: paths, batch sizes, threshold, top-K, SHA-256 of every asset
(the weights hash that goes into provenance), versions, and what failed.

    run.sh export --run <run dir> [--batches 16 32 64] [--threshold 0.3]
"""
from __future__ import annotations
import argparse, hashlib, json, os, platform, sys, time, traceback
from pathlib import Path
import numpy as np, torch, torch.nn as nn, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm, train as tr

S = sm.S

def load_model(run: str) -> nn.Module:
    cfg = json.load(open(os.path.join(run, "config.json")))
    width = cfg["args"].get("width", 16)
    model = tr.UNet(width=width)
    ck_path = os.path.join(run, "best.pt") if os.path.exists(os.path.join(run, "best.pt")) else os.path.join(run, "last.pt")
    ck = torch.load(ck_path, map_location="cpu", weights_only=False)  # our own checkpoint (numpy scalars inside)
    model.load_state_dict(ck["model"]); model.eval()
    return model


class Detector(nn.Module):
    """heatmap + in-graph peak-picking. Plain ops only: max-pool, compare, multiply, top-k, integer div/mod."""
    def __init__(self, unet: nn.Module, threshold: float = 0.3, top_k: int = 70):
        super().__init__(); self.unet, self.threshold, self.top_k = unet, threshold, top_k
    def forward(self, x):
        heat = self.unet(x)                                        # [B,1,S,S]
        mx = F.max_pool2d(heat, 3, stride=1, padding=1)
        peak = (heat >= mx) & (heat > self.threshold)
        score = (heat * peak.to(heat.dtype)).flatten(1)            # [B,S*S], 0 off-peak
        vals, idx = torch.topk(score, self.top_k, dim=1)           # brightest first, zero-padded
        rows = torch.div(idx, S, rounding_mode="floor"); cols = idx - rows * S      # no remainder op: coreai-torch 0.4.2 has no lowering for aten.remainder
        rows, cols = rows.to(torch.float32), cols.to(torch.float32)
        return heat, torch.stack([rows, cols], dim=-1), vals


class ScoreMap(nn.Module):
    """heatmap + the peak-masked score map (max-pool, compare, multiply; no top-k): zero off-peak,
    so the caller's top-K is a scan for non-zeros. The fallback if the ANE refuses top-k."""
    def __init__(self, unet: nn.Module, threshold: float = 0.3):
        super().__init__(); self.unet, self.threshold = unet, threshold
    def forward(self, x):
        heat = self.unet(x); mx = F.max_pool2d(heat, 3, stride=1, padding=1)
        peak = (heat >= mx) & (heat > self.threshold)
        return heat, heat * peak.to(heat.dtype)


class HeatmapOnly(nn.Module):
    def __init__(self, unet: nn.Module):
        super().__init__(); self.unet = unet
    def forward(self, x):
        return self.unet(x)


VARIANTS = {"detect": (Detector, ["heatmap", "coords", "scores"]), "scoremap": (ScoreMap, ["heatmap", "scoremap"]), "heatmap": (HeatmapOnly, ["heatmap"])}


class StatefulDetector(nn.Module):
    """The probe as model state: `probe` is a buffer; detect reads it and takes only two channels."""
    def __init__(self, det: Detector):
        super().__init__(); self.det = det; self.register_buffer("probe", torch.zeros(1, 1, S, S))
    def forward(self, x2):                                          # [B,2,S,S]: pattern, correlation
        self.probe.mul_(1.0)                                        # a mutation so the exporter keeps it as state
        x = torch.cat([x2[:, :1], self.probe.expand(x2.shape[0], 1, S, S), x2[:, 1:]], dim=1)
        return self.det(x)


class SetProbe(nn.Module):
    def __init__(self, probe_buffer: torch.Tensor):
        super().__init__(); self.register_buffer("probe", probe_buffer)
    def forward(self, probe):                                       # [1,1,S,S]
        self.probe.copy_(probe); return self.probe.sum()


def sha256_tree(path: str) -> str:
    h = hashlib.sha256(); p = Path(path)
    files = sorted(f for f in p.rglob("*") if f.is_file()) if p.is_dir() else [p]
    for f in files:
        h.update(str(f.relative_to(p) if p.is_dir() else f.name).encode()); h.update(f.read_bytes())
    return h.hexdigest()


def export_coreai(module: nn.Module, outputs: list, entry: str, batch: int, out: Path, log: dict):
    from coreai_torch import TorchConverter, get_decomp_table
    from coreai_opt.casting import cast_fp32_to_fp16
    example = (torch.rand(batch, 3, S, S),)
    ep = torch.export.export(module, args=example).run_decompositions(get_decomp_table())
    ep16 = cast_fp32_to_fp16(ep)
    conv = TorchConverter().add_exported_program(ep16, input_names=["x"], output_names=outputs, entrypoint_name=entry)
    prog = conv.to_coreai(); prog.optimize()
    prog.save_asset(out)
    log["ops"] = _op_summary(ep16)
    return out


def _op_summary(ep):
    from collections import Counter
    c = Counter(str(n.target).split(".")[-1] if hasattr(n.target, "__module__") else str(n.target) for n in ep.graph.nodes if n.op == "call_function")
    return dict(c.most_common(40))


def export_coreai_stateful(det: Detector, batch: int, out: Path):
    from coreai_torch import TorchConverter, get_decomp_table
    from coreai_opt.casting import cast_fp32_to_fp16
    sd = StatefulDetector(det); sp = SetProbe(sd.probe)
    ep_det = torch.export.export(sd, args=(torch.rand(batch, 2, S, S),)).run_decompositions(get_decomp_table())
    ep_set = torch.export.export(sp, args=(torch.rand(1, 1, S, S),)).run_decompositions(get_decomp_table())
    conv = TorchConverter()
    conv.add_exported_program(cast_fp32_to_fp16(ep_set), input_names=["probe"], output_names=["checksum"], state_names=["probe"], entrypoint_name="set_probe")
    conv.add_exported_program(cast_fp32_to_fp16(ep_det), input_names=["x2"], output_names=["heatmap", "coords", "scores"], state_names=["probe"], entrypoint_name="detect")
    prog = conv.to_coreai(); prog.optimize(); prog.save_asset(out)
    return out


def export_coreml(det: Detector, batch: int, out: Path, log: dict):
    import coremltools as ct
    example = torch.rand(batch, 3, S, S)
    try:
        traced = torch.jit.trace(det, example)
        m = ct.convert(traced, inputs=[ct.TensorType(name="x", shape=example.shape, dtype=np.float32)],
                       outputs=[ct.TensorType(name="heatmap"), ct.TensorType(name="coords"), ct.TensorType(name="scores")],
                       minimum_deployment_target=ct.target.macOS15, compute_precision=ct.precision.FLOAT16, convert_to="mlprogram")
        log["coreml_outputs"] = "heatmap+coords+scores"
    except Exception as e:
        log["coreml_peaks_error"] = f"{type(e).__name__}: {e}"[:400]
        traced = torch.jit.trace(det.unet, example)
        m = ct.convert(traced, inputs=[ct.TensorType(name="x", shape=example.shape, dtype=np.float32)], outputs=[ct.TensorType(name="heatmap")],
                       minimum_deployment_target=ct.target.macOS15, compute_precision=ct.precision.FLOAT16, convert_to="mlprogram")
        log["coreml_outputs"] = "heatmap only (the peak ops did not convert)"
    m.save(str(out)); return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--run", required=True)
    ap.add_argument("--batches", type=int, nargs="+", default=[16, 32, 64]); ap.add_argument("--primary", type=int, default=32)
    ap.add_argument("--threshold", type=float, default=0.3); ap.add_argument("--top-k", type=int, default=70)
    ap.add_argument("--skip-coreml", action="store_true"); ap.add_argument("--skip-stateful", action="store_true")
    ap.add_argument("--variants", nargs="+", default=["detect", "scoremap", "heatmap"], choices=list(VARIANTS))
    a = ap.parse_args()
    out = Path(a.run) / "export"; out.mkdir(exist_ok=True)
    model = load_model(a.run); det = Detector(model, a.threshold, a.top_k).eval()
    import coreai_torch, coremltools
    meta = dict(run=a.run, batch=a.primary, threshold=a.threshold, top_k=a.top_k, size=S, params=sum(p.numel() for p in model.parameters()),
                date=time.strftime("%Y-%m-%d %H:%M"), macos=platform.mac_ver()[0], torch=torch.__version__, coreai_torch=coreai_torch.__version__,
                coremltools=coremltools.__version__, coreai=None, coreai_batches={}, sha256={}, failures={})
    try:
        import coreai_opt; meta["coreai_opt"] = coreai_opt.__version__
    except Exception: pass
    meta["coreai_assets"] = {}
    for b in a.batches:
        for variant in a.variants:
            cls, outputs = VARIANTS[variant]
            module = (cls(model, a.threshold, a.top_k) if variant == "detect" else cls(model, a.threshold) if variant == "scoremap" else cls(model)).eval()
            p = out / f"disk-detector-{variant}-b{b}.aimodel"; t0 = time.time(); log = {}
            try:
                export_coreai(module, outputs, variant, b, p, log); dt = time.time() - t0
                meta["coreai_assets"][f"{variant}-b{b}"] = str(p); meta["sha256"][p.name] = sha256_tree(str(p))
                if variant == "detect": meta["ops"] = log.get("ops")
                print(f"Core AI {variant} B={b}: {p} ({dt:.1f} s) sha256 {meta['sha256'][p.name][:16]}")
                if b == a.primary and variant == "detect": meta["coreai"] = str(p)
            except Exception as e:
                meta["failures"][f"coreai_{variant}_b{b}"] = f"{type(e).__name__}: {e}"[:600]; print(f"Core AI {variant} B={b} FAILED: {type(e).__name__}: {e}"); traceback.print_exc()
    if not a.skip_stateful:
        p = out / f"disk-detector-stateful-b{a.primary}.aimodel"
        try:
            export_coreai_stateful(det, a.primary, p); meta["coreai_stateful"] = str(p); meta["sha256"][p.name] = sha256_tree(str(p)); print(f"Core AI stateful: {p}")
        except Exception as e:
            meta["failures"]["coreai_stateful"] = f"{type(e).__name__}: {e}"[:600]; print(f"Core AI stateful FAILED: {type(e).__name__}: {e}"); traceback.print_exc()
    if not a.skip_coreml:
        p = out / f"disk-detector-b{a.primary}.mlpackage"; log = {}
        try:
            export_coreml(det, a.primary, p, log); meta["coreml"] = str(p); meta["coreml_outputs"] = log.get("coreml_outputs"); meta["sha256"][p.name] = sha256_tree(str(p))
            if "coreml_peaks_error" in log: meta["failures"]["coreml_peaks"] = log["coreml_peaks_error"]
            print(f"Core ML: {p} ({meta['coreml_outputs']})")
        except Exception as e:
            meta["failures"]["coreml"] = f"{type(e).__name__}: {e}"[:600]; print(f"Core ML FAILED: {type(e).__name__}: {e}"); traceback.print_exc()
    json.dump(meta, open(out / "export.json", "w"), indent=1); print("wrote", out / "export.json")


if __name__ == "__main__":
    main()
