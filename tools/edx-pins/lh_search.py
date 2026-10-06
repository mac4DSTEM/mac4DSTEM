import numpy as np
from scipy.optimize import nnls
def lh_backtracks(A, y):
    m, n = A.shape; P = np.zeros(n, bool); x = np.zeros(n); back = 0
    for _ in range(3*n+100):
        w = A.T @ (y - A @ x)
        Z = np.where(~P)[0]
        if len(Z) == 0 or w[Z].max() <= 1e-12: break
        t = Z[np.argmax(w[Z])]; P[t] = True
        while True:
            idx = np.where(P)[0]
            s = np.zeros(n); s[idx] = np.linalg.lstsq(A[:, idx], y, rcond=None)[0]
            if (s[idx] > 0).all(): x = s; break
            back += 1
            neg = idx[s[idx] <= 0]
            alpha = np.min(x[neg] / (x[neg] - s[neg]))
            x = x + alpha * (s - x)
            P[idx[x[idx] <= 1e-14]] = False; x[~P] = 0
    return x, back
rng = np.random.default_rng(424242)
found = []
for trial in range(4000):
    m_, n_ = int(rng.integers(30, 90)), int(rng.integers(4, 9))
    A = rng.random((m_, n_))
    # correlated columns make a column enter and later turn negative
    for j in range(1, n_):
        if rng.random() < 0.6: A[:, j] = A[:, j - 1] * rng.uniform(0.5, 1.5) + 0.15 * rng.random(m_)
    xt = rng.normal(size=n_) * 2
    y = A @ xt + 0.3 * rng.normal(size=m_)
    xs, back = lh_backtracks(A, y)
    xr, _ = nnls(A, y, maxiter=100000)
    if back >= 2 and np.allclose(xs, xr, atol=1e-8) and (xr == 0).any() and (xr > 0).any():
        found.append((A, y, xr, back))
        if len(found) == 3: break
print([(f[0].shape, f[3]) for f in found])
