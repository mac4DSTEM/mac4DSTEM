# bullseye-kernel-truth.py — Gate D truth for "Bullseye disk detection accepts noise" (open-items.md, 2026-09-05).
# py4DSTEM find_Bragg_disks on 90 strided positions of polyAu_4DSTEM with the measured probe_template kernel
# (flat and sigmoid modes), flat synthetic disks at the estimator radius and the true 11.5 px radius, and a
# relative-threshold scan (--scan). Diagnostic, never gates; needs References/training_dataset. Run from the repo root:
#   $HOME/miniconda3/envs/py4dstem/bin/python tools/bragg-spacing-probe/bullseye-kernel-truth.py [--scan]
import sys
from py4DSTEM.process.calibration import get_probe_size
from py4DSTEM.braggvectors import Probe, find_Bragg_disks
f = h5py.File('References/training_dataset/calibrationData_bullseyeProbe.h5','r')
probe = f['4DSTEM_experiment/data/diffractionslices/probe_template/data'][:, :, 0].astype(np.float64)
cube = f['4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data']
pats = cube[::10, ::10].astype(np.float64).reshape(-1, 250, 250)   # 90 positions
mean = pats.mean(axis=0)
r_est, x0, y0 = get_probe_size(mean)
print(f"positions {len(pats)}  probe r (estimator) {r_est:.2f}  bullseye outer radius ~11.5 px (profile)")
def synthetic_kernel(r, width=2):
    yy, xx = np.mgrid[0:250, 0:250]; rad = np.hypot(xx - 125, yy - 125)
    k = np.clip(1 - (rad - r) / width, 0, 1)                         # flat disk, linear edge
    k = k - k.mean(); return np.fft.ifftshift(k)                     # zero-mean, corner-centred
def template_kernel(mode="flat", **kw):
    # py4DSTEM probe.py get_kernel: "'flat' ... This mode is recommended for bullseye or other structured probes"
    p = Probe(probe); p.get_kernel(mode=mode, origin=(125, 125), **kw); return p.kernel
def measure(name, kernel, **kw):
    peaks = []
    for pat in pats:
        q = find_Bragg_disks(pat, kernel, minPeakSpacing=8, edgeBoundary=6, **kw)
        peaks.append(np.stack([q.data['qx'], q.data['qy'], q.data['intensity']], 1) if len(q.data) else np.zeros((0, 3)))
    counts = np.array([len(p) for p in peaks])
    radii = np.concatenate([np.hypot(p[:, 0] - x0, p[:, 1] - y0) for p in peaks]); radii = radii[radii > 2 * r_est]
    ring = np.nan
    if len(radii):
        h, e = np.histogram(radii, bins=np.arange(0, 130, 0.5)); modal = e[h.argmax()] + 0.25
        ring = (np.abs(radii - modal) / modal < 0.06).mean()
    ratio = np.array([p[1, 2] / p[0, 2] for p in peaks if len(p) >= 2])
    beam_first = np.mean([np.hypot(p[0, 0] - x0, p[0, 1] - y0) < 3 for p in peaks if len(p)])
    print(f"  {name:38s} peaks/pos median {np.median(counts):4.0f} min {counts.min():3d} max {counts.max():3d}  at-cap(70) {int((counts >= 70).sum()):3d}/{len(counts)}  ring-proxy {ring:.3f}  2nd/1st median {np.median(ratio) if len(ratio) else float('nan'):.3f}  beam-is-brightest {beam_first:.2f}")
    return peaks
print("py4DSTEM defaults (minRelativeIntensity 0.005 vs brightest):")
t = measure("template kernel, FLAT (bullseye route)", template_kernel("flat"))
measure("template kernel, sigmoid (7, 14) [wrong]", template_kernel("sigmoid", radii=(r_est, 2 * r_est)))
measure("template kernel, sigmoid (11.5, 23)", template_kernel("sigmoid", radii=(11.5, 23.0)))
s = measure(f"synthetic flat disk r={r_est:.2f}", synthetic_kernel(r_est))
b = measure("synthetic flat disk r=11.5", synthetic_kernel(11.5))
print("H3 — synthetic r_est with tighter relative thresholds:")
for mr in [0.05, 0.2]: measure(f"synthetic r={r_est:.2f}, minRel {mr}", synthetic_kernel(r_est), minRelativeIntensity=mr)
# agreement of each variant with the template set, per position: fraction of template peaks matched within 2 px
def agree(other, label):
    hit = tot = 0
    for a, o in zip(t, other):
        for p in a:
            tot += 1
            if len(o) and np.hypot(o[:, 0] - p[0], o[:, 1] - p[1]).min() < 2: hit += 1
    print(f"  template peaks recovered by {label}: {hit}/{tot}")
agree(s, f"synthetic r={r_est:.2f}"); agree(b, "synthetic r=11.5")

if "--scan" in sys.argv:
    print("threshold scan, py4DSTEM, 90 positions:")
    for label, kern in [("template FLAT", template_kernel("flat")), ("synthetic flat r=11.5", synthetic_kernel(11.5)), ("synthetic flat r=6.96 (app's)", synthetic_kernel(r_est))]:
        for mr in [0.005, 0.01, 0.02, 0.03, 0.05, 0.1]:
            measure(f"{label}, minRel {mr}", kern, minRelativeIntensity=mr)
    # intensity spectrum with the flat template kernel: per-position sorted intensities relative to the beam, pooled
    peaks = []
    for pat in pats:
        q = find_Bragg_disks(pat, template_kernel("flat"), minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=0, maxNumPeaks=200)
        I = np.sort(q.data['intensity'])[::-1]; peaks.append(I / I[0])
    pooled = np.concatenate([p[1:] for p in peaks])
    print("pooled non-beam relative intensities, template FLAT, maxNumPeaks 200:")
    for lo, hi in [(0.5,1.01),(0.2,0.5),(0.1,0.2),(0.05,0.1),(0.03,0.05),(0.02,0.03),(0.01,0.02),(0.005,0.01),(0,0.005)]:
        n = ((pooled >= lo) & (pooled < hi)).sum(); print(f"  [{lo:5.3f}, {hi:5.3f}): {n:6d} peaks  ({n/len(peaks):.1f}/position)")
