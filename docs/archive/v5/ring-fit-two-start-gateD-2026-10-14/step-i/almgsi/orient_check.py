# Axis-order check: S1 (mean pattern, row = 3rd cube axis) vs S2 (BVM built from the sidecar peaks): they must agree spot for spot as-is, and not under a transpose.
import numpy as np
a = np.fromfile('s1_mean.f32', '<f4').reshape(64, 64).astype(np.float64)
b = np.fromfile('s2_bvm.f32', '<f4').reshape(64, 64).astype(np.float64)
yy, xx = np.mgrid[0:64, 0:64]; r = np.hypot(yy - 31.795, xx - 31.803); sel = (r > 8) & (r < 31)
la = np.log10(1 + np.maximum(a, 0)); lb = np.log10(1 + np.maximum(b, 0))
# remove radial trend of the mean pattern: subtract each pixel's radial-bin mean
k = np.floor(r / 0.5).astype(int)
ra = la.copy()
for i in np.unique(k): ra[k == i] -= la[k == i].mean()
def corr(x, y): return np.corrcoef(x[sel], y[sel])[0, 1]
print('corr(S1 detrended, S2 log) as is: %.3f' % corr(ra, lb))
print('corr with S2 transposed (row<->col): %.3f' % corr(ra, lb.T))
print('corr with S2 flipped rows: %.3f ; flipped cols: %.3f' % (corr(ra, lb[::-1]), corr(ra, lb[:, ::-1])))
# the brightest S1 spots outside the beam and the same spots in S2
for nm, img in (('S1', a), ('S2', b)):
    m = img.copy(); m[r < 8] = 0; idx = np.argsort(m.ravel())[::-1][:6]
    print(nm, 'brightest outside r<8 (row,col):', [tuple(int(v) for v in np.unravel_index(i, m.shape)) for i in idx])
