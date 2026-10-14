# Do the annuli change if the centre guess is the P5 rule (intensity-weighted centroid of the brightest 1 % of the mean pattern) or the float64 mean of the origin maps?
import numpy as np, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_annuli as M
from rings import profile, smooth, extrema
m1 = np.fromfile('s1_mean.f32', '<f4').reshape(64, 64).astype(np.float64)
yy, xx = np.mgrid[0:64, 0:64]; w = np.where(m1 > np.percentile(m1, 99), m1, 0)
p5 = ((w*yy).sum()/w.sum(), (w*xx).sum()/w.sum())
print('P5 rule centre (row,col) from S1: %.7f %.7f ; app centre %.7f %.7f ; diff %.4f %.4f' % (p5 + M.CENTRE + (p5[0]-M.CENTRE[0], p5[1]-M.CENTRE[1])))
f64 = (31.817291557112345, 31.8049831339238)
for nm, src, cen in (('S1', 's1_mean.f32', M.CENTRE), ('S1', 's1_mean.f32', p5), ('S2', 's2_bvm.f32', M.CENTRE), ('S2', 's2_bvm.f32', f64), ('S2', 's2_bvm.f32', p5)):
    m = np.fromfile(src, '<f4').reshape(64, 64).astype(np.float64)
    rad, mean, cnt = profile(m, cen[0], cen[1]); ps = smooth(mean); mx, mn = extrema(ps, 3)
    rings = M.find(rad, ps, mx, mn); an = M.annuli(rings)
    print(nm, 'centre (%.4f, %.4f)' % cen, [(t, a, b, aw, bw) for t, a, b, aw, bw in an])
