"""Turn a lattice fit (Q, axis ratio, major-axis angle) into what the app takes, and check it.

docs/archive/v4/almgsi-gateD-2026-09-24.md part 7. `diagnostic`. The app has no
field for an ellipse: it reads py4DSTEM's calibration keys a, b, theta from the
file (H5Reader.swift) and applies Calibration.ellipseTransform, whose lines are
ported literally below. Q is then typed as Å⁻¹ per CORRECTED pixel.

Usage:
  app_ellipse.py --q 0.026384 --ratio 1.0853 --angle 69.5 [--a-lattice 4.0495]
                 [--peaks DUMP.json --out CORRECTED.json]
The angle is lattice_fit.py's (x = column, y = row). With --out, refit the
corrected dump with lattice_fit.py --zones 001: the axis ratio must be ~1.000
and Q the printed "Q to type" (at the same --a).
"""
import argparse, json, math
import numpy as np


def transform(a, b, theta):                       # Calibration.ellipseTransform
    e = b / a
    s, c = math.sin(theta - math.pi / 2), math.cos(theta - math.pi / 2)
    return e * s * s + c * c, s * c * (1 - e), s * s + e * c * c


def corrected(t, dx, dy):                         # Calibration.ellipseCorrectedOffset -> (x, y)
    t00, t01, t11 = t
    qx = t00 * dy + t01 * dx
    qy = t01 * dy + t11 * dx
    return qy, qx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--q", type=float, required=True)
    ap.add_argument("--ratio", type=float, required=True)
    ap.add_argument("--angle", type=float, required=True)
    ap.add_argument("--a-lattice", type=float, default=4.0495)
    ap.add_argument("--peaks"); ap.add_argument("--out")
    x = ap.parse_args()
    s1 = math.sqrt(x.ratio) / x.q                 # px per Å⁻¹ along the major axis
    s2 = 1 / (x.q * math.sqrt(x.ratio))           # ... along the minor axis
    g200 = 2 / x.a_lattice
    # py4DSTEM convention: a = major semi-axis, b = minor, theta = a's angle
    # from qx (= this app's ROW axis) toward qy, so 90° minus the x/y angle.
    a, b = g200 * s1, g200 * s2
    theta = math.radians((90 - x.angle) % 180)
    t = transform(a, b, theta)
    phi = math.radians(x.angle)
    R = lambda u: np.array([[math.cos(u), -math.sin(u)], [math.sin(u), math.cos(u)]])
    A = R(phi) @ np.diag([s1, s2]) @ R(-phi)
    F = np.array([corrected(t, 1, 0), corrected(t, 0, 1)]).T
    sv = np.linalg.svd(F @ A, compute_uv=False)
    print(f"a {a:.4f} px   b {b:.4f} px   theta {theta:.6f} rad ({math.degrees(theta):.2f}°)   "
          f"(the {{200}} ring's semi-axes at a = {x.a_lattice} Å)")
    print(f"corrected anisotropy {sv[0] / sv[1] - 1:.2e}")
    print(f"Q to type: {1 / sv.mean():.6f} Å⁻¹/px")
    if x.peaks and x.out:
        d = json.load(open(x.peaks)); ox, oy = d["origin"]
        d["peaks"] = [[[ox + cx, oy + cy, I] for px_, py_, I in pl
                       for cx, cy in [corrected(t, px_ - ox, py_ - oy)]] for pl in d["peaks"]]
        json.dump(d, open(x.out, "w"))
        print(f"wrote {x.out}")


if __name__ == "__main__":
    main()
