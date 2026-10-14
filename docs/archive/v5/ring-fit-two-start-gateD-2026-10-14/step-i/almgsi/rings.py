# Ring finder for step (i) prep: radial profile about a centre guess, [1,2,1]/4-smoothed, local extrema within +-3 bins (+-1.5 px).
import numpy as np
def profile(m, cr, cc, binw=0.5):
    rr, c2 = np.mgrid[0:m.shape[0], 0:m.shape[1]]
    r = np.hypot(rr - cr, c2 - cc); k = np.floor(r / binw).astype(int)
    rad, mean, cnt = [], [], []
    for b in range(k.max() + 1):
        s = k == b
        if s.any(): rad.append((b + 0.5) * binw); mean.append(m[s].mean()); cnt.append(int(s.sum()))
    return np.array(rad), np.array(mean), np.array(cnt)
def smooth(p):
    q = np.empty_like(p)
    for i in range(len(p)):
        a = p[i-1] if i > 0 else None; c = p[i+1] if i < len(p)-1 else None
        w = [2.0]; v = [2.0*p[i]]
        if a is not None: w.append(1.0); v.append(a)
        if c is not None: w.append(1.0); v.append(c)
        q[i] = sum(v)/sum(w)
    return q
def extrema(ps, win=3):
    mx, mn = [], []
    for i in range(len(ps)):
        lo, hi = max(0, i-win), min(len(ps), i+win+1)
        seg = ps[lo:hi]
        if ps[i] == seg.max() and i not in (0, len(ps)-1): mx.append(i)
        if ps[i] == seg.min() and i not in (0, len(ps)-1): mn.append(i)
    return mx, mn
if __name__ == '__main__':
    import sys
    path, cr, cc = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    m = np.fromfile(path, '<f4').reshape(64, 64).astype(np.float64)
    rad, mean, cnt = profile(m, cr, cc); ps = smooth(mean)
    mx, mn = extrema(ps)
    print('maxima (smoothed):', [(rad[i], round(ps[i], 4)) for i in mx])
    print('minima (smoothed):', [(rad[i], round(ps[i], 4)) for i in mn])
