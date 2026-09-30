"""Row 1, part B: numpy port of the shipped polar-FFT matcher with the Swift constants
(OrientationPlan.generate defaults: 32x128, kMax 1.2, sgWidth 0.03, sgMax 0.1, azimBlur 1.5 bins,
intensityPower 0.25, radialKernel 0.08 A^-1, wavelength nil; 600 zone axes).
Forward pass = OrientationMatcher.match (corr = IFFT sum_r conj(E_r) T_r);
'inverted' pass = py4DSTEM's corr_full_inv (conj(im_polar_fft)), which the port does NOT have.
"""
import numpy as np, itertools, sys
sys.path.insert(0, '.')
from geom_check import sample_fundamental_zone, detector_basis, proper, full, reduce_direction
np.set_printoptions(precision=3, suppress=True)

a = 4.0495; kmax = 1.2; NR, NA = 32, 128
sg_width, sg_max, power = 0.03, 0.1, 0.25
radial_scale = kmax / NR; sigma_r = 0.08 / radial_scale; reach = max(1, int(round(3*sigma_r)))
blur_sigma = 1.5

def fe_Al(g):   # Peng (1996) 4-Gaussian electron scattering factor for Al, s = |g|/2
    s2 = (np.linalg.norm(g)/2)**2
    A = [2.276, 2.428, 0.8579, 0.3266]; B = [72.19, 19.77, 3.264, 0.5709]
    return sum(ai*np.exp(-bi*s2) for ai, bi in zip(A, B))

refl = []
for h,k,l in itertools.product(range(-6,7), repeat=3):
    if (h,k,l) == (0,0,0) or not (h%2 == k%2 == l%2): continue
    g = np.array([h,k,l])/a
    if np.linalg.norm(g) <= kmax:
        F = 4*fe_Al(g)/a**3
        refl.append((g, F*F))
G = np.array([r[0] for r in refl]); I = np.array([r[1] for r in refl])

def project(n):                                   # OrientationPlan.project, wavelength nil
    e1, e2 = detector_basis(n)
    sg = G @ n
    keep = np.abs(sg) <= sg_max
    excited = I[keep] * np.exp(-(sg[keep]/sg_width)**2)
    w = excited ** power
    x = G[keep] @ e1; y = G[keep] @ e2
    return np.hypot(x, y), np.arctan2(y, x), w

def build_polar(r, az, w):                        # OrientationPlan.buildPolar
    img = np.zeros((NR, NA))
    for ri, ai, wi in zip(r, az, w):
        exact = ri / radial_scale; rb = int(round(exact))
        if rb + reach < 0 or rb - reach >= NR: continue
        aa = ai % (2*np.pi)
        ab = int(round(aa/(2*np.pi)*NA)) % NA
        for b in range(rb-reach, rb+reach+1):
            if 0 <= b < NR:
                d = (b - exact)/sigma_r
                img[b, ab] += wi*np.exp(-0.5*d*d)
    # circular azimuthal Gaussian blur
    rad = max(1, int(round(3*blur_sigma)))
    taps = np.array([np.exp(-i*i/(2*blur_sigma**2)) for i in range(-rad, rad+1)]); taps /= taps.sum()
    out = np.zeros_like(img)
    for t, tap in zip(range(-rad, rad+1), taps):
        out += np.roll(img, t, axis=1) * tap      # out[a] += img[a - t]... symmetric taps, so fine
    img = out
    img -= img.mean(axis=1, keepdims=True)         # per-ring mean subtraction
    nrm = np.linalg.norm(img)
    return img/nrm if nrm > 0 else img             # normalizeUnit (L2)

bank = sample_fundamental_zone(600)
T = np.array([np.fft.fft(build_polar(*project(m)), axis=1) for m in bank])   # (600, NR, NA)

def match(E, inverted=False):
    Ef = np.fft.fft(E, axis=1)
    Ef = np.conj(Ef) if inverted else Ef
    corr = np.real(np.fft.ifft(np.sum(np.conj(Ef)[None] * T, axis=1), axis=1))  # (600, NA)
    scores = corr.max(axis=1); bins = corr.argmax(axis=1)
    t = int(scores.argmax()); return t, scores[t], bins[t]

def axis_err_proper(n, m):
    return min(np.degrees(np.arccos(np.clip((M@n)@m, -1, 1))) for M in proper)
def axis_err_full(n, m):
    return min(np.degrees(np.arccos(np.clip((M@n)@m, -1, 1))) for M in full)

rng = np.random.default_rng(7)
truths = [("(2,1,3)", [2,1,3]), ("(3,1,5)", [3,1,5]), ("(5,2,7)", [5,2,7]), ("(4,1,6)", [4,1,6]), ("(7,3,9)", [7,3,9])]
print("%-22s %-9s | forward pass (shipped): err_proper err_full  score | inverted pass (py4DSTEM corr_full_inv): err_proper err_full score"
      % ("truth axis", "triangle"))
for label, v in truths:
    for tri, vec in (("sampled", np.array(v, float)), ("mirror", np.array([v[1], v[0], v[2]], float))):
        n = vec/np.linalg.norm(vec)
        r, az, w = project(n)
        theta = np.radians(17.3)                   # off-grid in-plane rotation
        # experimental peaks: positions in A^-1, intensity = weight^(1/power) so the matcher's power restores w
        E = build_polar(r, az + theta, w)          # (the matcher raises intensity^0.25 = w; same deposit)
        t, s, b = match(E); ti, si, bi = match(E, inverted=True)
        print("%-22s %-9s | %9.2f° %8.2f° %6.3f | %9.2f° %8.2f° %6.3f"
              % (label, tri, axis_err_proper(n, bank[t]), axis_err_full(n, bank[t]), s,
                 axis_err_proper(n, bank[ti]), axis_err_full(n, bank[ti]), si))

# random generic truths: distribution of the shipped winner's proper-orbit axis error, split by triangle
errs_s, errs_m, sc_s, sc_m = [], [], [], []
for _ in range(60):
    n = rng.normal(size=3); n /= np.linalg.norm(n)
    nf = reduce_direction(n)                       # 48-fold fold into T0
    in_sampled = any(np.allclose(M@n, nf, atol=1e-9) for M in proper)
    r, az, w = project(n)
    E = build_polar(r, az + rng.uniform(0, 2*np.pi), w)
    t, s, b = match(E)
    e = axis_err_proper(n, bank[t])
    (errs_s if in_sampled else errs_m).append(e); (sc_s if in_sampled else sc_m).append(s)
def summ(x): return "n=%d median %.2f° 90%% %.2f° max %.2f°" % (len(x), np.median(x), np.percentile(x, 90), np.max(x))
print("\nrandom truths, shipped forward pass, winner axis error under the proper group:")
print("  sampled-triangle truths:", summ(errs_s), " score median %.3f" % np.median(sc_s))
print("  mirror-triangle  truths:", summ(errs_m), " score median %.3f" % np.median(sc_m))
