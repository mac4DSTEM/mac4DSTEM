import numpy as np
def prof(path, cr, cc, binw=0.5):
    m = np.fromfile(path, '<f4').reshape(64, 64).astype(np.float64)
    rr, cc_ = np.mgrid[0:64, 0:64]
    r = np.hypot(rr - cr, cc_ - cc)
    k = np.floor(r / binw).astype(int)
    out = []
    for b in range(k.max() + 1):
        s = k == b
        if s.any(): out.append(((b + 0.5) * binw, m[s].mean(), int(s.sum())))
    return m, out
# S1 centre options
m1 = np.fromfile('s1_mean.f32', '<f4').reshape(64, 64).astype(np.float64)
yy, xx = np.mgrid[0:64, 0:64]
w = np.where(m1 > np.percentile(m1, 99), m1, 0); print('S1 top-1% CoM (row,col)', (w*yy).sum()/w.sum(), (w*xx).sum()/w.sum(), 'n px', int((w>0).sum()))
print('S1 argmax', np.unravel_index(m1.argmax(), m1.shape))
for nm, path, cr, cc in (('S1', 's1_mean.f32', 31.7953815, 31.80266), ('S2', 's2_bvm.f32', 31.7953815, 31.80266)):
    m, p = prof(path, cr, cc)
    print(nm)
    for r, v, n in p: print('%5.2f %12.5g %4d' % (r, v, n))
