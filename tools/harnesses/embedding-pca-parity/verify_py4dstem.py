#!/usr/bin/env python3
"""Decomposition parity for DiffractionEmbedding against py4DSTEM and numpy.

WHAT THIS CAN AND CANNOT CHECK -- established 2026-09-11 by reading the pinned
upstream and by measurement, not assumed:

  CAN   PCA decomposition, against py4DSTEM's OWN Featurization.PCA, which
        accepts an arbitrary (positions x dims) matrix (featurization.py:86-94).
        Verified: its scores equal sklearn's transform to 9.8e-15.
  CAN   symmetricEigenTop against numpy.linalg.eigh. This is the check that
        would have caught the 2026-09-06 subspace-iteration defect, which
        returned one power step instead of converged eigenpairs; the PCA
        checks alone cannot, because explained-variance RATIOS hide a uniform
        eigenvalue error.
  CANNOT  the FEATURISATION. py4DSTEM's only shipped featuriser is
        from_braggvectors; it has no binned-pattern representation, which is
        what DiffractionEmbedding.swift's DEVIATION at :39-45 already says.
  CANNOT  k-means. `grep -rin "kmeans|k_means|KMeans"` over the pinned tree
        returns NOTHING -- py4DSTEM clusters with GaussianMixture. Any k-means
        number here is an sklearn reference, never a py4DSTEM parity, and is
        PRINTED rather than gated so the distinction cannot be lost.
  CANNOT  a real cube. py4DSTEM passes neither svd_solver nor random_state, so
        sklearn's 'auto' flips to the randomized solver above 500 rows and the
        upstream number stops being deterministic. Measured: n=500 -> 0.0
        run-to-run drift, n=501 -> 5.9e-4. The fixture is capped at 400.

Some numbers below come from py4DSTEM and some from a direct sklearn call,
because Featurization discards the fitted estimator (featurization.py:373-374)
and so never exposes components_ or explained_variance_ratio_. Gate 0 licenses
the substitution by proving the two agree on this exact input. Every assertion
names its source.
"""
import json, sys
import numpy as np

WORK = sys.argv[1]
r = json.load(open(f"{WORK}/result.json"))
P, D = r["positions"], r["dims"]
K = r["componentCount"]
X = np.fromfile(f"{WORK}/features.f64", dtype="<f8").reshape(P, D)

fails, checks = [], 0
def check(name, ok, measured, tol, source):
    global checks
    checks += 1
    status = "ok  " if ok else "FAIL"
    print(f"  [{status}] {name:46s} {measured:12.3e}  tol {tol:9.3e}   [{source}]")
    if not ok:
        fails.append(name)

print(f"embedding-pca-parity: {P} positions x {D} dims, {K} components")

# ---- Gate 0: py4DSTEM's PCA == sklearn's, on THIS matrix ------------------
sys.path.insert(0, f"{WORK}/../py4DSTEM-dev")
from py4DSTEM.process.classification.featurization import Featurization
from sklearn.decomposition import PCA

f = Featurization(X.copy(), R_Nx=r["scanWidth"], R_Ny=r["scanHeight"], name="parity")
f.PCA(components=K)
sk = PCA(n_components=K).fit(X)
gate0 = np.abs(f.pca - sk.transform(X)).max()
check("gate 0: py4DSTEM scores == sklearn transform", gate0 < 1e-10, gate0, 1e-10, "py4DSTEM+sklearn")

# ---- Guard F: the comparisons below are only meaningful if ----------------
# eigenvalues are well separated (else eigenvector direction is noise) and the
# solver is the exact one (else the reference itself is nondeterministic).
ev = sk.explained_variance_[:K]
gaps = np.abs(np.diff(ev)) / np.maximum(ev[:-1], 1e-300)
print(f"  guard F: min relative eigenvalue gap = {gaps.min():.3f} (need >= 0.1)")
# That number is FIXED, not sampled: the fixture is a seeded LCG with no
# randomness anywhere in the pipeline, and two consecutive runs both give
# 0.115. So a value near the floor is not a flake risk -- the guard fires only
# if someone edits the fixture or the engine, which is what it is for. 0.1 is
# where per-component eigenvector comparison stops meaning anything.
print(f"  guard F: sklearn solver = {sk._fit_svd_solver!r} (need 'full')")
if gaps.min() < 0.1:
    fails.append("guard F: eigenvalues too close -- per-component checks are noise")
if sk._fit_svd_solver != "full":
    fails.append(f"guard F: solver is {sk._fit_svd_solver!r}, not 'full' -- reference is nondeterministic")

# ---- A. explained variance ------------------------------------------------
ours_ev = np.array(r["explainedVariance"][:K])
a = np.abs(ours_ev - sk.explained_variance_ratio_[:K]).max()
check("A: explainedVariance vs explained_variance_ratio_", a < 1e-6, a, 1e-6, "sklearn")

# ---- B/C. the basis, per component, sign-aligned --------------------------
ours_basis = np.array(r["basis"]).reshape(K, D)
cos_worst, elem_worst = 1.0, 0.0
for i in range(K):
    u, v = ours_basis[i], sk.components_[i]
    s = np.sign(np.dot(u, v)) or 1.0
    c = abs(np.dot(u, v)) / (np.linalg.norm(u) * np.linalg.norm(v))
    cos_worst = min(cos_worst, c)
    elem_worst = max(elem_worst, np.abs(u * s - v).max())
check("B: |cos(basis_i, components_i)|", 1 - cos_worst < 1e-6, 1 - cos_worst, 1e-6, "sklearn")
check("C: basis elementwise, sign-aligned", elem_worst < 1e-6, elem_worst, 1e-6, "sklearn")

# ---- D. coordinates vs py4DSTEM's OWN scores ------------------------------
ours_coord = np.array(r["coordinates"]).reshape(P, K)
scale = max(np.abs(f.pca).max(), 1e-30)
dw = 0.0
for i in range(K):
    s = np.sign(np.dot(ours_coord[:, i], f.pca[:, i])) or 1.0
    dw = max(dw, np.abs(ours_coord[:, i] * s - f.pca[:, i]).max())
check("D: coordinates vs py4DSTEM scores", dw < 1e-5 * scale, dw, 1e-5 * scale, "py4DSTEM")

# ---- E. the mean vector ---------------------------------------------------
e = np.abs(np.array(r["mean"]) - X.mean(axis=0)).max()
check("E: mean vs X.mean(axis=0)", e < 1e-6, e, 1e-6, "numpy")

# ---- Scope 2: the eigensolver alone ---------------------------------------
d = r["eigenDimension"]
M = np.fromfile(f"{WORK}/eigen_input.f64", dtype="<f8").reshape(d, d)
w, V = np.linalg.eigh(M)
top = np.argsort(w)[::-1][:8]
ours_vals = np.array(r["eigenValues"][:8])
rel = np.abs(ours_vals - w[top]).max() / max(np.abs(w[top]).max(), 1e-300)
check("S2a: symmetricEigenTop eigenvalues vs eigh", rel < 1e-12, rel, 1e-12, "numpy")
ours_vecs = np.array(r["eigenVectors"]).reshape(-1, d)[:8]
cw = 1.0
for i in range(8):
    u, v = ours_vecs[i], V[:, top[i]]
    cw = min(cw, abs(np.dot(u, v)) / (np.linalg.norm(u) * np.linalg.norm(v)))
check("S2b: symmetricEigenTop eigenvectors vs eigh", 1 - cw < 1e-10, 1 - cw, 1e-10, "numpy")

# ---- k-means: PRINTED, NEVER GATED ----------------------------------------
from sklearn.cluster import KMeans
km = KMeans(n_clusters=4, n_init=10, random_state=0).fit(ours_coord)
ours_g = np.array(r["groupOf"])
best = 0
from itertools import permutations
for p in permutations(range(4)):
    best = max(best, (np.array([p[g] for g in km.labels_]) == ours_g).mean())
print(f"  [note] k-means agreement with sklearn (best label permutation): {best:.3f}")
print("  [note] NOT GATED, and not a py4DSTEM parity: the pinned py4DSTEM ships")
print("  [note] no k-means at all -- it clusters with GaussianMixture.")

print(f"embedding-pca-parity: {checks} gated checks, {len(fails)} failed")
if fails:
    for n in fails: print(f"  FAILED: {n}", file=sys.stderr)
    sys.exit(1)
print("embedding-pca-parity: all passed")
