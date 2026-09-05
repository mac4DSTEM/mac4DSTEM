# origin-kernel-twin.py — Gate B refuter, 2026-09-05 (docs/q-calibration-design.md §9).
# Numpy twins of the OLD (single-pass, 1.2 r) and NEW (iterated, max(1.2 r, r + 1.5 px))
# measureOrigin kernels, py4DSTEM get_origin_single_dp (PY) and an iterated 3 r centre of
# mass from the PY seed (WIDE, the truth proxy), over the training cubes in References/.
# Diagnostic, never gates — needs the machine-local training set. Run:
#   $HOME/miniconda3/envs/py4dstem/bin/python tools/origin-fit-diagnostics/origin-kernel-twin.py [name-substring ...]
import sys, h5py, numpy as np
from scipy.ndimage import gaussian_filter, maximum_filter
from py4DSTEM.process.calibration import get_probe_size

def block_coarse(pat, r):
    b = max(1, int(round(r))); qy, qx = pat.shape
    best = -np.inf; cx = 0.5*(qx-1); cy = 0.5*(qy-1)
    for by in range(0, qy, b):
        ye = min(by+b, qy)
        for bx in range(0, qx, b):
            xe = min(bx+b, qx)
            s = pat[by:ye, bx:xe].sum()
            if s > best: best = s; cx = 0.5*(bx+xe-1); cy = 0.5*(by+ye-1)
    return cx, cy

def com(pat, cx, cy, win, passes):
    qy, qx = pat.shape; yy, xx = np.mgrid[0:qy, 0:qx]
    p = np.maximum(pat, 0)
    for _ in range(passes):
        m = (xx-cx)**2 + (yy-cy)**2 <= win*win
        s = p[m].sum()
        if not s > 0: break
        nx = (p*xx)[m].sum()/s; ny = (p*yy)[m].sum()/s
        settled = abs(nx-cx) < 1e-4 and abs(ny-cy) < 1e-4
        cx, cy = nx, ny
        if settled: break
    return cx, cy

def py_seed(pat, r):
    iy, ix = np.unravel_index(np.argmax(gaussian_filter(pat, r, mode='nearest')), pat.shape)
    return float(ix), float(iy)

def innermost_feature(mean, cx, cy, r):
    qy, qx = mean.shape; yy, xx = np.mgrid[0:qy, 0:qx]
    rad = np.hypot(xx-cx, yy-cy)
    # radial profile, 0.5 px bins
    bins = np.arange(0, rad.max(), 0.5); prof = np.array([mean[(rad>=a)&(rad<a+0.5)].mean() if ((rad>=a)&(rad<a+0.5)).any() else np.nan for a in bins])
    # first local max beyond the beam (after profile has fallen below 20% of centre)
    fell = np.where(prof < 0.2*np.nanmax(prof[:3]))[0]
    ring = np.nan
    if len(fell):
        i0 = fell[0]
        for i in range(i0+1, len(prof)-1):
            if prof[i] > prof[i-1] and prof[i] >= prof[i+1]: ring = bins[i]+0.25; break
    # nearest local maximum of the smoothed mean outside 1.5 r of the beam
    g = gaussian_filter(mean, 1.0); lm = (g == maximum_filter(g, size=5)) & (g > 0.02*g.max())
    d = rad[lm]; d = d[d > 1.5*r]
    return ring, (d.min() if len(d) else np.nan)

def main(path, dset, stride_note=''):
    with h5py.File(path, 'r') as h:
        ds = h[dset]; ry, rx, qy, qx = ds.shape
        sy = max(1, ry//12); sx = max(1, rx//12)
        sample = ds[::sy, ::sx, :, :].astype(np.float64)
    sample = sample.reshape(-1, qy, qx)
    mean = np.nanmean(sample, axis=0)
    r, x0, y0 = get_probe_size(mean)
    win_new = max(1.2*r, r+1.5)
    ring, nearest = innermost_feature(mean, x0, y0, r)
    print(f"== {path.split('/')[-1][:40]}  q={qy}x{qx}  sample={sample.shape[0]}  r={r:.3f}  1.2r={1.2*r:.3f}  r+1.5={r+1.5:.3f}  win_new={win_new:.3f}")
    print(f"   innermost ring radius ~{ring:.2f}   nearest off-beam local max at {nearest:.2f} px;  window admits ring inner edge (ring - r < win)? {'YES' if ring - r < win_new else 'no'} (old 1.2r: {'YES' if ring - r < 1.2*r else 'no'})")
    res = {k: [] for k in ('OLD','NEW','PY','WIDE')}
    for pat in sample:
        pat = np.nan_to_num(pat)
        bx, by = block_coarse(pat, r)
        res['OLD'].append(com(pat, bx, by, 1.2*r, 1))
        res['NEW'].append(com(pat, bx, by, win_new, 4))
        px, py = py_seed(pat, r)
        res['PY'].append(com(pat, px, py, 1.2*r, 1))
        res['WIDE'].append(com(pat, px, py, 3*r, 4))
    for k, v in res.items():
        v = np.array(v); print(f"   {k:4s} mean ({v[:,0].mean():.4f}, {v[:,1].mean():.4f})  median ({np.median(v[:,0]):.4f}, {np.median(v[:,1]):.4f})  sd ({v[:,0].std():.3f}, {v[:,1].std():.3f})")
    o = np.array(res['OLD']); n = np.array(res['NEW']); w = np.array(res['WIDE']); p = np.array(res['PY'])
    print(f"   NEW-OLD mean shift ({(n-o)[:,0].mean():+.4f}, {(n-o)[:,1].mean():+.4f});  NEW-WIDE ({(n-w)[:,0].mean():+.4f}, {(n-w)[:,1].mean():+.4f});  OLD-WIDE ({(o-w)[:,0].mean():+.4f}, {(o-w)[:,1].mean():+.4f});  PY-WIDE ({(p-w)[:,0].mean():+.4f}, {(p-w)[:,1].mean():+.4f})")
    print(f"   per-pattern |NEW-WIDE| max {np.abs(n-w).max():.3f}   |OLD-WIDE| max {np.abs(o-w).max():.3f}   |PY-WIDE| max {np.abs(p-w).max():.3f}")

D = '/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/'
sets = [
 ('polycrystal_2D_WS2.h5', '4DSTEM/datacube/data'),
 ('sim_Au_data_all_binned.h5', '4DSTEM_simulation/4DSTEM_polyAu/data'),
 ('sim_Au_data_all_binned.h5', '4DSTEM_simulation/4DSTEM_AuNanoplatelet/data'),
 ('downsample_Si_SiGe_exp.h5', '4DSTEM_experiment/data/datacubes/datacube_0/data'),
 ('SPED_MgO.hdf5', 'Experiments/SPED of MgO/data'),
 ('Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5', 'datacube_root/datacube/data'),
 ('twisted_bilayer_graphene.hdf5', 'ds'),
 ('060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5', 'dm_dataset_root/dm_dataset/data'),
 ('COPL_Ni65Cu35_C_ROI6_240911_aper_70_conv_2.1_spot_6_CL_35_stepsize_3_r_x_200_r_y_200_GIF_512x512_preprocessed_unfiltered_bin_4_20240912.h5', 'dm_dataset_root/dm_dataset/data'),
 ('Si-SiGe_calibrated.h5', 'datacube_root/datacube/data'),
]
only = sys.argv[1:] 
for f, d in sets:
    if only and not any(o in f for o in only): continue
    try: main(D+f, d)
    except Exception as e: print(f"== {f[:40]} FAILED: {e!r}")
