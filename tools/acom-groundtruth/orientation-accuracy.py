#!/usr/bin/env python3
"""tools/acom-groundtruth/orientation-accuracy.py — how accurately does the
app's ACOM recover a zone axis it was PLANTED, and does the answer depend on
where the specimen happens to sit relative to the matcher's internal grid?

WHY THIS EXISTS. `main.swift` says the harness is here "so a Python driver can
feed it synthetic diffraction patterns with KNOWN orientations and check what
mac4DSTEM's matcher recovers", and until 2026-09-15 no driver measured the
ERROR — the app has never had a number for how well it orients. Three
hypotheses about a 3-5 deg offset on the demo cube were refuted in two days
(radial binning, the bank's kMax, and the azimuthal rounding), and each time
the missing thing was the same: the distribution, not a single case.

  python3 tools/acom-groundtruth/orientation-accuracy.py build  > input.json
  tools/acom-groundtruth/run.sh input.json                      > output.json
  python3 tools/acom-groundtruth/orientation-accuracy.py score output.json

THE PLANT IS INDEPENDENT OF THE CODE UNDER TEST, which is this repo's own rule
(a harness may not take its frame from what it gates): reflections are the fcc
selection rule applied by hand, the zone is `g . n == 0` by hand, and the 2D
frame is built here by Gram-Schmidt. Only the zone AXIS is scored, never the
in-plane angle, so the frame's arbitrary origin cannot matter.

Diagnostic, not gated: it takes minutes and answers a question about the
method, not an invariant of the code.
"""
import itertools
import json
import math
import sys

A = 4.0495          # Al, the crystal the app ships as Aluminium (FCC)
ASTAR = 1.0 / A
KMAX = 1.2          # the bank the app builds (AppState.swift)
SCALE = 0.008       # A^-1 per detector pixel
ORIGIN = 128.0
# Planted axes. NOTE, and it cost me a wrong claim: the ACOM bank is NOT the
# low-index list — it is `sampleFundamentalZone(count:)`, a farthest-point
# Fibonacci sampling seeded with the three vertices, so only <100>, <110> and
# <111> are in it exactly. For every other axis part of any error is the
# distance to the nearest bank entry and is unavoidable. `score` measures that
# floor from the bank the harness reports and subtracts it.
AXES = [(0, 0, 1), (0, 1, 1), (1, 1, 1), (0, 1, 2), (1, 1, 2),
        (1, 2, 2), (0, 1, 3), (1, 1, 3), (1, 2, 3)]
# One azimuthal bin is 360/128 = 2.8125 deg. The sweep crosses two of them, so
# a result that depends on the grid cannot hide in it.
ROTATIONS = [round(0.35 * i, 3) for i in range(17)]


def reflections(kmax):
    out = []
    n = int(kmax / ASTAR) + 1
    for h, k, l in itertools.product(range(-n, n + 1), repeat=3):
        if h == k == l == 0:
            continue
        odd = (h % 2, k % 2, l % 2)
        if not (odd == (0, 0, 0) or odd == (1, 1, 1)):   # fcc selection rule
            continue
        g = ASTAR * math.sqrt(h * h + k * k + l * l)
        if g <= kmax:
            out.append((h, k, l, g))
    return out


def frame(n):
    """Any orthonormal pair perpendicular to n. Gram-Schmidt off the least
    aligned Cartesian axis, so it is never degenerate."""
    nn = [c / math.sqrt(sum(c * c for c in n)) for c in n]
    seed = min(((abs(nn[i]), i) for i in range(3)))[1]
    e = [0.0, 0.0, 0.0]
    e[seed] = 1.0
    dot = sum(e[i] * nn[i] for i in range(3))
    u = [e[i] - dot * nn[i] for i in range(3)]
    un = math.sqrt(sum(c * c for c in u))
    u = [c / un for c in u]
    v = [nn[1] * u[2] - nn[2] * u[1], nn[2] * u[0] - nn[0] * u[2],
         nn[0] * u[1] - nn[1] * u[0]]
    return u, v


def pattern(axis, rotation_deg, refl):
    u, v = frame(axis)
    t = math.radians(rotation_deg)
    c, s = math.cos(t), math.sin(t)
    spots = [{"x": ORIGIN, "y": ORIGIN, "intensity": 50.0}]
    for h, k, l, g in refl:
        if h * axis[0] + k * axis[1] + l * axis[2] != 0:      # not in the zone
            continue
        gx = ASTAR * (h * u[0] + k * u[1] + l * u[2])
        gy = ASTAR * (h * v[0] + k * v[1] + l * v[2])
        # Structure factor of fcc is 4f for an allowed reflection, so every
        # spot here carries the same weight bar the 1/g^2 falloff of an
        # ordinary atomic form factor, approximated as 1/(1 + (g/0.6)^2).
        inten = 1.0 / (1.0 + (g / 0.6) ** 2)
        spots.append({"x": ORIGIN + (gx * c - gy * s) / SCALE,
                      "y": ORIGIN + (gx * s + gy * c) / SCALE,
                      "intensity": inten})
    return spots


def build():
    refl = reflections(KMAX)
    plants, labels = [], []
    for axis in AXES:
        for rot in ROTATIONS:
            p = pattern(axis, rot, refl)
            if len(p) < 5:          # too few spots to orient; not a fair plant
                continue
            plants.append(p)
            labels.append({"axis": list(axis), "rotation": rot, "spots": len(p) - 1})
    json.dump({
        "cellAAngstrom": A,
        "siteFractional": [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]],
        "siteAtomicNumbers": [13, 13, 13, 13],
        "kMaxInvAngstrom": KMAX, "zoneAxisCount": 200, "symmetry": "cubic",
        "invAngstromPerPixel": SCALE, "originX": ORIGIN, "originY": ORIGIN,
        "intensityPower": 0.25, "radialKernelInvAngstrom": 0.08,
        "distinctOrientationDeg": 10,
        "patterns": plants,
    }, sys.stdout)
    json.dump(labels, open("/tmp/acom-accuracy-labels.json", "w"))


def family_angle(a, b):
    """Angle between two directions after m-3m reduction."""
    fa = sorted(abs(c) for c in a)
    fb = sorted(abs(c) for c in b)
    na = math.sqrt(sum(c * c for c in fa)) or 1
    nb = math.sqrt(sum(c * c for c in fb)) or 1
    dot = sum(x * y for x, y in zip(fa, fb)) / (na * nb)
    return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def score(path):
    out = json.load(open(path))
    labels = json.load(open("/tmp/acom-accuracy-labels.json"))
    bank = out["zoneAxes"]
    floors = {}                      # nearest bank entry to each planted axis
    for label in labels:
        axis = tuple(label["axis"])
        if axis not in floors:
            floors[axis] = min(family_angle(b, list(axis)) for b in bank)
    by_axis = {}
    for label, result in zip(labels, out["results"]):
        z = result["zoneAxis"]
        err = family_angle(z, label["axis"]) if z else float("nan")
        by_axis.setdefault(tuple(label["axis"]), []).append(err)
    print(f"{'planted':>10} {'spots':>6} {'floor':>6}  "
          f"{'error across in-plane rotation (deg)':<44} {'worst':>6} {'excess':>7}")
    excesses = []
    for axis, errs in by_axis.items():
        floor = floors[axis]
        spots = next(l["spots"] for l in labels if tuple(l["axis"]) == axis)
        excess = max(0.0, max(errs) - floor)
        excesses.append((excess, axis))
        shown = " ".join(f"{e:4.1f}" for e in errs[:11])
        print(f"{str(axis):>10} {spots:6d} {floor:6.2f}  {shown:<44} "
              f"{max(errs):6.2f} {excess:7.2f}")
    print("\n  'floor' is the distance to the nearest axis the bank actually holds:")
    print("  no matcher can do better, and an error at the floor is not an error.")
    print("  'excess' is what is left after subtracting it — that is the defect.")
    excesses.sort(reverse=True)
    for excess, axis in excesses[:3]:
        verdict = "AT THE FLOOR" if excess < 0.5 else f"{excess:.1f} deg BEYOND the floor"
        print(f"    {str(axis):>10}  {verdict}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "build":
        build()
    elif len(sys.argv) == 3 and sys.argv[1] == "score":
        score(sys.argv[2])
    else:
        sys.exit(__doc__)
