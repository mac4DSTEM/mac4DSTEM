#!/usr/bin/env python
"""simulate.py — synthetic 4D-STEM diffraction patterns with known disk centres.

Step 1 of docs/v3-plan.md §3a (learned disk detector). Pure numpy + scipy so it
imports in BOTH the pinned py4DSTEM environment (fixture verification) and the
detector's own PyTorch environment (training). Never ships in the app.

Conventions (py4DSTEM's, kept on purpose so the fixture can be checked against
find_Bragg_disks without a transpose): a centre is (row, col) = (qx, qy) in
py4DSTEM terms — axis 0 first. Nothing here is ever called "x".

Ported from the pinned py4DSTEM source (References/py4DSTEM-dev, 0.14.19,
f050d207) and checked against it pixel for pixel by verify_fixture.py:
  probe.py:474   Probe.get_probe_kernel_flat   -> flat_kernel()
  preprocess/utils.py:59 get_shifted_ar        -> fourier_shift()
  process/utils/cross_correlate.py:13/28 get_cross_correlation(_FT) -> cross_correlation()
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field, asdict

import numpy as np
from scipy import ndimage

S = 128            # the detector's fixed input size (design default, §3a)
RENDER_MARGIN = 32 # disks are rendered on a wider canvas so nothing wraps

# ----------------------------------------------------------------------------
# py4DSTEM ports (numpy only). Line-cited above.
# ----------------------------------------------------------------------------

def fourier_coords_2d(nx: int, ny: int):
    # process/utils/utils.py make_Fourier_coords2D(nx, ny, 1): fftfreq grids.
    qx = np.fft.fftfreq(nx, 1.0)
    qy = np.fft.fftfreq(ny, 1.0)
    return np.meshgrid(qx, qy, indexing="ij")


def fourier_shift(ar: np.ndarray, rowshift: float, colshift: float) -> np.ndarray:
    """get_shifted_ar(ar, xshift, yshift) with periodic=True, bilinear=False."""
    nx, ny = ar.shape
    qx, qy = fourier_coords_2d(nx, ny)
    w = np.exp(-(2j * np.pi) * ((colshift * qy) + (rowshift * qx)))
    return np.real(np.fft.ifft2(np.fft.fft2(ar) * w))


def flat_kernel(probe: np.ndarray, origin: tuple[float, float]) -> np.ndarray:
    """Probe.get_probe_kernel_flat(probe, origin): normalise, shift the centre to the corner."""
    probe = probe.astype(np.float64)
    probe = probe / np.sum(probe)
    return fourier_shift(probe, -origin[0], -origin[1])


def cross_correlation(pattern: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """get_cross_correlation(ar, template, corrPower=1, _returnval='real')."""
    template_ft = np.conj(np.fft.fft2(kernel.astype(np.float64)))
    m = np.fft.fft2(pattern.astype(np.float64)) * template_ft
    return np.maximum(np.real(np.fft.ifft2(m)), 0)

# ----------------------------------------------------------------------------
# Probes
# ----------------------------------------------------------------------------

def centre_of_mass(img: np.ndarray) -> tuple[float, float]:
    img = np.asarray(img, dtype=np.float64)
    rr, cc = np.indices(img.shape)
    s = img.sum()
    return float((img * rr).sum() / s), float((img * cc).sum() / s)


def centred_crop(img: np.ndarray, centre: tuple[float, float], size: int = S) -> tuple[np.ndarray, tuple[float, float]]:
    """Crop `size`x`size` around `centre` (row, col), zero-padded; returns the crop and
    the centre's position inside it (fractional part preserved)."""
    r0 = int(round(centre[0])) - size // 2
    c0 = int(round(centre[1])) - size // 2
    out = np.zeros((size, size), dtype=np.float64)
    rs, re = max(r0, 0), min(r0 + size, img.shape[0])
    cs, ce = max(c0, 0), min(c0 + size, img.shape[1])
    out[rs - r0:re - r0, cs - c0:ce - c0] = img[rs:re, cs:ce]
    return out, (centre[0] - r0, centre[1] - c0)


def drawn_bullseye_probe(size: int = S, centre: tuple[float, float] = (63.6, 64.3),
                         radius: float = 9.0, ring_depth: float = 0.55) -> np.ndarray:
    """A fully synthetic ring-shaped ("bullseye") probe: a soft-edged disk whose centre
    is dimmed by a cosine ring, so the fixture exercises the failure class the feature
    targets without any real data. Fractional centre on purpose (a refuter found an
    integer-centre fixture blind to an unwrapped frequency index, 2026-09-05)."""
    rr, cc = np.indices((size, size), dtype=np.float64)
    r = np.hypot(rr - centre[0], cc - centre[1])
    edge = 0.5 * (1 - np.tanh((r - radius) / 0.8))          # soft disk
    ring = 1 - ring_depth * (0.5 + 0.5 * np.cos(2 * np.pi * r / (radius * 0.75)))
    return edge * ring * 1000.0


def prepare_measured_probe(probe: np.ndarray, size: int = S) -> tuple[np.ndarray, tuple[float, float]]:
    """Centre-crop a measured probe (any size) to the model size around its centre of mass."""
    crop, centre = centred_crop(np.asarray(probe, dtype=np.float64), centre_of_mass(probe), size)
    return crop, centre


def rescale_probe(probe: np.ndarray, centre: tuple[float, float], zoom: float) -> tuple[np.ndarray, tuple[float, float]]:
    """Zoom a probe about its centre (disk-size randomisation); the output is the same size."""
    if abs(zoom - 1.0) < 1e-6:
        return probe.copy(), centre
    z = ndimage.zoom(probe, zoom, order=1)
    zc = (centre[0] * zoom, centre[1] * zoom)
    crop, c = centred_crop(z, zc, probe.shape[0])
    return np.maximum(crop, 0), c

# ----------------------------------------------------------------------------
# Lattices and rendering
# ----------------------------------------------------------------------------

@dataclass
class SimConfig:
    size: int = S
    spacing_px: tuple[float, float] = (10.0, 40.0)        # |a|, |b| range at the model size
    angle_deg: tuple[float, float] = (50.0, 130.0)         # angle between a and b
    origin_jitter_px: float = 8.0                          # detector offset of the (000) disk
    zoom: tuple[float, float] = (0.6, 1.4)                 # disk-size randomisation
    ring_mix: tuple[float, float] = (0.0, 1.0)             # 0 = probe as given, 1 = flat disk of the same radius
    tilt: tuple[float, float] = (0.0, 0.35)                # intensity gradient across a disk
    central_gain: tuple[float, float] = (2.0, 20.0)        # (000) over the strongest reflection
    falloff_px: tuple[float, float] = (15.0, 60.0)         # Gaussian |g| falloff of intensities
    spread_lognormal: tuple[float, float] = (0.2, 0.9)     # per-disk intensity spread
    missing_fraction: tuple[float, float] = (0.0, 0.35)    # reflections rendered at ~0 (extinct)
    second_grain_p: float = 0.3
    second_grain_weight: tuple[float, float] = (0.2, 1.0)
    dose_counts: tuple[float, float] = (2e4, 2e6)          # total counts per pattern (Poisson)
    background_level: tuple[float, float] = (0.0, 0.6)     # background over disk sum, before noise
    readout_sigma: tuple[float, float] = (0.0, 3.0)
    gain_sigma: tuple[float, float] = (0.0, 0.05)
    hot_pixels: tuple[int, int] = (0, 6)
    pedestal: tuple[float, float] = (0.0, 20.0)
    heatmap_sigma: float = 1.5


def random_lattice(rng: np.random.Generator, cfg: SimConfig):
    a = rng.uniform(*cfg.spacing_px)
    b = rng.uniform(*cfg.spacing_px)
    ang = math.radians(rng.uniform(*cfg.angle_deg))
    rot = rng.uniform(0, 2 * math.pi)
    va = np.array([math.cos(rot), math.sin(rot)]) * a
    vb = np.array([math.cos(rot + ang), math.sin(rot + ang)]) * b
    return va, vb


def lattice_points(origin, va, vb, size: int, margin: float):
    """All (h,k) whose position lies inside the render canvas (size + margins)."""
    lo, hi = -margin, size + margin
    n = int(math.ceil((size + 2 * margin) / min(np.linalg.norm(va), np.linalg.norm(vb)))) + 2
    pts, hk = [], []
    for h in range(-n, n + 1):
        for k in range(-n, n + 1):
            p = np.asarray(origin) + h * va + k * vb
            if lo <= p[0] < hi and lo <= p[1] < hi:
                pts.append(p); hk.append((h, k))
    return np.array(pts).reshape(-1, 2), hk


def disk_intensities(rng, pts, hk, origin, cfg: SimConfig, falloff, spread, missing):
    g = np.linalg.norm(pts - np.asarray(origin), axis=1)
    base = np.exp(-(g ** 2) / (2 * falloff ** 2))
    base *= rng.lognormal(0.0, spread, size=len(pts))
    extinct = rng.random(len(pts)) < missing
    base[extinct] *= rng.uniform(0.0, 0.02, size=extinct.sum())
    central = [i for i, (h, k) in enumerate(hk) if h == 0 and k == 0]
    if central:
        base[central[0]] = base.max() * rng.uniform(*cfg.central_gain)
    return base


def render_disks(probe_render: np.ndarray, probe_centre, centres, intensities, size: int, margin: int):
    """Sum of shifted copies of `probe_render` at `centres` via one FFT on a wider canvas;
    the centre `size` x `size` is returned (no periodic wrap into the field of view)."""
    R = size + 2 * margin
    canvas = np.zeros((R, R), dtype=np.float64)
    pr = probe_render
    canvas[: pr.shape[0], : pr.shape[1]] = pr
    # move the probe centre to the canvas corner, then place at each centre + margin
    qx, qy = fourier_coords_2d(R, R)
    F = np.fft.fft2(canvas) * np.exp(2j * np.pi * (probe_centre[0] * qx + probe_centre[1] * qy))
    phase = np.zeros((R, R), dtype=np.complex128)
    for (r, c), I in zip(centres, intensities):
        phase += I * np.exp(-2j * np.pi * ((r + margin) * qx + (c + margin) * qy))
    img = np.real(np.fft.ifft2(F * phase))
    return np.maximum(img[margin:margin + size, margin:margin + size], 0)


def synthetic_background(rng, size: int, level_scale: float) -> np.ndarray:
    """A drawn background: a broad halo plus a faint amorphous ring, no real data."""
    rr, cc = np.indices((size, size), dtype=np.float64)
    c = (size / 2 + rng.uniform(-4, 4), size / 2 + rng.uniform(-4, 4))
    r = np.hypot(rr - c[0], cc - c[1])
    halo = np.exp(-r / rng.uniform(15, 50))
    ring_r = rng.uniform(20, 55)
    ring = rng.uniform(0, 0.6) * np.exp(-((r - ring_r) ** 2) / (2 * rng.uniform(3, 8) ** 2))
    bg = halo + ring + rng.uniform(0.0, 0.05)
    return bg * level_scale


def apply_detector(rng, ideal: np.ndarray, cfg: SimConfig, dose: float) -> np.ndarray:
    """Poisson at `dose` total counts, readout noise, gain variation, hot pixels, pedestal."""
    size = ideal.shape[0]
    scale = dose / max(ideal.sum(), 1e-12)
    expected = ideal * scale
    gain = 1 + rng.normal(0, rng.uniform(*cfg.gain_sigma), size=ideal.shape)
    smooth = ndimage.gaussian_filter(rng.normal(0, 1, size=ideal.shape), 12)
    gain *= 1 + 0.05 * smooth / (np.abs(smooth).max() + 1e-12)
    counts = rng.poisson(np.maximum(expected * gain, 0)).astype(np.float64)
    counts += rng.normal(0, rng.uniform(*cfg.readout_sigma), size=ideal.shape)
    counts += rng.uniform(*cfg.pedestal)
    for _ in range(rng.integers(cfg.hot_pixels[0], cfg.hot_pixels[1] + 1)):
        counts[rng.integers(size), rng.integers(size)] = rng.uniform(0.5, 1.0) * max(counts.max(), 1) * 4
    return np.maximum(counts, 0)

# ----------------------------------------------------------------------------
# One sample
# ----------------------------------------------------------------------------

@dataclass
class Sample:
    pattern: np.ndarray                    # (S,S) float64 counts, noisy
    probe: np.ndarray                      # (S,S) the probe the detector is GIVEN (zoomed measured probe)
    probe_centre: tuple[float, float]      # its centre (row, col) inside the array
    correlation: np.ndarray                # (S,S) py4DSTEM flat-kernel cross-correlation of pattern with probe
    centres: np.ndarray                    # (N,2) truth (row, col) inside [0,S)
    intensities: np.ndarray                # (N,) relative disk intensities (max 1 per grain)
    meta: dict = field(default_factory=dict)


def simulate_one(rng: np.random.Generator, probe: np.ndarray, probe_centre, cfg: SimConfig,
                 background: np.ndarray | None = None) -> Sample:
    size = cfg.size
    zoom = rng.uniform(*cfg.zoom)
    given, gc = rescale_probe(probe, probe_centre, zoom)
    # what the disks really look like: the given probe with the ring filled in a bit and a tilt gradient
    rr, cc = np.indices((size, size), dtype=np.float64)
    r = np.hypot(rr - gc[0], cc - gc[1])
    radius = probe_radius(given, gc)
    flat = 0.5 * (1 - np.tanh((r - radius) / 0.8)) * given.max()
    mix = rng.uniform(*cfg.ring_mix)
    tilt = rng.uniform(*cfg.tilt)
    tdir = rng.uniform(0, 2 * math.pi)
    grad = 1 + tilt * (((rr - gc[0]) * math.cos(tdir) + (cc - gc[1]) * math.sin(tdir)) / max(radius, 1))
    render = np.maximum(((1 - mix) * given + mix * flat) * grad, 0)
    render /= render.sum()

    origin = (size / 2 + rng.uniform(-cfg.origin_jitter_px, cfg.origin_jitter_px),
              size / 2 + rng.uniform(-cfg.origin_jitter_px, cfg.origin_jitter_px))
    grains = 1 + int(rng.random() < cfg.second_grain_p)
    all_pts, all_I, all_hk, weights = [], [], [], []
    for gi in range(grains):
        va, vb = random_lattice(rng, cfg)
        pts, hk = lattice_points(origin, va, vb, size, RENDER_MARGIN)
        I = disk_intensities(rng, pts, hk, origin, cfg,
                             rng.uniform(*cfg.falloff_px), rng.uniform(*cfg.spread_lognormal),
                             rng.uniform(*cfg.missing_fraction))
        w = 1.0 if gi == 0 else rng.uniform(*cfg.second_grain_weight)
        if gi == 1:  # the second grain shares the (000) disk: drop its own central disk
            keep = [i for i, (h, k) in enumerate(hk) if not (h == 0 and k == 0)]
            pts, hk, I = pts[keep], [hk[i] for i in keep], I[keep]
        all_pts.append(pts); all_I.append(I * w); all_hk += hk; weights.append(w)
    pts = np.concatenate(all_pts); I = np.concatenate(all_I)
    I = I / I.max()
    disks = render_disks(render, gc, pts, I, size, RENDER_MARGIN)

    level = rng.uniform(*cfg.background_level)
    if background is None:
        bg = synthetic_background(rng, size, 1.0)
    else:
        bg = np.maximum(background, 0).astype(np.float64)
    bg = bg / max(bg.sum(), 1e-12) * disks.sum() * level
    dose = float(np.exp(rng.uniform(math.log(cfg.dose_counts[0]), math.log(cfg.dose_counts[1]))))
    pattern = apply_detector(rng, disks + bg, cfg, dose)

    inside = (pts[:, 0] >= 0) & (pts[:, 0] < size) & (pts[:, 1] >= 0) & (pts[:, 1] < size)
    centres, intens = pts[inside], I[inside]
    kernel = flat_kernel(given, gc)
    corr = cross_correlation(pattern, kernel)
    meta = dict(zoom=zoom, ring_mix=mix, tilt=tilt, origin=[float(origin[0]), float(origin[1])], grains=grains,
                dose=dose, background_level=level, radius_px=float(radius))
    return Sample(pattern, given, gc, corr, centres, intens, meta)


def probe_radius(probe: np.ndarray, centre) -> float:
    """Radius at which the azimuthal mean falls to 20% of its maximum (outer edge; enough for rendering)."""
    rr, cc = np.indices(probe.shape, dtype=np.float64)
    r = np.hypot(rr - centre[0], cc - centre[1]).astype(int)
    prof = np.bincount(r.ravel(), probe.ravel()) / np.maximum(np.bincount(r.ravel()), 1)
    thr = 0.2 * prof.max()
    below = np.nonzero(prof < thr)[0]
    return float(below[0]) if len(below) else float(probe.shape[0] / 4)

# ----------------------------------------------------------------------------
# Model inputs and targets (the one normalisation, shared with step 4)
# ----------------------------------------------------------------------------

def model_inputs(pattern: np.ndarray, probe: np.ndarray, correlation: np.ndarray) -> np.ndarray:
    """(3,S,S) float32: log-scaled normalised pattern, normalised probe, normalised correlation."""
    p = np.asarray(pattern, dtype=np.float64)
    p = np.log1p(np.maximum(p - p.min(), 0))
    p /= max(p.max(), 1e-12)
    q = np.asarray(probe, dtype=np.float64); q = q / max(q.max(), 1e-12)
    c = np.asarray(correlation, dtype=np.float64); c = c / max(c.max(), 1e-12)
    return np.stack([p, q, c]).astype(np.float32)


def heatmap_target(centres: np.ndarray, size: int, sigma: float) -> np.ndarray:
    """(1,S,S) float32: a Gaussian bump of amplitude 1 at every truth centre."""
    out = np.zeros((size, size), dtype=np.float64)
    if len(centres) == 0:
        return out[None].astype(np.float32)
    rr, cc = np.indices((size, size), dtype=np.float64)
    for r, c in centres:
        out = np.maximum(out, np.exp(-((rr - r) ** 2 + (cc - c) ** 2) / (2 * sigma ** 2)))
    return out[None].astype(np.float32)

# ----------------------------------------------------------------------------
# Real ingredients (owner-local, gitignored; absolute paths from the caller)
# ----------------------------------------------------------------------------

def load_bullseye_probe(path: str) -> np.ndarray:
    import h5py
    with h5py.File(path, "r") as f:
        return f["4DSTEM_experiment/data/diffractionslices/probe_template/data"][:, :, 0].astype(np.float64)


def load_ws2_probe(path: str, n: int = 64, seed: int = 0) -> np.ndarray:
    """polycrystal_2D_WS2.h5 carries no probe: the central disk of the mean of `n` random
    patterns, masked at 1.4x the py4DSTEM-style probe radius, stands in for it."""
    import h5py
    rng = np.random.default_rng(seed)
    with h5py.File(path, "r") as f:
        d = f["4DSTEM/datacube/data"]
        idx = sorted({(int(a), int(b)) for a, b in zip(rng.integers(d.shape[0], size=n), rng.integers(d.shape[1], size=n))})
        mean = np.zeros(d.shape[2:], dtype=np.float64)
        for a, b in idx:
            mean += d[a, b].astype(np.float64)
        mean /= len(idx)
    c = np.unravel_index(mean.argmax(), mean.shape)
    rad = probe_radius(mean, c)
    rr, cc = np.indices(mean.shape, dtype=np.float64)
    r = np.hypot(rr - c[0], cc - c[1])
    return mean * (0.5 * (1 - np.tanh((r - 1.4 * rad) / 1.0)))


def radial_background(pattern: np.ndarray, centre) -> np.ndarray:
    """A real background from a real pattern: the azimuthal MEDIAN at every radius (disks are
    a minority of each ring, so the median keeps the halo and diffuse rings and drops the disks)."""
    rr, cc = np.indices(pattern.shape, dtype=np.float64)
    r = np.hypot(rr - centre[0], cc - centre[1]).astype(int)
    prof = np.zeros(r.max() + 1)
    flat_r, flat_p = r.ravel(), pattern.ravel()
    order = np.argsort(flat_r)
    flat_r, flat_p = flat_r[order], flat_p[order]
    bounds = np.searchsorted(flat_r, np.arange(r.max() + 2))
    for i in range(r.max() + 1):
        seg = flat_p[bounds[i]:bounds[i + 1]]
        prof[i] = np.median(seg) if len(seg) else 0
    return prof[r]


def collect_real_backgrounds(bullseye: str, ws2: str, n_each: int = 48, seed: int = 1) -> np.ndarray:
    """(N,S,S) real radial backgrounds at the model size from both cubes."""
    import h5py
    rng = np.random.default_rng(seed)
    out = []
    with h5py.File(bullseye, "r") as f:
        d = f["4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"]
        for _ in range(n_each):
            p = d[rng.integers(d.shape[0]), rng.integers(d.shape[1])].astype(np.float64)
            crop, c = centred_crop(p, (124.76, 124.74), S)
            out.append(radial_background(crop, c))
    with h5py.File(ws2, "r") as f:
        d = f["4DSTEM/datacube/data"]
        for _ in range(n_each):
            p = d[rng.integers(d.shape[0]), rng.integers(d.shape[1])].astype(np.float64)
            c = np.unravel_index(p.argmax(), p.shape)
            out.append(radial_background(p, c))
    return np.stack(out)

# ----------------------------------------------------------------------------
# The fixture: fully synthetic, seeded, small enough to commit
# ----------------------------------------------------------------------------

FIXTURE_SEED = 20260906
FIXTURE_N = 16


def fixture_config() -> SimConfig:
    # Narrower than training so the classical detector at its 2026-09-05 settings is a fair
    # judge: moderate doses, no extinct reflections, single grain, the probe as given.
    # Lattice spacing >= 2 disk radii (no overlapping disks) and a gentle intensity falloff: the
    # overlapping and near-extinct regimes are training material, not a proof of geometry.
    return SimConfig(zoom=(0.9, 1.1), ring_mix=(0.0, 0.3), tilt=(0.0, 0.15), missing_fraction=(0.0, 0.0),
                     second_grain_p=0.0, dose_counts=(3e5, 2e6), background_level=(0.0, 0.3),
                     readout_sigma=(0.0, 1.5), hot_pixels=(0, 3), spacing_px=(23.0, 36.0), angle_deg=(60.0, 120.0),
                     falloff_px=(30.0, 70.0), spread_lognormal=(0.2, 0.5), central_gain=(2.0, 4.0))


def make_fixture(n: int = FIXTURE_N, seed: int = FIXTURE_SEED, break_mode: str | None = None):
    """Returns (patterns uint16 (n,S,S), probe float32 (S,S), probe_centre, truth list).
    break_mode renders a deliberate defect (verify_fixture.py must FAIL on each):
      shifted-truth  every truth centre moved by (+3, 0) px
      swapped-axes   truth stored as (col, row)
      dropped-disk   the three brightest non-central disks are not rendered but stay in the truth
      wrong-probe    the stored probe is rolled by (+4, -3) px (a wrong probe file / wrong origin)
    """
    rng = np.random.default_rng(seed)
    probe = drawn_bullseye_probe()
    centre = (63.6, 64.3)
    cfg = fixture_config()
    patterns, truth = [], []
    for i in range(n):
        s = simulate_one(rng, probe, centre, cfg)
        cen, inten = s.centres.copy(), s.intensities.copy()
        pat = s.pattern
        if break_mode == "dropped-disk":
            # re-render without the three brightest non-central disks, truth unchanged
            order = np.argsort(-inten)
            drop = [j for j in order if inten[j] < 0.999][:3]
            keep = np.ones(len(cen), bool); keep[drop] = False
            r2 = np.random.default_rng(seed + 1000 + i)
            disks = render_disks(s.probe / s.probe.sum(), s.probe_centre, cen[keep], inten[keep], cfg.size, RENDER_MARGIN)
            pat = apply_detector(r2, disks, cfg, s.meta["dose"])
        if break_mode == "shifted-truth":
            cen = cen + np.array([3.0, 0.0])
        if break_mode == "swapped-axes":
            cen = cen[:, ::-1]
        patterns.append(np.clip(np.round(pat), 0, 65535).astype(np.uint16))
        truth.append(dict(index=i, centres=[[float(a), float(b)] for a, b in cen],
                          intensities=[float(v) for v in inten], meta={k: (float(v) if not isinstance(v, list) else v) for k, v in s.meta.items()}))
    probe_out = probe.astype(np.float32)
    if break_mode == "wrong-probe":
        probe_out = np.roll(np.roll(probe_out, 4, axis=0), -3, axis=1)
    return np.stack(patterns), probe_out, centre, truth


def write_fixture(dirpath: str):
    import os, hashlib
    pats, probe, centre, truth = make_fixture()
    np.savez_compressed(os.path.join(dirpath, "fixture.npz"), patterns=pats, probe=probe)
    digest = hashlib.sha256(pats.tobytes()).hexdigest()
    json.dump(dict(seed=FIXTURE_SEED, n=FIXTURE_N, size=S, probe_centre=list(centre),
                   patterns_sha256=digest, config=asdict(fixture_config()), truth=truth),
              open(os.path.join(dirpath, "expected.json"), "w"), indent=1)
    print(f"fixture: {pats.shape} uint16, sha256 {digest[:16]}…, {sum(len(t['centres']) for t in truth)} truth centres")


if __name__ == "__main__":
    import argparse, os
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["fixture", "backgrounds"])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "fixture"))
    ap.add_argument("--bullseye"); ap.add_argument("--ws2")
    a = ap.parse_args()
    if a.command == "fixture":
        write_fixture(a.out)
    else:
        bg = collect_real_backgrounds(a.bullseye, a.ws2)
        np.save(a.out, bg.astype(np.float32)); print("backgrounds", bg.shape, "->", a.out)
