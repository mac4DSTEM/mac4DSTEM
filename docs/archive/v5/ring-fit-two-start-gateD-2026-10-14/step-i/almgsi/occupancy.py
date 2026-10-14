# Pre-fit descriptor only (NOT a fit): the angular-coverage statistic EllipseCalibration.fit1D applies before any optimisation
# (EllipseCalibration.swift:140-232): samples = pixels with inner < radius <= outer; strong = value >= min + 0.2 * (max - min) over the annulus;
# angle = atan2(col - centreCol, row - centreRow), 36 bins of 10 deg; bound = 30 bins (default path), floor = 12 (acceptSparseCoverage).
import numpy as np
cr, cc = 31.7953815, 31.80266
rr, c2 = np.mgrid[0:64, 0:64]; dx = rr - cr; dy = c2 - cc; rad = np.hypot(dx, dy)
ang = np.arctan2(dy, dx); ang = np.where(ang < 0, ang + 2*np.pi, ang)
bins = np.minimum(35, (ang / (2*np.pi) * 36).astype(int))
lines = []
for nm, src in (('s1', 's1_mean'), ('s2', 's2_bvm')):
    img = np.fromfile(src + '.f32', '<f4').reshape(64, 64).astype(np.float64)
    for ln in open(src + '.annuli.txt'):
        if ln.startswith('#') or not ln.strip(): continue
        tag, a, b = ln.split(); a = float(a); b = float(b)
        sel = (rad > a) & (rad <= b); v = img[sel]
        thr = v.min() + 0.2 * (v.max() - v.min())
        occ = len(set(bins[sel][v >= thr]))
        lines.append('%-8s inner %-6g outer %-6g samples %4d  strongThreshold %.4g  occupiedBins %2d/36  default-path(>=30): %s  sparse-floor(>=12): %s' % (tag, a, b, sel.sum(), thr, occ, 'pass' if occ >= 30 else 'REFUSE', 'pass' if occ >= 12 else 'REFUSE'))
print('\n'.join(lines)); open('occupancy.txt', 'w').write('\n'.join(lines) + '\n')
