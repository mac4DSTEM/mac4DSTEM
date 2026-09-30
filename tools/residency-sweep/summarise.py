#!/usr/bin/env python3
# Summarise characterise.sh sample TSVs (2026-09-30): a Markdown table per file and an SVG curve.
# A diagnostic, not a gate: it reports what was measured and asserts nothing. Standard library only.
#
#   tools/residency-sweep/summarise.py --out-md summary.md --out-svg curve.svg samples-*.tsv
#
# Processes are not labelled in the TSV; they are rebuilt by walking the lines in order: a new process
# starts at every `preload` line (resident) or at every streamed `image` pass 0. A resident process is
# "cold" when its preload started with cached_before < 0.05, else "warm". Repeats: a streamed process
# opens a repeat, its two resident processes follow it (a cold resident with no open repeat opens one).
# Partial or truncated lines (a run in progress) are skipped; a missing file is skipped with a warning.
import argparse, math, os, sys
from collections import OrderedDict

COLS = ["file", "dtype", "rows", "cube_MB", "ratio", "mode", "phase", "pass", "ms", "ns_per_MB",
        "cached_before", "footprint_MB", "peak_footprint_MB", "swap_MB", "pressure", "checksum"]
COLD_CACHED = 0.05
NOISY = 1.20
CAP = 0.75  # maxBufferLength as a fraction of the working set


def num(s):
    try:
        v = float(s)
        return v if math.isfinite(v) else None
    except ValueError:
        return None


def valid_checksum(s):
    return s in ("held", "REFUSED") or (1 <= len(s) <= 16 and all(c in "0123456789abcdef" for c in s))  # leading zeros are dropped upstream


def read_tsv(path):
    out, skipped = [], 0
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("file\t"):
                continue
            p = line.split("\t")
            if len(p) != len(COLS) or not valid_checksum(p[-1]):
                skipped += 1
                continue
            r = dict(zip(COLS, p))
            for k in ("rows", "pass"):
                r[k] = int(float(r[k]))
            for k in ("cube_MB", "ratio", "ms", "ns_per_MB", "cached_before", "footprint_MB",
                      "peak_footprint_MB", "swap_MB", "pressure"):
                r[k] = num(r[k])
            out.append(r)
    return out, skipped


class Proc:
    def __init__(self, mode):
        self.mode, self.kind, self.repeat = mode, None, None
        self.preload = None
        self.image, self.mean, self.lines = {}, {}, []  # pass -> line

    @property
    def refused(self):
        return self.preload is not None and self.preload["checksum"] == "REFUSED"


def build(lines):
    """(file, rows) -> {meta, procs}, in file order."""
    cells = OrderedDict()
    cur = {}  # (file, rows) -> current open process
    rep = {}  # (file, rows) -> current repeat index
    for r in lines:
        key = (r["file"], r["rows"])
        c = cells.setdefault(key, {"cube_MB": r["cube_MB"], "ratio": r["ratio"], "dtype": r["dtype"], "procs": []})
        p = cur.get(key)
        new = False
        if r["mode"] == "resident" and r["phase"] == "preload":
            new = True
        elif r["mode"] == "streamed" and r["phase"] == "image" and r["pass"] == 0:
            new = True
        elif p is None or p.mode != r["mode"]:
            new = True  # stray line: attach to a fresh process rather than drop it
        if new:
            p = Proc(r["mode"])
            if r["mode"] == "streamed":
                p.kind = "streamed"
                rep[key] = rep.get(key, -1) + 1
            else:
                pc = r["cached_before"] if r["phase"] == "preload" else 1.0
                p.kind = "cold" if (pc is not None and pc < COLD_CACHED) else "warm"
                if key not in rep or (p.kind == "cold" and any(q.kind == "cold" and q.repeat == rep[key] for q in c["procs"])):
                    rep[key] = rep.get(key, -1) + 1
            p.repeat = rep[key]
            c["procs"].append(p)
            cur[key] = p
        p.lines.append(r)
        if r["phase"] == "preload":
            p.preload = r
        elif r["phase"] == "image":
            p.image[r["pass"]] = r
        elif r["phase"] == "meanDP":
            p.mean[r["pass"]] = r
    return cells


def med(v):
    v = sorted(x for x in v if x is not None)
    if not v:
        return None
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])


def rng(v):
    v = [x for x in v if x is not None]
    return (med(v), min(v), max(v)) if v else None


def fmt(t, d=2, scale=1.0):
    if t is None:
        return "–"
    m, lo, hi = t
    return f"{m*scale:.{d}f} ({lo*scale:.{d}f}–{hi*scale:.{d}f})"


def f1(x, d=2):
    return "–" if x is None else f"{x:.{d}f}"


def warm(procs, phase):
    return [getattr(p, phase)[k]["ms"] for p in procs for k in (1, 2) if k in getattr(p, phase)]


def spread(v):
    v = [x for x in v if x]
    return max(v) / min(v) if len(v) >= 2 else None


def analyse(key, c):
    P = [p for p in c["procs"]]
    st = [p for p in P if p.mode == "streamed"]
    res = [p for p in P if p.mode == "resident"]
    ok = [p for p in res if not p.refused]
    cold = [p for p in ok if p.kind == "cold"]
    wrm = [p for p in ok if p.kind == "warm"]
    a = {"key": key, "ratio": c["ratio"], "cube_MB": c["cube_MB"], "n": (len(st), len(cold), len(wrm))}
    a["refused"] = [p for p in res if p.refused]
    ms = lambda ps, ph, k: [getattr(p, ph)[k]["ms"] for p in ps if k in getattr(p, ph)]
    a["st_cold"] = rng(ms(st, "image", 0))
    st_warm_i, st_warm_m = warm(st, "image"), warm(st, "mean")
    rs_warm_i, rs_warm_m = warm(ok, "image"), warm(ok, "mean")
    a["st_warm"], a["st_warm_m"] = rng(st_warm_i), rng(st_warm_m)
    a["rs_warm"], a["rs_warm_m"] = rng(rs_warm_i), rng(rs_warm_m)
    a["pre_cold"] = rng([p.preload["ms"] for p in cold])
    a["pre_warm"] = rng([p.preload["ms"] for p in wrm])
    a["first_cold"] = rng(ms(cold, "image", 0))
    a["first_warm"] = rng(ms(wrm, "image", 0))
    a["nspmb_cold"] = med([p.image[0]["ns_per_MB"] for p in cold if 0 in p.image])
    a["cache"] = tuple(med([p.lines[0]["cached_before"] if k == "streamed" else p.preload["cached_before"]
                            for p in ps if (p.preload or k == "streamed")])
                       for k, ps in (("streamed", st), ("cold", cold), ("warm", wrm)))
    # single-pass ratio, paired per repeat
    sp = []
    for p in cold:
        s = next((q for q in st if q.repeat == p.repeat and 0 in q.image), None)
        if s and 0 in p.image:
            sp.append((p.preload["ms"] + p.image[0]["ms"]) / s.image[0]["ms"])
    a["single"] = rng(sp)
    sp_ = lambda x, y: None if not x or not y else x[0] / y[0]
    a["speed_i"], a["speed_m"] = sp_(a["st_warm"], a["rs_warm"]), sp_(a["st_warm_m"], a["rs_warm_m"])
    # break-even N: P + F + (N-1) R <= S + (N-1) W
    a["breakeven"] = None
    if a["pre_cold"] and a["first_cold"] and a["st_cold"] and a["st_warm"] and a["rs_warm"]:
        P_, F_, S_, W_, R_ = a["pre_cold"][0], a["first_cold"][0], a["st_cold"][0], a["st_warm"][0], a["rs_warm"][0]
        if R_ >= W_:
            a["breakeven"] = "never"
        else:
            x = P_ + F_ - S_
            a["breakeven"] = "1" if x <= 0 else str(1 + math.ceil(x / (W_ - R_)))
    a["peak_res"] = max([l["peak_footprint_MB"] for p in res for l in p.lines if l["peak_footprint_MB"] is not None], default=None)
    a["peak_st"] = max([l["peak_footprint_MB"] for p in st for l in p.lines if l["peak_footprint_MB"] is not None], default=None)
    allines = [l for p in P for l in p.lines]
    a["swap"] = max([l["swap_MB"] for l in allines if l["swap_MB"] is not None], default=None)
    a["press"] = max([l["pressure"] for l in allines if l["pressure"] is not None], default=None)
    a["noise"] = {"streamed": (spread(st_warm_i), spread(st_warm_m)), "resident": (spread(rs_warm_i), spread(rs_warm_m))}
    a["noisy"] = [f"{m} {w}" for m, (i, mm) in a["noise"].items() for w, s in (("image", i), ("meanDP", mm))
                  if s is not None and s > NOISY]
    a["sums"] = {}
    for ph in ("image", "meanDP"):
        vals = sorted({l["checksum"] for p in P for l in p.lines if l["phase"] == ph})
        a["sums"][ph] = vals
    return a


def sumtxt(v):
    return "–" if not v else ("identical" if len(v) == 1 else "differ: " + ", ".join(v))


def table(fname, cells_a):
    """Metrics as rows, rungs as columns."""
    cols = cells_a
    hdr = ["rows"] + [str(a["key"][1]) for a in cols]
    out = [f"### {fname}", "", "| " + " | ".join(hdr) + " |", "|" + "---|" * len(hdr)]
    med_ns = med([a["nspmb_cold"] for a in cols])

    def row(label, fn):
        out.append("| " + label + " | " + " | ".join(fn(a) for a in cols) + " |")

    row("ratio", lambda a: f1(a["ratio"], 4))
    row("cube GB", lambda a: f1(a["cube_MB"] / 1000 if a["cube_MB"] else None, 1))
    row("repeats (streamed / cold / warm)", lambda a: "/".join(map(str, a["n"])))
    row("page cache at start, median (streamed / cold pre / warm pre)",
        lambda a: " / ".join(f1(x, 2) for x in a["cache"]))
    row("streamed cold first image pass, s", lambda a: fmt(a["st_cold"], 2, 1e-3))
    row("streamed warm image pass, s", lambda a: fmt(a["st_warm"], 2, 1e-3))
    row("resident cold preload, s", lambda a: fmt(a["pre_cold"], 2, 1e-3))
    row("resident warm-cache preload, s", lambda a: fmt(a["pre_warm"], 2, 1e-3))
    row("resident first image after cold preload, ms", lambda a: fmt(a["first_cold"], 1))
    row("resident first image after warm preload, ms", lambda a: fmt(a["first_warm"], 1))
    row("resident warm image pass, ms", lambda a: fmt(a["rs_warm"], 1))
    row("meanDP streamed warm pass, s", lambda a: fmt(a["st_warm_m"], 2, 1e-3))
    row("meanDP resident warm pass, ms", lambda a: fmt(a["rs_warm_m"], 1))
    row("single pass: (cold preload + first image) / streamed cold", lambda a: fmt(a["single"], 2))
    row("repeated-pass speedup, image (streamed warm / resident warm)", lambda a: f1(a["speed_i"], 1))
    row("repeated-pass speedup, meanDP", lambda a: f1(a["speed_m"], 1))
    row("break-even pass count N, image", lambda a: a["breakeven"] or "–")
    row("resident cold first image, ns/MB", lambda a: f1(a["nspmb_cold"], 0))
    row("  multiple of median over this file's rungs",
        lambda a: "–" if not a["nspmb_cold"] or not med_ns else f"{a['nspmb_cold']/med_ns:.2f}")
    row("peak footprint, resident max, MB", lambda a: f1(a["peak_res"], 0))
    row("  minus cube, MB", lambda a: f1(a["peak_res"] - a["cube_MB"] if a["peak_res"] is not None else None, 0))
    row("peak footprint, streamed max, MB", lambda a: f1(a["peak_st"], 0))
    row("swap max, MB", lambda a: f1(a["swap"], 0))
    row("pressure max", lambda a: f1(a["press"], 0))
    row("warm max/min, streamed (image / meanDP)",
        lambda a: " / ".join(f1(x, 2) for x in a["noise"]["streamed"]))
    row("warm max/min, resident (image / meanDP)",
        lambda a: " / ".join(f1(x, 2) for x in a["noise"]["resident"]))
    row("noisy (> 1.20)", lambda a: "yes" if a["noisy"] else "no")
    row("checksum, image", lambda a: sumtxt(a["sums"]["image"]))
    row("checksum, meanDP", lambda a: sumtxt(a["sums"]["meanDP"]))
    out.append("")
    return out


def checks(all_a):
    out = ["## Checks", ""]
    for fname, cols in all_a.items():
        for a in cols:
            tag = f"{fname} rows {a['key'][1]} (ratio {f1(a['ratio'], 4)})"
            for ph in ("image", "meanDP"):
                out.append(f"- {tag}: {ph} checksum {sumtxt(a['sums'][ph])}")
            for p in a["refused"]:
                out.append(f"- {tag}: REFUSED preload ({p.kind}), no passes")
            if a["noisy"]:
                out.append(f"- {tag}: noisy warm samples ({', '.join(a['noisy'])})")
        sw = [a["swap"] for a in cols if a["swap"] is not None]
        pr = [a["press"] for a in cols if a["press"] is not None]
        out.append(f"- {fname}: max swap_MB {f1(max(sw) if sw else None, 0)}, max pressure {f1(max(pr) if pr else None, 0)}")
        nref = sum(len(a["refused"]) for a in cols)
        nnoisy = sum(1 for a in cols if a["noisy"])
        out.append(f"- {fname}: {nref} refused preload(s), {nnoisy} noisy cell(s) of {len(cols)}")
    out.append("")
    return out


# ---- SVG ----
SERIES = [  # key, label, colour, dash
    ("st_cold", "streamed, cold first pass", "#b35806", None),
    ("st_warm", "streamed, warm pass", "#f1a340", "6 4"),
    ("pre_cold", "resident, cold preload", "#08519c", None),
    ("rs_warm", "resident, warm pass (image)", "#6baed6", "6 4"),
]


def marker(shape, x, y, c, s=5):
    if shape == "circle":
        return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{s}" fill="{c}" stroke="#fff" stroke-width="1"/>'
    return f'<rect x="{x-s:.1f}" y="{y-s:.1f}" width="{2*s}" height="{2*s}" fill="{c}" stroke="#fff" stroke-width="1"/>'


def svg(all_a):
    W, H, L, R, T, B = 1020, 600, 84, 270, 44, 76
    pw, ph = W - L - R, H - T - B
    secs = []
    for cols in all_a.values():
        for a in cols:
            for key, *_ in SERIES:
                t = a[key]
                if t:
                    secs += [t[1] / 1000, t[2] / 1000]
    lo = 10 ** math.floor(math.log10(min(secs))) if secs else 0.01
    hi = 10 ** math.ceil(math.log10(max(secs))) if secs else 100.0
    if hi <= lo:
        hi = lo * 10
    ly0, ly1 = math.log10(lo), math.log10(hi)
    X = lambda r: L + pw * r / 0.8
    Y = lambda s: T + ph * (1 - (math.log10(s) - ly0) / (ly1 - ly0))
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
         f'font-family="Helvetica, Arial, sans-serif" font-size="12">',
         f'<rect width="{W}" height="{H}" fill="#ffffff"/>',
         f'<text x="{L}" y="24" font-size="14" font-weight="bold" fill="#222">Seconds per pass against cube ratio '
         f'(cube ÷ working set), medians with min–max bars</text>']
    # grid + axes
    d = int(round(ly0))
    while d <= round(ly1):
        for m in range(1, 10):
            v = m * 10 ** d
            if v < lo * 0.999 or v > hi * 1.001:
                continue
            y = Y(v)
            major = m == 1
            o.append(f'<line x1="{L}" y1="{y:.1f}" x2="{L+pw}" y2="{y:.1f}" stroke="{"#c8c8c8" if major else "#ececec"}" stroke-width="1"/>')
            if major:
                lab = f"{v:g}"
                o.append(f'<text x="{L-8}" y="{y+4:.1f}" text-anchor="end" fill="#222">{lab}</text>')
        d += 1
    for i in range(0, 9):
        r = i / 10
        x = X(r)
        o.append(f'<line x1="{x:.1f}" y1="{T}" x2="{x:.1f}" y2="{T+ph}" stroke="#ececec" stroke-width="1"/>')
        o.append(f'<text x="{x:.1f}" y="{T+ph+18}" text-anchor="middle" fill="#222">{r:.1f}</text>')
    o.append(f'<rect x="{L}" y="{T}" width="{pw}" height="{ph}" fill="none" stroke="#555" stroke-width="1"/>')
    o.append(f'<text x="{L+pw/2}" y="{H-24}" text-anchor="middle" font-size="13" fill="#222">ratio (cube bytes as float32 ÷ working set)</text>')
    o.append(f'<text transform="translate(20,{T+ph/2}) rotate(-90)" text-anchor="middle" font-size="13" fill="#222">seconds per pass (log scale)</text>')
    # cap line
    xc = X(CAP)
    o.append(f'<line x1="{xc:.1f}" y1="{T}" x2="{xc:.1f}" y2="{T+ph}" stroke="#333" stroke-width="1.5" stroke-dasharray="7 5"/>')
    o.append(f'<text x="{xc-6:.1f}" y="{T+16}" text-anchor="end" fill="#333">maxBufferLength (0.75)</text>')
    # series
    shapes = ["circle", "square"]
    files = list(all_a.keys())
    for fi, fname in enumerate(files):
        sh = shapes[fi % 2]
        cols = sorted(all_a[fname], key=lambda a: a["ratio"] or 0)
        for key, _, c, dash in SERIES:
            pts = [(a["ratio"], a[key]) for a in cols if a[key] and a["ratio"] is not None]
            if len(pts) > 1:
                dpath = " ".join(f"{X(r):.1f},{Y(t[0]/1000):.1f}" for r, t in pts)
                da = f' stroke-dasharray="{dash}"' if dash else ""
                o.append(f'<polyline points="{dpath}" fill="none" stroke="{c}" stroke-width="2"{da}/>')
            for r, t in pts:
                x = X(r)
                o.append(f'<line x1="{x:.1f}" y1="{Y(t[1]/1000):.1f}" x2="{x:.1f}" y2="{Y(t[2]/1000):.1f}" stroke="{c}" stroke-width="1.5"/>')
                o.append(marker(sh, x, Y(t[0] / 1000), c))
    # legend
    lx, ly = L + pw + 24, T + 6
    o.append(f'<text x="{lx}" y="{ly+8}" font-weight="bold" fill="#222">Series (colour)</text>')
    for i, (_, lab, c, dash) in enumerate(SERIES):
        y = ly + 30 + i * 24
        da = f' stroke-dasharray="{dash}"' if dash else ""
        o.append(f'<line x1="{lx}" y1="{y}" x2="{lx+34}" y2="{y}" stroke="{c}" stroke-width="2.5"{da}/>')
        o.append(f'<text x="{lx+42}" y="{y+4}" fill="#222">{lab}</text>')
    y0 = ly + 30 + len(SERIES) * 24 + 18
    o.append(f'<text x="{lx}" y="{y0}" font-weight="bold" fill="#222">File (marker)</text>')
    for fi, fname in enumerate(files):
        y = y0 + 22 + fi * 24
        o.append(marker(shapes[fi % 2], lx + 17, y, "#555", 6))
        nm = fname if len(fname) <= 26 else fname[:25] + "…"
        o.append(f'<text x="{lx+42}" y="{y+4}" fill="#222">{nm}</text>')
    o.append(f'<text x="{lx}" y="{y0+22+len(files)*24+14}" fill="#555">Bars: min–max over repeats.</text>')
    o.append("</svg>")
    return "\n".join(o) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Summarise residency characterisation TSVs.")
    ap.add_argument("tsv", nargs="+")
    ap.add_argument("--out-md", required=True)
    ap.add_argument("--out-svg", required=True)
    args = ap.parse_args()

    all_a = OrderedDict()  # display name -> [analysis per rung]
    notes = []
    for path in args.tsv:
        if not os.path.exists(path):
            print(f"warning: {path} missing, skipped", file=sys.stderr)
            notes.append(f"{os.path.basename(path)}: missing")
            continue
        lines, skipped = read_tsv(path)
        if skipped:
            notes.append(f"{os.path.basename(path)}: {skipped} partial/malformed line(s) skipped")
        cells = build(lines)
        by_file = OrderedDict()
        for (f, rows), c in cells.items():
            by_file.setdefault(f, []).append(analyse((f, rows), c))
        if not by_file:
            notes.append(f"{os.path.basename(path)}: no samples")
        for f, cols in by_file.items():
            cols.sort(key=lambda a: a["key"][1])
            all_a[f] = cols

    md = ["# Residency characterisation, summary", "",
          "Generated by `tools/residency-sweep/summarise.py`. Times are median (min–max) over repeats. Cold = file evicted "
          "from the page cache at process start. Warm passes are passes 1–2 of every process. Break-even N uses the medians.",
          "The ns/MB multiple is against the median, over this file's rungs, of the per-rung median.", ""]
    for n in notes:
        md.append(f"- Input note, {n}")
    if notes:
        md.append("")
    for fname, cols in all_a.items():
        md += table(fname, cols)
    md += checks(all_a)
    with open(args.out_md, "w") as f:
        f.write("\n".join(md))
    with open(args.out_svg, "w") as f:
        f.write(svg(all_a))


if __name__ == "__main__":
    main()
