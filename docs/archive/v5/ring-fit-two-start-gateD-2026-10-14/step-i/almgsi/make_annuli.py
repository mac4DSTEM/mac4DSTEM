# Ring-fit Gate D step (i) prep, Al-Mg-Si 060: radial profile, rings, annuli. NO FITS.
# Rule (the record's): one annulus per ring visible outside the central beam; inner/outer = ring peak -/+ half the distance to the
# neighbouring minimum on that side; plus each widened by 2 px on both sides; inner >= 1 px; outer <= distance centre -> farthest detector edge.
# How "peak" and "minimum" are read (fixed here, before any fit): profile = mean per 0.5 px radial bin (bin centre = radius), pixel
# centres at integer (row, col), as the fitter samples (EllipseCalibration.swift:159-166); smoothed once with [1,2,1]/4 (edge bins renormalised);
# a peak/minimum is a point that is the extreme of the smoothed profile within +-3 bins (+-1.5 px); a ring needs smoothed peak >= 1.5 x the
# larger of its two neighbouring minima; only radii <= the cap count (the last 0.5 px bin centre <= the farthest-edge distance); with no
# interior minimum on a side, that side's minimum is the cap bin.  Ties among equal minima: the one nearest the peak.
import numpy as np, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from rings import profile, smooth, extrema
BIN = 0.5
CENTRE = (31.7953815, 31.80266)      # (row, col) = (centerQX, centerQY) = (aperture.centerY, aperture.centerX): the sidecar's meanOrigin (bvm-run.log)
cap = max(CENTRE[0], 63 - CENTRE[0], CENTRE[1], 63 - CENTRE[1])
capbin = (np.floor((cap - BIN/2) / BIN)) * BIN + BIN/2     # last 0.5 px bin centre <= cap
def find(rad, ps, mx, mn):
    rings = []
    mnc = [i for i in mn if rad[i] <= capbin]
    for i in mx:
        if rad[i] <= capbin and ps[i] > 0:
            if rad[i] < 3.5:      # the central beam itself (app's measured probe radius 2.54 px; lineage s1/probe_radius_px)
                continue
            lo = [j for j in mnc if j < i]; hi = [j for j in mnc if j > i]
            jl = max(lo) if lo else None
            jh = min(hi) if hi else None
            vin = ps[jl] if jl is not None else 0.0
            vout = ps[jh] if jh is not None else ps[np.argmin(np.abs(rad - capbin))]
            if ps[i] < 1.5 * max(vin, vout):
                continue
            rin = rad[jl] if jl is not None else None
            rout = rad[jh] if jh is not None else capbin
            rings.append(dict(peak=rad[i], rin=rin, rout=rout, vp=ps[i], vin=vin, vout=vout, outcap=(jh is None)))
    return rings
def annuli(rings):
    out = []
    for k, r in enumerate(rings, 1):
        assert r['rin'] is not None
        a = r['peak'] - (r['peak'] - r['rin']) / 2; b = r['peak'] + (r['rout'] - r['peak']) / 2
        a = max(a, 1.0); b = min(b, cap)
        out.append(('R%d' % k, a, b, max(a - 2, 1.0), min(b + 2, cap)))
    return out
def run(name, srcfile, tag, desc, centre, extra_hdr):
    m = np.fromfile(srcfile, '<f4').reshape(64, 64).astype(np.float64)
    rad, mean, cnt = profile(m, centre[0], centre[1], BIN); ps = smooth(mean)
    mx, mn = extrema(ps, 3)
    rings = find(rad, ps, mx, mn)
    an = annuli(rings)
    # profile file
    with open(name + '.profile.txt', 'w') as f:
        f.write('# %s: azimuthal average about the centre guess (row, col) = (%.7f, %.7f); 0.5 px bins [r, r+0.5), radius = bin centre; mean over the pixels in the bin; count\n' % (desc, centre[0], centre[1]))
        f.write('# pixel centres at integer (row, col). columns: radius mean count\n')
        for r, v, n in zip(rad, mean, cnt): f.write('%.2f %.9g %d\n' % (r, v, n))
    with open(name + '.annuli.txt', 'w') as f:
        f.write('# %s | centre guess (row, col) = (%.7f, %.7f) | cap (farthest detector-edge distance) = %.5f, last bin centre %.2f\n' % (desc, centre[0], centre[1], cap, capbin))
        f.write('# read from %s.profile.txt: [1,2,1]/4-smoothed profile, peak and minima = extremes within +-3 bins (+-1.5 px); ring needs peak >= 1.5 x its larger neighbouring minimum; peak radius -/+ half the distance to the neighbouring minimum; a side with no interior minimum uses the cap bin; wN = widened 2 px both sides (inner >= 1, outer <= cap)\n' % name)
        for r in rings:
            f.write('# ring %s: smoothed peak r=%.2f (%.4g); inner min r=%.2f (%.4g); outer min r=%s (%.4g)\n' % (
                'R%d' % (rings.index(r) + 1), r['peak'], r['vp'], r['rin'], r['vin'], ('%.2f' % r['rout']) + (' [cap bin, no interior minimum]' if r['outcap'] else ''), r['vout']))
        f.write(extra_hdr)
        for t, a, b, aw, bw in an:
            f.write('%s-%s %.4g %.4g\n' % (tag, t, a, b)); f.write('%s-%sw %.4g %.4g\n' % (tag, t, aw, bw))
    # picture
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.6), gridspec_kw=dict(width_ratios=[1, 1.15]))
    img = np.log10(1 + np.maximum(m, 0))
    ax[0].imshow(img, cmap='magma', interpolation='nearest')
    ax[0].plot([centre[1]], [centre[0]], 'c+', ms=10)
    th = np.linspace(0, 2 * np.pi, 361)
    for t, a, b, aw, bw in an:
        for rr, ls in ((a, '-'), (b, '-'), (aw, ':'), (bw, ':')):
            ax[0].plot(centre[1] + rr * np.cos(th), centre[0] + rr * np.sin(th), 'c' + ls, lw=0.6, alpha=0.8)
    ax[0].set_xlim(-0.5, 63.5); ax[0].set_ylim(63.5, -0.5); ax[0].set_title('%s\nlog10(1+I), row down, col right; annuli solid, widened dotted, + = centre guess' % desc.split(' (')[0], fontsize=7)
    ax[1].semilogy(rad, np.maximum(mean, 1e-3 * max(mean.max(), 1) * 1e-6 + 1e-30), 'k.-', lw=0.6, ms=3)
    for t, a, b, aw, bw in an:
        ax[1].axvspan(a, b, color='c', alpha=0.25); ax[1].axvspan(aw, bw, color='c', alpha=0.08)
    ax[1].axvline(cap, color='r', lw=0.6); ax[1].set_xlabel('radius (px), 0.5 px bins'); ax[1].set_ylabel('azimuthal mean (zeros drawn at a floor)'); ax[1].set_title('radial profile; shaded = annuli (widened lighter); red = cap', fontsize=8)
    ax[1].set_ylim(max(mean[mean > 0].min() * 0.5, 1e-3), mean.max() * 2)
    plt.tight_layout(); plt.savefig(name + '.png', dpi=110); plt.close()
    return rad, mean, ps, rings, an
if __name__ == '__main__':
    alt = None
    run('s1_mean', 's1_mean.f32', 's1', 'S1 Al-Mg-Si 060 mean pattern (64x64)', CENTRE, '')
    run('s2_bvm', 's2_bvm.f32', 's2', 'S2 Al-Mg-Si 060 Bragg-vector map from the saved vectors (64x64)', CENTRE, '')
