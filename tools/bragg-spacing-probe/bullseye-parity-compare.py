# bullseye-parity-compare.py — py4DSTEM side of the 2026-09-05 parity (get_probe_kernel_flat on probe_template
# slice 0, origin (125,125), find_Bragg_disks on the same 90 positions), paired with the app dump within 1 px.
#   $HOME/miniconda3/envs/py4dstem/bin/python tools/bragg-spacing-probe/bullseye-parity-compare.py <app-peaks.txt> [minRel]
# Retained result: 878/878 at 0.05 and 164/164 at 0.1, |d| <= 0.0013 px, intensity ratio 1.0000.
import sys, h5py, numpy as np, warnings; warnings.filterwarnings("ignore")
from py4DSTEM.braggvectors import Probe, find_Bragg_disks
app_file = sys.argv[1]; min_rel = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
f = h5py.File('References/training_dataset/calibrationData_bullseyeProbe.h5', 'r')
probe = f['4DSTEM_experiment/data/diffractionslices/probe_template/data'][:, :, 0].astype(np.float64)
cube = f['4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data']
p = Probe(probe); p.get_kernel(mode="flat", origin=(125, 125)); kernel = p.kernel
app = {}
for line in open(app_file):
    parts = line.split()
    if len(parts) != 5: continue
    try: ry, rx, x, y, I = int(parts[0]), int(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
    except ValueError: continue
    app.setdefault((ry, rx), []).append((x, y, I))
matched = total_py = total_app = 0; residuals = []; count_diff = []
for ry in range(0, cube.shape[0], 10):
    for rx in range(0, cube.shape[1], 10):
        pat = cube[ry, rx].astype(np.float64)
        q = find_Bragg_disks(pat, kernel, minPeakSpacing=8, edgeBoundary=6, minRelativeIntensity=min_rel, subpixel='poly', sigma_cc=2)
        py = [(float(b), float(a), float(c)) for a, b, c in zip(q.data['qx'], q.data['qy'], q.data['intensity'])]  # (x=col, y=row)
        ap = app.get((ry, rx), [])
        total_py += len(py); total_app += len(ap); count_diff.append(len(ap) - len(py))
        for (x, y, I) in py:
            if ap:
                d = [np.hypot(ax - x, ay - y) for ax, ay, _ in ap]
                j = int(np.argmin(d))
                if d[j] < 1.0: matched += 1; residuals.append((ap[j][0] - x, ap[j][1] - y, ap[j][2] / I if I else np.nan))
r = np.array(residuals)
print(f"minRel {min_rel}: py4DSTEM peaks {total_py}, app peaks {total_app}, matched within 1 px {matched} ({matched/max(total_py,1):.3f} of py4DSTEM's)")
print(f"  per-position count difference app-py: min {min(count_diff)} median {int(np.median(count_diff))} max {max(count_diff)}")
if len(r):
    print(f"  matched residual |dx| max {np.abs(r[:,0]).max():.4f} median {np.median(np.abs(r[:,0])):.4f}   |dy| max {np.abs(r[:,1]).max():.4f} median {np.median(np.abs(r[:,1])):.4f}")
    print(f"  intensity ratio app/py median {np.median(r[:,2]):.4f} min {r[:,2].min():.4f} max {r[:,2].max():.4f}")
