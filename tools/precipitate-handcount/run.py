#!/usr/bin/env python3
"""Propose precipitate candidates on a 4D-STEM cube, mark them, and count them.

This exists to make the owner's acceptance count CHEAP, not to replace it. It
proposes and marks; a human adjudicates. An algorithmic count cannot score an
algorithm — and counting with threshold + connected components would BE the
baseline arm of the step-4 comparison, so it could not score that either.

Reproduces docs/archive/v3/precipitate-handcount-2026-09-11.md end to end:

    python3 tools/precipitate-handcount/run.py \
        "References/training_dataset/060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5" \
        /tmp/out

Needs numpy, h5py and Pillow. `diagnostic` in tools/run-tests.sh: it reads a
cube that is not in the repo, so no gate can run it.
"""
import sys, json, numpy as np, h5py
from PIL import Image, ImageDraw

def blur(a, s):
    n = int(6*s) | 1; k = np.exp(-0.5*((np.arange(n)-n//2)/s)**2); k /= k.sum(); p = n//2
    o = np.pad(a, ((p, p), (0, 0)), mode="reflect")
    o = np.apply_along_axis(lambda m: np.convolve(m, k, "valid"), 0, o)
    o = np.pad(o, ((0, 0), (p, p)), mode="reflect")
    return np.apply_along_axis(lambda m: np.convolve(m, k, "valid"), 1, o)

def find_reflections(d, mean, std):
    """Detector pixels hot at MANY scan positions.

    NOT the max pattern. The max over ~10^5 positions is maximally sensitive to
    a single-position event, so peak-finding on it returns detector SPIKES: the
    first attempt at this measured one position of 108 900 above 20 sigma at its
    best `reflection`, while a quiet pixel at the same radius had MORE positions
    above 3 sigma (2.35 % vs 0.58 %).
    """
    R0, R1, Q0, Q1 = d.shape
    thr = mean + 4*std
    cnt = np.zeros((Q0, Q1))
    for r in range(0, R0, 33):
        cnt += (d[r:r+33].astype(np.float64) > thr).sum(axis=(0, 1))
    frac = cnt/(R0*R1)*100
    cy, cx = (Q0-1)/2, (Q1-1)/2
    yy, xx = np.mgrid[0:Q0, 0:Q1].astype(float)
    rr = np.hypot(yy-cy, xx-cx)
    peaks = []
    for y in range(1, Q0-1):
        for x in range(1, Q1-1):
            if 5 <= rr[y, x] <= 14 and frac[y, x] >= frac[y-1:y+2, x-1:x+2].max():
                peaks.append((frac[y, x], y, x, rr[y, x]))
    peaks.sort(reverse=True)
    return peaks, (cy, cx)

def friedel_pairs(peaks, centre, tol=1.6):
    """Group reflections into Friedel pairs through the beam centre.

    Three pairs is what beta'' in Al-Mg-Si gives: three needle variants along
    the three <100>Al directions.
    """
    cy, cx = centre; used, pairs = set(), []
    for i, (f, y, x, r) in enumerate(peaks):
        if i in used: continue
        my, mx = 2*cy - y, 2*cx - x
        best, bj = tol, None
        for j, (f2, y2, x2, r2) in enumerate(peaks):
            if j == i or j in used: continue
            dd = np.hypot(y2-my, x2-mx)
            if dd < best: best, bj = dd, j
        if bj is not None:
            used |= {i, bj}
            pairs.append(((y, x), (peaks[bj][1], peaks[bj][2])))
    return pairs

def dark_field(d, pts, rad=1.8):
    R0, R1, Q0, Q1 = d.shape
    yy, xx = np.mgrid[0:Q0, 0:Q1].astype(float)
    m = np.zeros((Q0, Q1), bool)
    for (py, px) in pts:
        m |= np.hypot(yy-py, xx-px) <= rad
    out = np.zeros((R0, R1))
    for r in range(0, R0, 33):
        out[r:r+33] = (d[r:r+33].astype(np.float64)*m).sum(axis=(2, 3))/m.sum()
    return out

def zmap(v):
    """Flatten the slowly varying background, then express in robust sigmas.

    Background subtraction in DIFFRACTION space was tried and rejected: the beam
    tail is azimuthally flat to +-8 %, so subtracting a reference aperture is
    clean — and it made the image slightly WORSE (z(p99.9) 4.91 -> 4.21),
    because this flattening already removes the tail and the reference aperture
    only adds its own shot noise.
    """
    flat = blur(v - blur(v, 12.0), 0.8)
    med = np.median(flat)
    return (flat-med)/(np.median(np.abs(flat-med))*1.4826)

def components(mask):
    H, W = mask.shape; lab = np.zeros((H, W), int); out = []
    for sy in range(H):
        for sx in range(W):
            if mask[sy, sx] and lab[sy, sx] == 0:
                st = [(sy, sx)]; lab[sy, sx] = 1; px = []
                while st:
                    y, x = st.pop(); px.append((y, x))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y+dy, x+dx
                            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and lab[ny, nx] == 0:
                                lab[ny, nx] = 1; st.append((ny, nx))
                out.append(px)
    return out

def measure(px):
    a = np.array(px, float); cy, cx = a.mean(axis=0); dd = a - [cy, cx]
    w, v = np.linalg.eigh((dd.T @ dd)/len(a))
    u = dd @ v[:, -1]; t = dd @ v[:, 0]
    ang = np.degrees(np.arctan2(v[-1, -1] if False else v[0, -1], v[1, -1]))
    ang = ang + 180 if ang <= -90 else (ang - 180 if ang > 90 else ang)
    return dict(n=len(a), cy=cy, cx=cx, length=u.max()-u.min()+1,
                width=t.max()-t.min()+1,
                aspect=(u.max()-u.min()+1)/max(t.max()-t.min()+1, 1.0), angle=ang)

CRITERIA = {
    "strict":    dict(sigma=6.0, min_area=10, min_len=8.0, min_aspect=3.0),
    "balanced":  dict(sigma=5.0, min_area=6,  min_len=5.0, min_aspect=2.5),
    "inclusive": dict(sigma=4.0, min_area=4,  min_len=4.0, min_aspect=2.0),
}

def main(cube, outdir):
    import os; os.makedirs(outdir, exist_ok=True)
    f = h5py.File(cube, "r")
    d = f["dm_dataset_root/dm_dataset/data"]
    cal = f["dm_dataset_root/metadatabundle/calibration"]
    r_nm = float(cal["R_pixel_size"][()])*1000
    R0, R1, Q0, Q1 = d.shape
    mean = np.zeros((Q0, Q1)); 
    for r in range(0, R0, 33): mean += d[r:r+33].astype(np.float64).sum(axis=(0, 1))
    mean /= R0*R1
    ss = np.zeros((Q0, Q1))
    for r in range(0, R0, 33): ss += ((d[r:r+33].astype(np.float64)-mean)**2).sum(axis=(0, 1))
    std = np.sqrt(ss/(R0*R1))
    peaks, centre = find_reflections(d, mean, std)
    pairs = friedel_pairs(peaks[:8], centre)
    print(f"{len(pairs)} Friedel pair(s); using pair 1 = {pairs[0]}")
    z = zmap(dark_field(d, list(pairs[0])))
    np.save(f"{outdir}/z_variant1.npy", z)
    base = (np.clip(z/9.0, 0, 1)*255).astype(np.uint8); Z = 5
    results = {}
    strict = [measure(p) for p in components(z > CRITERIA["strict"]["sigma"])]
    strict = [m for m in strict if m["n"] >= 10 and m["length"] >= 8 and m["aspect"] >= 3]
    mu = np.average([m["angle"] for m in strict], weights=[m["length"] for m in strict])
    print(f"variant axis = {mu:+.1f} deg (length-weighted, strict set)")
    for name, c in CRITERIA.items():
        objs = [m for m in (measure(p) for p in components(z > c["sigma"]))
                if m["n"] >= c["min_area"] and m["length"] >= c["min_len"]
                and m["aspect"] >= c["min_aspect"]]
        objs.sort(key=lambda m: -m["length"])
        im = Image.fromarray(base).resize((R1*Z, R0*Z), Image.LANCZOS).convert("RGB")
        dr = ImageDraw.Draw(im); on = 0
        for i, o in enumerate(objs, 1):
            dev = abs(((o["angle"]-mu+90) % 180)-90); ax = dev <= 20; on += ax
            col = (60, 230, 90) if ax else (255, 140, 0)
            a = np.radians(o["angle"]); h = o["length"]/2
            ay, axx = np.sin(a)*h, np.cos(a)*h
            p0 = ((o["cx"]-axx+0.5)*Z, (o["cy"]-ay+0.5)*Z)
            p1 = ((o["cx"]+axx+0.5)*Z, (o["cy"]+ay+0.5)*Z)
            dr.line([p0, p1], fill=col, width=3 if ax else 2)
            for (px_, py_) in (p0, p1):
                dr.ellipse([px_-4, py_-4, px_+4, py_+4], outline=col, width=2)
            dr.text((o["cx"]*Z+8, o["cy"]*Z-15), str(i), fill=col)
        dr.text((14, 12), f"{name.upper()}  on-axis {on}  off-axis {len(objs)-on}", fill=(255, 255, 255))
        im.save(f"{outdir}/COUNT_{name}.png")
        L = np.array([o["length"] for o in objs
                      if abs(((o["angle"]-mu+90) % 180)-90) <= 20])*r_nm
        area_um2 = (R0*r_nm/1000)*(R1*r_nm/1000)
        results[name] = dict(total=len(objs), on_axis=on, off_axis=len(objs)-on,
                             mean_length_nm=float(L.mean()), density_per_um2=on/area_um2)
        print(f"  {name:10s} N={len(objs):3d}  on-axis={on:3d}  "
              f"length {L.mean():5.1f} nm  density {on/area_um2:6.1f}/um^2")
    json.dump(results, open(f"{outdir}/counts.json", "w"), indent=2)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
