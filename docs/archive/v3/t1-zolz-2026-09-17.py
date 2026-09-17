#!/usr/bin/env python3
"""T1 (Al2CuLi, P6/mmm) reciprocal lattice at zone axis [0,-4,1].

Independent crystallographic cross-check of PhaseReferenceLibrary's T1 entry.
Enumerates ZOLZ reflections, computes |g| (1/A), 2D projected direction in the
plane perpendicular to the beam, and |F|^2 (extinction), to answer:
  - which |g| families exist near 0.45-0.49 A^-1,
  - whether the reflections the ground truth uses (~0.454, ~0.479) are the
    SAME |g| family (a Friedel pair +-g is same length) or DIFFERENT families,
  - the direction geometry, so we can see what a real 2-spot pattern leaves.
Structure and cell are exactly tools/phase-map-probe/thronsen.swift's T1.
"""
import numpy as np

a = 4.94775
c = 14.14499
gamma = np.deg2rad(120.0)

# Direct lattice vectors, Cartesian (Angstrom).
a1 = np.array([a, 0.0, 0.0])
a2 = np.array([a*np.cos(gamma), a*np.sin(gamma), 0.0])
a3 = np.array([0.0, 0.0, c])
V = np.dot(a1, np.cross(a2, a3))

# Reciprocal lattice (crystallographic, 1/A, no 2*pi).
b1 = np.cross(a2, a3) / V
b2 = np.cross(a3, a1) / V
b3 = np.cross(a1, a2) / V

# T1 basis exactly as thronsen.swift (Z, fractional).
sites = [
    (13, [0.333333, 0.000000, 0.000000]), (13, [0.666667, 0.000000, 0.000000]),
    (13, [0.000000, 0.333333, 0.000000]), (13, [0.000000, 0.666667, 0.000000]),
    (13, [0.666667, 0.666667, 0.000000]), (13, [0.333333, 0.333333, 0.000000]),
    (13, [0.000000, 0.000000, 0.406200]), (13, [0.000000, 0.000000, 0.593800]),
    (29, [0.666667, 0.333333, 0.161200]), (29, [0.333333, 0.666667, 0.838800]),
    (29, [0.333333, 0.666667, 0.161200]), (29, [0.666667, 0.333333, 0.838800]),
    (29, [0.500000, 0.000000, 0.323700]), (29, [0.500000, 0.000000, 0.676300]),
    (29, [0.000000, 0.500000, 0.323700]), (29, [0.000000, 0.500000, 0.676300]),
    (29, [0.500000, 0.500000, 0.323700]), (29, [0.500000, 0.500000, 0.676300]),
    (3,  [0.000000, 0.000000, 0.199300]), (3,  [0.000000, 0.000000, 0.800700]),
    (3,  [0.333333, 0.666667, 0.500000]), (3,  [0.666667, 0.333333, 0.500000]),
]
Zs = np.array([s[0] for s in sites], dtype=float)
frac = np.array([s[1] for s in sites])

# Zone axis as a REAL-SPACE direction [uvw] = [0,-4,1]; also the 0.29-deg-off
# exact-parallel-to-[001]Al direction is essentially this. Beam along r_zone.
uvw = np.array([0.0, -4.0, 1.0])
r_zone = uvw[0]*a1 + uvw[1]*a2 + uvw[2]*a3
beam = r_zone / np.linalg.norm(r_zone)

# Two in-plane basis vectors perpendicular to the beam (for 2D projection).
tmp = np.array([1.0, 0.0, 0.0])
if abs(np.dot(tmp, beam)) > 0.9:
    tmp = np.array([0.0, 1.0, 0.0])
e1 = tmp - np.dot(tmp, beam)*beam; e1 /= np.linalg.norm(e1)
e2 = np.cross(beam, e1)

kmax = 0.70
s_tol = 0.02   # excitation-error window on |g.beam|, generous; exact ZOLZ has l=4k

rows = []
H = 6
for h in range(-H, H+1):
    for k in range(-H, H+1):
        for l in range(-4*H, 4*H+1):
            if h == 0 and k == 0 and l == 0:
                continue
            g = h*b1 + k*b2 + l*b3
            gmag = np.linalg.norm(g)
            if gmag > kmax:
                continue
            s = abs(np.dot(g, beam))          # excitation error component
            if s > s_tol:
                continue
            zolz_exact = (l == 4*k)
            # structure factor (f = Z proxy: exact for extinction detection)
            phase = 2j*np.pi*(frac @ np.array([h, k, l]))
            F = np.sum(Zs * np.exp(phase))
            F2 = (F.real**2 + F.imag**2)
            x = np.dot(g, e1); y = np.dot(g, e2)
            az = np.degrees(np.arctan2(y, x)) % 360.0
            rows.append(dict(h=h, k=k, l=l, gmag=gmag, s=s, exact=zolz_exact,
                             F2=F2, x=x, y=y, az=az))

# Keep reflections with non-negligible structure factor (present).
maxF2 = max(r['F2'] for r in rows) if rows else 1.0
present = [r for r in rows if r['F2'] > 1e-6 * maxF2]

# Group by |g| within 0.001 A^-1 (same as the overnight measurement).
present.sort(key=lambda r: r['gmag'])
groups = []
for r in present:
    if groups and abs(r['gmag'] - groups[-1]['gmag']) < 0.001:
        groups[-1]['members'].append(r)
    else:
        groups.append(dict(gmag=r['gmag'], members=[r]))

print(f"cell a={a} c={c}  V={V:.3f} A^3   |b1|={np.linalg.norm(b1):.5f} |b3|={np.linalg.norm(b3):.5f}")
print(f"ZOLZ condition l=4k ; excitation window |g.beam|<={s_tol}; kMax={kmax}")
print(f"{len(present)} present reflections in {len(groups)} |g| groups\n")
print(f"{'|g|':>8} {'n':>3} {'exact?':>6}   representative (h,k,l)@az, F2/maxF2")
for gp in groups:
    m = gp['members']
    ex = all(x['exact'] for x in m)
    # list distinct (hkl) with azimuths, sorted by azimuth
    ms = sorted(m, key=lambda r: r['az'])
    desc = ", ".join(f"({r['h']},{r['k']},{r['l']})@{r['az']:.0f}[{r['F2']/maxF2:.2f}]" for r in ms[:8])
    star = "  <== 0.45-0.49" if 0.44 <= gp['gmag'] <= 0.50 else ""
    print(f"{gp['gmag']:8.4f} {len(m):3d} {str(ex):>6}   {desc}{star}")

print("\n--- Friedel structure within each |g| group (does the group contain +-g pairs?) ---")
for gp in groups:
    if not (0.44 <= gp['gmag'] <= 0.50):
        continue
    m = gp['members']
    print(f"\n|g|={gp['gmag']:.4f} A^-1, {len(m)} reflections:")
    for r in sorted(m, key=lambda r: r['az']):
        # does -g (i.e. (-h,-k,-l)) also appear in this same group?
        has_partner = any(o['h']==-r['h'] and o['k']==-r['k'] and o['l']==-r['l'] for o in m)
        print(f"   ({r['h']:2d},{r['k']:2d},{r['l']:3d})  |g|={r['gmag']:.4f}  az={r['az']:6.1f} deg  "
              f"(x={r['x']:+.4f}, y={r['y']:+.4f})  Friedel partner in-group: {has_partner}")
