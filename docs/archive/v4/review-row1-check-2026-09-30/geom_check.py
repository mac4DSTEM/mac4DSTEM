"""Row 1 geometric check with the Swift constants.
Ports CubicOrientationSymmetry.reduceDirection / sampleFundamentalZone(count: 600)
(OrientationResult.swift:157-209) and ACOMOrientation.detectorBasis (:91-96) verbatim.
"""
import numpy as np, itertools
np.set_printoptions(precision=3, suppress=True)

def reduce_direction(d):                       # OrientationResult.swift:158-163
    v = np.sort(np.abs(d))                     # ascending
    out = np.array([v[1], v[0], v[2]])         # (middle, smallest, largest): z >= x >= y >= 0
    return out / np.linalg.norm(out)

def sample_fundamental_zone(count=600):        # OrientationResult.swift:169-209
    verts = [np.array([0,0,1.]), np.array([1,0,1.])/np.sqrt(2), np.array([1,1,1.])/np.sqrt(3)]
    cand_n = max(128, count*12)
    golden = np.pi*(3-np.sqrt(5))
    cands = []
    for i in range(cand_n):
        z = 1 - 2*(i+0.5)/cand_n
        r = np.sqrt(max(0, 1-z*z)); az = golden*i
        cands.append(reduce_direction(np.array([r*np.cos(az), r*np.sin(az), z])))
    cands = np.array(cands)
    selected = list(verts)
    min_chord = np.min([1 - cands @ v for v in verts], axis=0)
    while len(selected) < count:
        best = int(np.argmax(min_chord))
        nxt = cands[best]; selected.append(nxt)
        min_chord = np.minimum(min_chord, 1 - cands @ nxt)
        min_chord[best] = -np.inf
    return np.array(selected)

def detector_basis(n):                          # OrientationResult.swift:91-96
    ref = np.array([1,0,0.]) if abs(n[0]) < 0.9 else np.array([0,1,0.])
    e1 = np.cross(n, ref); e1 /= np.linalg.norm(e1)
    e2 = np.cross(n, e1)
    return e1, e2

# 24 proper + 24 improper signed permutation matrices (OrientationResult.swift:114-135 for the proper set)
proper, improper = [], []
for perm in itertools.permutations(range(3)):
    for signs in itertools.product([-1,1], repeat=3):
        M = np.zeros((3,3))
        for r in range(3): M[r, perm[r]] = signs[r]
        (proper if np.linalg.det(M) > 0.5 else improper).append(M)
assert len(proper) == 24 and len(improper) == 24
full = proper + improper

# FCC Al reflections (geometry only; kMax 1.2 as in AppState+ACOM.swift:172)
a = 4.0495; kmax = 1.2
refl = []
for h,k,l in itertools.product(range(-6,7), repeat=3):
    if (h,k,l) == (0,0,0): continue
    if not (h%2 == k%2 == l%2): continue            # fcc: all even or all odd
    g = np.array([h,k,l])/a
    if np.linalg.norm(g) <= kmax: refl.append(g)
refl = np.array(refl)

def zolz_spots(n, sg_max=0.1):                    # OrientationPlan.project, wavelength nil -> sg = g.n
    e1, e2 = detector_basis(n)
    sg = refl @ n
    sel = refl[np.abs(sg) <= sg_max]
    return np.stack([sel @ e1, sel @ e2], axis=1)

def chirality_signature(pts, tol=1e-6):
    """Rotation-invariant, reflection-odd descriptor: sorted (r_i, r_j, signed angle i->j)
    over the two shortest shells. Under a 2-D mirror every signed angle flips sign."""
    r = np.linalg.norm(pts, axis=1)
    shells = np.unique(np.round(r, 4))[:2]
    idx = [i for i in range(len(pts)) if np.round(r[i],4) in shells]
    sig = []
    for i in idx:
        for j in idx:
            if i == j: continue
            ang = np.arctan2(pts[i,0]*pts[j,1]-pts[i,1]*pts[j,0], pts[i]@pts[j])
            sig.append((round(r[i],3), round(r[j],3), round(ang,3)))
    return sorted(sig)

def matches_up_to_rotation(p_query, p_templ, tol=2e-3):
    """Exact test: is there an in-plane rotation R with R.templ == query as point sets?"""
    if len(p_query) != len(p_templ): return False
    rq = np.linalg.norm(p_query, axis=1); rt = np.linalg.norm(p_templ, axis=1)
    if not np.allclose(np.sort(rq), np.sort(rt), atol=tol): return False
    # candidate rotations: align the query's first non-zero spot with every template spot of equal radius
    i = int(np.argmax(rq > 1e-9))
    for j in np.where(np.abs(rt - rq[i]) < tol)[0]:
        th = np.arctan2(p_query[i,1], p_query[i,0]) - np.arctan2(p_templ[j,1], p_templ[j,0])
        R = np.array([[np.cos(th), -np.sin(th)],[np.sin(th), np.cos(th)]])
        rot = p_templ @ R.T
        # every rotated template point has a query point within tol
        d = np.linalg.norm(rot[:,None,:] - p_query[None,:,:], axis=2)
        if np.all(d.min(axis=1) < tol): return True
    return False

bank = sample_fundamental_zone(600)
print("bank size", len(bank), "; all in z>=x>=y>=0:", np.all((bank[:,2] >= bank[:,0]-1e-12) & (bank[:,0] >= bank[:,1]-1e-12) & (bank[:,1] >= -1e-12)))
# bank spacing: nearest-neighbour angle
dots = np.clip(bank @ bank.T, -1, 1); np.fill_diagonal(dots, -1)
nn = np.degrees(np.arccos(dots.max(axis=1)))
print("bank nearest-neighbour spacing deg: median %.2f max %.2f" % (np.median(nn), nn.max()))

def dist_to_bank(n, ops):
    imgs = np.array([M @ n for M in ops])
    d = np.degrees(np.arccos(np.clip(imgs @ bank.T, -1, 1)))
    return d.min()

queries = {
 "(2,1,3)  sampled triangle": np.array([2,1,3.]),
 "(1,2,3)  mirror  triangle": np.array([1,2,3.]),
 "(3,1,5)  sampled":          np.array([3,1,5.]),
 "(1,3,5)  mirror":           np.array([1,3,5.]),
 "(5,2,7)  sampled":          np.array([5,2,7.]),
 "(2,5,7)  mirror":           np.array([2,5,7.]),
 "(1,1,3)  edge x=y (on mirror plane)": np.array([1,1,3.]),
 "(1,2,2)  S20's <122> (on {110} plane)": np.array([1,2,2.]),
}
print("\n%-42s %10s %10s %8s %8s" % ("query axis (crystal frame)", "d_proper", "d_full48", "#proper", "#mirror"))
for name, q in queries.items():
    q = q/np.linalg.norm(q)
    pq = zolz_spots(q)
    sq = chirality_signature(pq); sq_m = chirality_signature(pq * np.array([1,-1]))
    n_prop = n_mirr = 0
    for m in bank:
        pm = zolz_spots(m)
        if matches_up_to_rotation(pq, pm): n_prop += 1
        if matches_up_to_rotation(pq * np.array([1,-1]), pm): n_mirr += 1
    print("%-42s %9.2f° %9.2f° %8d %8d" % (name, dist_to_bank(q, proper), dist_to_bank(q, full), n_prop, n_mirr))
print("\n#proper = bank templates whose spot set equals the query's up to an in-plane ROTATION;")
print("#mirror = bank templates equal to the query's MIRROR image up to a rotation.")

# Algebraic statement: detectorBasis(-n) = (-e1, e2, -n)  ->  the -n pattern is the x-mirror of the n pattern
n = np.array([2,1,3.])/np.sqrt(14); e1,e2 = detector_basis(n); f1,f2 = detector_basis(-n)
print("\nbasis(-n): e1' = -e1 ?", np.allclose(f1,-e1), " e2' = e2 ?", np.allclose(f2,e2))
# and -n of a sampled axis is a PROPER image of a mirror-triangle axis:
m = np.array([1,2,3.])/np.sqrt(14)
print("is -(2,1,3) a proper image of (1,2,3)?", any(np.allclose(M@m, -n) for M in proper),
      "; is (2,1,3) itself a proper image of (1,2,3)?", any(np.allclose(M@m, n) for M in proper))

# Whole-triangle statistics: random directions, fraction whose proper orbit misses the sampled triangle,
# and how far (d_proper) they are from every template on the proper orbit.
rng = np.random.default_rng(1)
v = rng.normal(size=(4000,3)); v /= np.linalg.norm(v, axis=1)[:,None]
dp = np.array([dist_to_bank(x, proper) for x in v]); df = np.array([dist_to_bank(x, full) for x in v])
miss = dp > df + 1e-9
print("\nrandom directions: fraction whose proper orbit is farther from the bank than the 48-fold fold: %.3f" % miss.mean())
print("d_full48: median %.2f max %.2f ; d_proper on the missed half: median %.2f, 90%% %.2f, max %.2f (bank floor on the axis error)"
      % (np.median(df), df.max(), np.median(dp[miss]), np.percentile(dp[miss],90), dp[miss].max()))
