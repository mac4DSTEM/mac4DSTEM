#!/usr/bin/env python
"""train.py — plain-conv U-Net disk-centre heatmap regression, PyTorch on MPS (§3a step 2).

Data is simulated on the fly (simulate.py) from the measured probes and real backgrounds in
`--ingredients` (an .npz prepared from the owner's cubes; gitignored) plus the drawn bullseye
probe. Inputs (3,128,128): log pattern, probe, flat-kernel correlation. Target (1,128,128):
Gaussian bumps (sigma 1.5 px) at the truth centres. Loss: MSE weighted (1 + w*target) so a
missed bump costs more than a false one (recall over precision). Logs to TensorBoard,
checkpoints best/last under --out. Time-capped (--max-minutes) so a run ends by morning.

    run.sh train --ingredients <npz> --out References/training_runs/disk-detector-<date>/run1 --max-minutes 75
"""
from __future__ import annotations
import argparse, json, math, os, sys, time
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simulate as sm

# ----------------------------------------------------------------------------- the net
class Block(nn.Module):
    def __init__(self, cin, cout):
        super().__init__()
        self.net = nn.Sequential(nn.Conv2d(cin, cout, 3, padding=1), nn.BatchNorm2d(cout), nn.SiLU(),
                                 nn.Conv2d(cout, cout, 3, padding=1), nn.BatchNorm2d(cout), nn.SiLU())
    def forward(self, x): return self.net(x)


class UNet(nn.Module):
    """Four levels, width x (1,2,4,8) channels (width 24 -> 1.1 M parameters): conv/BN/SiLU, max-pool, nearest upsample + concat.
    Nothing outside the Neural Engine's set (no FFT, no dynamic shapes, no custom ops)."""
    def __init__(self, cin=3, width=24):
        super().__init__()
        ch = (width, 2 * width, 4 * width, 8 * width)
        self.e1, self.e2, self.e3, self.e4 = Block(cin, ch[0]), Block(ch[0], ch[1]), Block(ch[1], ch[2]), Block(ch[2], ch[3])
        self.d3, self.d2, self.d1 = Block(ch[3] + ch[2], ch[2]), Block(ch[2] + ch[1], ch[1]), Block(ch[1] + ch[0], ch[0])
        self.head = nn.Conv2d(ch[0], 1, 1)
    def forward(self, x):
        e1 = self.e1(x); e2 = self.e2(F.max_pool2d(e1, 2)); e3 = self.e3(F.max_pool2d(e2, 2)); e4 = self.e4(F.max_pool2d(e3, 2))
        d3 = self.d3(torch.cat([F.interpolate(e4, scale_factor=2.0, mode="nearest"), e3], 1))
        d2 = self.d2(torch.cat([F.interpolate(d3, scale_factor=2.0, mode="nearest"), e2], 1))
        d1 = self.d1(torch.cat([F.interpolate(d2, scale_factor=2.0, mode="nearest"), e1], 1))
        return torch.sigmoid(self.head(d1))


class HeatmapLoss(nn.Module):
    def __init__(self, miss_weight=20.0):
        super().__init__(); self.w = miss_weight
    def forward(self, pred, target):
        return torch.mean((1 + self.w * target) * (pred - target) ** 2)

# ----------------------------------------------------------------------------- data
def load_ingredients(path):
    z = np.load(path)
    probes = [(z["bullseye_probe"].astype(np.float64), tuple(z["bullseye_centre"]), 0.55),
              (z["ws2_probe"].astype(np.float64), tuple(z["ws2_centre"]), 0.30),
              (sm.drawn_bullseye_probe(), (63.6, 64.3), 0.15)]
    return probes, z["backgrounds"].astype(np.float64)


class SimStream(torch.utils.data.IterableDataset):
    def __init__(self, ingredients, cfg: sm.SimConfig, seed: int, real_bg_p=0.7):
        self.ingredients, self.cfg, self.seed, self.real_bg_p = ingredients, cfg, seed, real_bg_p
    def __iter__(self):
        wi = torch.utils.data.get_worker_info()
        rng = np.random.default_rng(self.seed + (wi.id if wi else 0) * 7919)
        probes, bgs = load_ingredients(self.ingredients)
        w = np.array([p[2] for p in probes]); w /= w.sum()
        while True:
            pi = rng.choice(len(probes), p=w)
            probe, centre, _ = probes[pi]
            bg = bgs[rng.integers(len(bgs))] if rng.random() < self.real_bg_p else None
            s = sm.simulate_one(rng, probe, centre, self.cfg, background=bg)
            x = sm.model_inputs(s.pattern, s.probe, s.correlation)
            y = sm.heatmap_target(s.centres, self.cfg.size, self.cfg.heatmap_sigma)
            yield torch.from_numpy(x), torch.from_numpy(y)


def fixed_set(ingredients, cfg, seed, n):
    rng = np.random.default_rng(seed)
    probes, bgs = load_ingredients(ingredients)
    xs, ys, cens = [], [], []
    for i in range(n):
        probe, centre, _ = probes[i % len(probes)]
        bg = bgs[rng.integers(len(bgs))] if rng.random() < 0.7 else None
        s = sm.simulate_one(rng, probe, centre, cfg, background=bg)
        xs.append(sm.model_inputs(s.pattern, s.probe, s.correlation)); ys.append(sm.heatmap_target(s.centres, cfg.size, cfg.heatmap_sigma)); cens.append(s.centres)
    return torch.from_numpy(np.stack(xs)), torch.from_numpy(np.stack(ys)), cens

# ----------------------------------------------------------------------------- peak-picking (numpy, the reference for the in-graph version)
def pick_peaks(heat: np.ndarray, threshold=0.3, top_k=70):
    """(S,S) -> (K,3) [row, col, score]: 3x3 local maxima above threshold, brightest first."""
    from scipy.ndimage import maximum_filter
    mx = maximum_filter(heat, size=3, mode="constant")
    rows, cols = np.nonzero((heat == mx) & (heat > threshold))
    sc = heat[rows, cols]; order = np.argsort(-sc)[:top_k]
    return np.stack([rows[order], cols[order], sc[order]], 1) if len(order) else np.zeros((0, 3))


def recall_precision(peaks, truth, tol=2.0, edge=4):
    truth = np.asarray(truth).reshape(-1, 2)
    keep = (truth.min(1) >= edge) & (truth.max(1) < sm.S - edge); truth = truth[keep]
    if len(truth) == 0: return np.nan, np.nan
    used = np.zeros(len(peaks), bool); hit = 0
    for r, c in truth:
        if len(peaks) == 0: break
        d = np.hypot(peaks[:, 0] - r, peaks[:, 1] - c); d[used] = np.inf; j = int(np.argmin(d))
        if d[j] <= tol: hit += 1; used[j] = True
    return hit / len(truth), (used.sum() / len(peaks) if len(peaks) else np.nan)

# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ingredients", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--steps", type=int, default=20000); ap.add_argument("--max-minutes", type=float, default=75)
    ap.add_argument("--batch", type=int, default=32); ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--workers", type=int, default=6); ap.add_argument("--miss-weight", type=float, default=20.0)
    ap.add_argument("--val-every", type=int, default=500); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--resume"); ap.add_argument("--device", default="mps"); ap.add_argument("--width", type=int, default=24)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    from torch.utils.tensorboard import SummaryWriter
    tb = SummaryWriter(a.out)
    torch.manual_seed(a.seed)
    dev = torch.device(a.device if (a.device != "mps" or torch.backends.mps.is_available()) else "cpu")
    model = UNet(width=a.width).to(dev)
    nparam = sum(p.numel() for p in model.parameters())
    print(f"UNet params {nparam:,} device {dev}", flush=True)
    cfg = sm.SimConfig()
    json.dump(dict(args=vars(a), params=nparam, config=sm.asdict(cfg)), open(os.path.join(a.out, "config.json"), "w"), indent=1)
    loss_fn = HeatmapLoss(a.miss_weight)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    step0 = 0; best = float("inf")
    if a.resume:
        # --steps is absolute; the schedule (warm-up then anneal) covers the steps that remain
        ck = torch.load(a.resume, map_location=dev, weights_only=False); model.load_state_dict(ck["model"]); opt.load_state_dict(ck["opt"]); step0 = ck["step"]; best = ck.get("best", best)
        for g in opt.param_groups: g["lr"] = a.lr
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=a.lr, total_steps=max(a.steps - step0, 1), pct_start=0.05)
    vx, vy, vcen = fixed_set(a.ingredients, cfg, 999, 128)
    z = np.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture", "fixture.npz"))
    ex = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture", "expected.json")))
    fk = sm.flat_kernel(z["probe"].astype(np.float64), tuple(ex["probe_centre"]))
    fx = torch.from_numpy(np.stack([sm.model_inputs(p.astype(np.float64), z["probe"], sm.cross_correlation(p.astype(np.float64), fk)) for p in z["patterns"]]))
    fcen = [np.array(t["centres"]) for t in ex["truth"]]
    loader = torch.utils.data.DataLoader(SimStream(a.ingredients, cfg, a.seed), batch_size=a.batch, num_workers=a.workers,
                                         persistent_workers=a.workers > 0, prefetch_factor=4 if a.workers > 0 else None)
    it = iter(loader); t0 = time.time(); last = t0; model.train()
    for step in range(step0, a.steps):
        x, y = next(it); x, y = x.to(dev), y.to(dev)
        pred = model(x); loss = loss_fn(pred, y)
        opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
        if step < a.steps - 1: sched.step()
        if step % 50 == 0:
            tb.add_scalar("train/loss", loss.item(), step); tb.add_scalar("train/lr", sched.get_last_lr()[0], step)
            now = time.time(); tb.add_scalar("train/samples_per_s", 50 * a.batch / max(now - last, 1e-9), step); last = now
        if step % a.val_every == 0 or step == a.steps - 1:
            model.eval()
            with torch.no_grad():
                vp = torch.cat([model(vx[i:i + 32].to(dev)).cpu() for i in range(0, len(vx), 32)])
                vloss = loss_fn(vp, vy).item()
                fp = model(fx.to(dev)).cpu()
            rp = [recall_precision(pick_peaks(vp[i, 0].numpy()), vcen[i]) for i in range(len(vx))]
            rf = [recall_precision(pick_peaks(fp[i, 0].numpy()), fcen[i]) for i in range(len(fx))]
            vr, vpp = np.nanmean([r for r, _ in rp]), np.nanmean([p for _, p in rp]); fr, fpp = np.nanmean([r for r, _ in rf]), np.nanmean([p for _, p in rf])
            tb.add_scalar("val/loss", vloss, step); tb.add_scalar("val/recall@2px", vr, step); tb.add_scalar("val/precision", vpp, step)
            tb.add_scalar("fixture/recall@2px", fr, step); tb.add_scalar("fixture/precision", fpp, step)
            tb.add_images("val/input_pattern", vx[:4, 0:1], step); tb.add_images("val/pred", vp[:4], step); tb.add_images("val/target", vy[:4], step)
            el = (time.time() - t0) / 60
            print(f"step {step} loss {loss.item():.5f} val {vloss:.5f} recall {vr:.3f} prec {vpp:.3f} | fixture recall {fr:.3f} prec {fpp:.3f} | {el:.1f} min", flush=True)
            ck = dict(model=model.state_dict(), opt=opt.state_dict(), step=step + 1, best=best, val_loss=vloss, val_recall=vr, fixture_recall=fr)
            torch.save(ck, os.path.join(a.out, "last.pt"))
            if vloss < best:
                best = vloss; ck["best"] = best; torch.save(ck, os.path.join(a.out, "best.pt"))
            model.train()
            if el > a.max_minutes:
                print(f"TIME CAP {a.max_minutes} min reached at step {step}; best checkpoint kept (val loss {best:.5f})", flush=True); break
    tb.close(); print("done", flush=True)


if __name__ == "__main__":
    main()
