#!/usr/bin/env python3
"""tools/demo-dataset/make_demo.py — builds the synthetic two-phase AlMgSi
4D-STEM demo cube described in demo-dataset-brief.md, from the reflection
geometry `export_reflections.swift` computed against the app's own Crystal /
ScatteringFactors port.

Forward model, per scan position: a soft-edged flat-top disk (probe shape) is
stamped at the origin (the direct beam, amplitude = 6x a unit Bragg disk) and
at every visible reflection's detector position (amplitude = that reflection's
relative intensity x the unit Bragg amplitude), plus a flat isotropic
background; the whole float pattern is then the Poisson mean for that pixel.
Everything the pattern for one scan position needs is a function of which of
12 fixed RECIPES the position belongs to (which grain / stripe / precipitate /
boundary / vacuum) — no two positions in the same recipe differ except by
their independent Poisson draw — so each recipe's expected pattern is built
once and reused, not recomputed 10 000 times.

Usage: make_demo.py --reflections <reflections.json> --out-dir <dir>
"""
import argparse
import json
import math
import sys

import numpy as np
import h5py
from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Geometry constants (demo-dataset-brief.md)
# ---------------------------------------------------------------------------
SCAN = 100                  # R_y = R_x
DET = 128                   # Q_y = Q_x
R_PIXEL_NM = 0.5
Q_PIXEL_INV_A = 0.012
ORIGIN = 63.5                # both axes
PROBE_RADIUS_PX = 3.0
PROBE_EDGE_PX = 1.0

# Dose: strongest Bragg disk near 8000 counts, direct beam (= same disk x6)
# near 50000. S is the peak amplitude of a relative-intensity-1.0 Bragg disk.
DIRECT_BEAM_MULTIPLIER = 6
S = 8200.0
DIRECT_BEAM_PEAK = S * DIRECT_BEAM_MULTIPLIER   # 49200, "near 50000"

BACKGROUND_FRACTION = 0.01                       # of the direct beam
BACKGROUND_BASE = BACKGROUND_FRACTION * DIRECT_BEAM_PEAK          # 492.0
PRECIPITATE_BACKGROUND_EXTRA = 0.30              # +30% extra, precipitates only
BACKGROUND_PRECIPITATE = BACKGROUND_BASE * (1 + PRECIPITATE_BACKGROUND_EXTRA)  # 639.6

PRECIPITATE_INTENSITY_SCALE = 0.35               # of Al's intensity scale

GRAINS = {
    "A": {"zone_key": "Al_001", "zone_axis": [0, 0, 1], "in_plane_deg": 12.0,
          "columns": [0, 54]},
    "B": {"zone_key": "Al_011", "zone_axis": [0, 1, 1], "in_plane_deg": 40.0,
          "columns": [55, 99], "rows": [0, 49]},
    "C": {"zone_key": "Al_111", "zone_axis": [1, 1, 1], "in_plane_deg": 70.0,
          "columns": [55, 99], "rows": [50, 99]},
}
VACUUM_ROWS = [90, 99]
VACUUM_COLS = [0, 9]
STRIPE_COLS = [20, 27]
STRIPE_SCALE = 1.0 / 1.015   # every Al q scaled by this (lattice +1.5%)

# Precipitates: (name, kind, rows[r0,r1], cols[c0,c1], zone_key, extra_deg)
# kind: "endon" -> beta" [010], "needle" -> beta" [001]. extra_deg is ON TOP
# of grain A's own +12 deg rotation, drawn from {0, 90}. All clear of the
# stripe (cols 20-27) and the vacuum corner (rows 90-99, cols 0-9); see
# truth.json's "precipitates" list for the authoritative machine-readable copy.
PRECIPITATES = [
    ("E1", "endon",  [8, 11],  [5, 8],   "betaDoublePrime_010", 0),
    ("E2", "endon",  [20, 23], [10, 13], "betaDoublePrime_010", 90),
    ("E3", "endon",  [35, 38], [40, 43], "betaDoublePrime_010", 0),
    ("E4", "endon",  [50, 53], [34, 37], "betaDoublePrime_010", 90),
    ("E5", "endon",  [65, 68], [45, 48], "betaDoublePrime_010", 0),
    ("E6", "endon",  [78, 81], [12, 15], "betaDoublePrime_010", 90),
    ("H1", "needle", [14, 15], [34, 51], "betaDoublePrime_001", 0),   # along scan rows (horizontal)
    ("H2", "needle", [58, 59], [32, 49], "betaDoublePrime_001", 90),  # along scan rows (horizontal)
    ("V1", "needle", [42, 59], [8, 9],   "betaDoublePrime_001", 0),   # along scan columns (vertical)
]
PRECIPITATE_CODE = {"endon": 1, "needle": 2}

RECIPE_CODE = {"A": 0, "B": 1, "C": 2, "vacuum": 3, "mixAB": 4, "mixAC": 5, "mixBC": 6,
               "A_strain": 0, }  # strain keeps the grain-A label in the truth map


# Optional planted detector ellipse (2026-09-24, lattice-calibration
# feasibility): an area-preserving map applied where reciprocal positions
# become pixels, so the true Q is unchanged. None (the default) takes the
# original arithmetic untouched, and the shipped cube is reproduced exactly.
DISTORT = None


def to_pixels(qxr, qyr):
    if DISTORT is None:
        return ORIGIN + qxr / Q_PIXEL_INV_A, ORIGIN + qyr / Q_PIXEL_INV_A
    dx, dy = qxr / Q_PIXEL_INV_A, qyr / Q_PIXEL_INV_A
    (a, b), (c, d) = DISTORT
    return ORIGIN + a * dx + b * dy, ORIGIN + c * dx + d * dy


def rotate(qx, qy, deg):
    theta = math.radians(deg)
    c, s = math.cos(theta), math.sin(theta)
    return c * qx - s * qy, s * qx + c * qy


def stamp_disk(pattern, cx, cy, amplitude, radius=PROBE_RADIUS_PX, edge=PROBE_EDGE_PX):
    """Add a soft-edged flat-top disk to `pattern` (float64 [DET,DET]),
    x = column (fast), y = row — the app's own BraggPeak convention
    (DiskDetection.swift header) and H5Reader's last two axes (Qy, Qx)."""
    half = radius + 0.5 * edge + 1.0
    x0, x1 = int(math.floor(cx - half)), int(math.ceil(cx + half))
    y0, y1 = int(math.floor(cy - half)), int(math.ceil(cy + half))
    x0c, x1c = max(x0, 0), min(x1, DET)
    y0c, y1c = max(y0, 0), min(y1, DET)
    if x0c >= x1c or y0c >= y1c:
        return
    xs = np.arange(x0c, x1c)
    ys = np.arange(y0c, y1c)
    xx, yy = np.meshgrid(xs, ys)
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    inner, outer = radius - 0.5 * edge, radius + 0.5 * edge
    val = np.clip((outer - r) / edge, 0.0, 1.0)
    val = np.where(r <= inner, 1.0, val)
    pattern[y0c:y1c, x0c:x1c] += amplitude * val


def render(reflections, zone_key, rotation_deg, strain_scale=1.0,
           precipitate=None, extra_background=False):
    pattern = np.zeros((DET, DET), dtype=np.float64)
    stamp_disk(pattern, ORIGIN, ORIGIN, DIRECT_BEAM_PEAK)
    for ref in reflections[zone_key]:
        qx, qy = ref["qx"] * strain_scale, ref["qy"] * strain_scale
        qxr, qyr = rotate(qx, qy, rotation_deg)
        px, py = to_pixels(qxr, qyr)
        stamp_disk(pattern, px, py, S * ref["intensity"])
    pattern += BACKGROUND_PRECIPITATE if extra_background else BACKGROUND_BASE
    if precipitate is not None:
        pkey, prot_deg = precipitate
        for ref in reflections[pkey]:
            qxr, qyr = rotate(ref["qx"], ref["qy"], prot_deg)
            px, py = to_pixels(qxr, qyr)
            stamp_disk(pattern, px, py, PRECIPITATE_INTENSITY_SCALE * S * ref["intensity"])
    return pattern


def render_vacuum():
    pattern = np.zeros((DET, DET), dtype=np.float64)
    stamp_disk(pattern, ORIGIN, ORIGIN, DIRECT_BEAM_PEAK)
    return pattern


def build_grid():
    """Returns (recipe_grid[SCAN,SCAN] str, precip_map[SCAN,SCAN] int,
    stripe_mask[SCAN,SCAN] bool, grain_label_map[SCAN,SCAN] int)."""
    recipe = np.empty((SCAN, SCAN), dtype=object)
    precip_map = np.zeros((SCAN, SCAN), dtype=np.int32)
    stripe_mask = np.zeros((SCAN, SCAN), dtype=bool)
    grain_label = np.zeros((SCAN, SCAN), dtype=np.int32)  # 0 A, 1 B, 2 C, 3 vacuum

    precip_lookup = {}
    for name, kind, rows, cols, zkey, extra in PRECIPITATES:
        for r in range(rows[0], rows[1] + 1):
            for c in range(cols[0], cols[1] + 1):
                precip_lookup[(r, c)] = (kind, zkey, extra)

    for row in range(SCAN):
        for col in range(SCAN):
            is_vacuum = VACUUM_ROWS[0] <= row <= VACUUM_ROWS[1] and VACUUM_COLS[0] <= col <= VACUUM_COLS[1]
            if is_vacuum:
                recipe[row, col] = "vacuum"
                grain_label[row, col] = 3
                continue
            grain = "A" if col <= 54 else ("B" if row <= 49 else "C")
            grain_label[row, col] = {"A": 0, "B": 1, "C": 2}[grain]

            if col == 54:
                recipe[row, col] = "mixAB" if row <= 49 else "mixAC"
                continue
            if col >= 55 and row == 49:
                recipe[row, col] = "mixBC"
                continue
            if grain != "A":
                recipe[row, col] = grain
                continue
            if STRIPE_COLS[0] <= col <= STRIPE_COLS[1]:
                stripe_mask[row, col] = True
                recipe[row, col] = "A_strain"
                continue
            hit = precip_lookup.get((row, col))
            if hit is not None:
                kind, zkey, extra = hit
                precip_map[row, col] = PRECIPITATE_CODE[kind]
                recipe[row, col] = f"precip_{kind}_{extra}"
                continue
            recipe[row, col] = "A"
    return recipe, precip_map, stripe_mask, grain_label


def build_bases(reflections):
    bases = {}
    bases["A"] = render(reflections, "Al_001", GRAINS["A"]["in_plane_deg"])
    bases["B"] = render(reflections, "Al_011", GRAINS["B"]["in_plane_deg"])
    bases["C"] = render(reflections, "Al_111", GRAINS["C"]["in_plane_deg"])
    bases["A_strain"] = render(reflections, "Al_001", GRAINS["A"]["in_plane_deg"],
                                strain_scale=STRIPE_SCALE)
    for extra in (0, 90):
        bases[f"precip_endon_{extra}"] = render(
            reflections, "Al_001", GRAINS["A"]["in_plane_deg"],
            precipitate=("betaDoublePrime_010", GRAINS["A"]["in_plane_deg"] + extra),
            extra_background=True)
        bases[f"precip_needle_{extra}"] = render(
            reflections, "Al_001", GRAINS["A"]["in_plane_deg"],
            precipitate=("betaDoublePrime_001", GRAINS["A"]["in_plane_deg"] + extra),
            extra_background=True)
    bases["mixAB"] = 0.5 * (bases["A"] + bases["B"])
    bases["mixAC"] = 0.5 * (bases["A"] + bases["C"])
    bases["mixBC"] = 0.5 * (bases["B"] + bases["C"])
    bases["vacuum"] = render_vacuum()
    return bases


def write_truth(out_dir, grain_label, precip_map, stripe_mask, seed):
    truth = {
        "scan": {"width": SCAN, "height": SCAN, "r_pixel_nm": R_PIXEL_NM},
        "detector": {"width": DET, "height": DET, "q_pixel_inv_angstrom": Q_PIXEL_INV_A,
                     "origin": [ORIGIN, ORIGIN]},
        "probe": {"radius_px": PROBE_RADIUS_PX, "edge_px": PROBE_EDGE_PX},
        "dose": {"direct_beam_multiplier": DIRECT_BEAM_MULTIPLIER,
                 "unit_bragg_amplitude": S, "direct_beam_peak_counts": DIRECT_BEAM_PEAK,
                 "background_fraction": BACKGROUND_FRACTION,
                 "background_base_counts": BACKGROUND_BASE,
                 "precipitate_background_extra_fraction": PRECIPITATE_BACKGROUND_EXTRA,
                 "background_precipitate_counts": BACKGROUND_PRECIPITATE,
                 "precipitate_intensity_scale": PRECIPITATE_INTENSITY_SCALE,
                 "poisson_seed": seed},
        "grains": GRAINS,
        "vacuum": {"rows": VACUUM_ROWS, "columns": VACUUM_COLS},
        "stripe": {"columns": STRIPE_COLS, "q_scale": STRIPE_SCALE,
                   "note": "every Al q scaled by 1/1.015 (lattice +1.5%)"},
        "precipitates": [
            {"name": n, "kind": k, "rows": r, "columns": c, "zone_axis_key": z,
             "extra_in_plane_deg": e, "matrix_in_plane_deg": GRAINS["A"]["in_plane_deg"],
             "code": PRECIPITATE_CODE[k]}
            for n, k, r, c, z, e in PRECIPITATES
        ],
        "precipitate_codes": {"0": "none", "1": "end-on [010]", "2": "needle [001]"},
        "grain_label_codes": {"0": "A", "1": "B", "2": "C", "3": "vacuum"},
        "reflections_source": "reflections.json",
        "grain_label_map": grain_label.tolist(),
        "precipitate_map": precip_map.tolist(),
        "stripe_mask": stripe_mask.tolist(),
    }
    with open(f"{out_dir}/truth.json", "w") as f:
        json.dump(truth, f, indent=1)
    return truth


def write_truth_png(out_dir, grain_label, precip_map, stripe_mask):
    scale = 4
    img = Image.new("RGB", (SCAN * scale, SCAN * scale), "white")
    draw = ImageDraw.Draw(img)
    grain_colors = {0: (200, 200, 255), 1: (200, 255, 200), 2: (255, 220, 180), 3: (40, 40, 40)}
    for row in range(SCAN):
        for col in range(SCAN):
            color = grain_colors[int(grain_label[row, col])]
            draw.rectangle([col * scale, row * scale, col * scale + scale - 1, row * scale + scale - 1],
                            fill=color)
    for row in range(SCAN):
        for col in range(SCAN):
            if stripe_mask[row, col]:
                draw.rectangle([col * scale, row * scale, col * scale + scale - 1, row * scale + scale - 1],
                                outline=(120, 0, 0))
    precip_colors = {1: (200, 0, 0), 2: (0, 0, 220)}
    for row in range(SCAN):
        for col in range(SCAN):
            code = int(precip_map[row, col])
            if code:
                cx, cy = col * scale + scale // 2, row * scale + scale // 2
                draw.ellipse([cx - scale, cy - scale, cx + scale, cy + scale], fill=precip_colors[code])
    img.save(f"{out_dir}/truth.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reflections", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--distort", default=None,
                    help="RATIO,ANGLE_DEG: plant an area-preserving detector ellipse "
                         "(axis ratio, major axis angle from +x toward +y). Off by default.")
    args = ap.parse_args()
    if args.distort:
        global DISTORT
        ratio, angle = (float(v) for v in args.distort.split(","))
        c, s_ = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        k1, k2 = math.sqrt(ratio), 1 / math.sqrt(ratio)
        # R(angle) · diag(k1, k2) · R(-angle)
        DISTORT = ((k1 * c * c + k2 * s_ * s_, (k1 - k2) * c * s_),
                   ((k1 - k2) * c * s_, k1 * s_ * s_ + k2 * c * c))
        print(f"planted ellipse: ratio {ratio}, major axis {angle}°", file=sys.stderr)

    with open(args.reflections) as f:
        reflections = json.load(f)

    print("building recipe grid...", file=sys.stderr)
    recipe_grid, precip_map, stripe_mask, grain_label = build_grid()

    print("rendering the 12 base patterns...", file=sys.stderr)
    bases = build_bases(reflections)
    for name, arr in bases.items():
        print(f"  {name}: peak {arr.max():.1f} counts (pre-noise)", file=sys.stderr)

    recipe_names = sorted(bases.keys())
    recipe_index = {name: i for i, name in enumerate(recipe_names)}
    base_stack = np.stack([bases[name] for name in recipe_names])  # [R, DET, DET]
    recipe_id_grid = np.vectorize(recipe_index.get)(recipe_grid).astype(np.int32)

    rng = np.random.default_rng(args.seed)

    out_path = f"{args.out_dir}/AlMgSi_demo.h5"
    print(f"writing {out_path} ...", file=sys.stderr)
    with h5py.File(out_path, "w") as f:
        group = f.create_group("4DSTEM_experiment/data/datacubes/datacube_0")
        dataset = group.create_dataset(
            "data", shape=(SCAN, SCAN, DET, DET), dtype=np.uint16,
            chunks=(1, SCAN, DET, DET), compression="gzip", compression_opts=4,
        )
        for row in range(SCAN):
            row_bases = base_stack[recipe_id_grid[row]]           # [SCAN, DET, DET]
            counts = rng.poisson(lam=row_bases).astype(np.int64)
            counts = np.clip(counts, 0, 65535).astype(np.uint16)
            dataset[row, :, :, :] = counts
            if row % 10 == 0:
                print(f"  row {row}/{SCAN}", file=sys.stderr)

        cal = group.create_group("metadatabundle/calibration")
        cal.attrs["Q_pixel_size"] = np.float64(Q_PIXEL_INV_A)
        cal.attrs["Q_pixel_units"] = "A^-1"
        cal.attrs["R_pixel_size"] = np.float64(R_PIXEL_NM)
        cal.attrs["R_pixel_units"] = "nm"
        cal.attrs["QR_flip"] = False

        def dim(n, values, name, units):
            d = group.create_dataset(f"dim{n}", data=np.asarray(values, dtype=np.float64))
            d.attrs["name"] = name
            d.attrs["units"] = units

        dim(0, np.arange(SCAN) * R_PIXEL_NM, "Ry", "nm")
        dim(1, np.arange(SCAN) * R_PIXEL_NM, "Rx", "nm")
        dim(2, (np.arange(DET) - ORIGIN) * Q_PIXEL_INV_A, "Qy", "A^-1")
        dim(3, (np.arange(DET) - ORIGIN) * Q_PIXEL_INV_A, "Qx", "A^-1")

    print("writing truth.json / truth.png ...", file=sys.stderr)
    write_truth(args.out_dir, grain_label, precip_map, stripe_mask, args.seed)
    write_truth_png(args.out_dir, grain_label, precip_map, stripe_mask)

    import os
    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"done: {out_path} ({size_mb:.1f} MiB)", file=sys.stderr)


if __name__ == "__main__":
    main()
