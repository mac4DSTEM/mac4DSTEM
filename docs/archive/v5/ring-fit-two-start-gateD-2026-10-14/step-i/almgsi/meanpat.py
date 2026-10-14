# S1: the mean diffraction pattern of the Al-Mg-Si 060 cube, mirroring VirtualDetector.tiledDPStatistics
# (VirtualDetector.swift:422-470): per-tile mean (float32 on Metal) combined as a double-weighted sum, divided by ry*rx, cast to Float.
# Here: float64 sum over all scan positions in tiles of 22 scan rows, / (ry*rx), cast float32 little-endian.
import h5py, numpy as np, sys
src = "/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5"
f = h5py.File(src, 'r'); d = f['dm_dataset_root/dm_dataset/data']
print('shape', d.shape, 'dtype', d.dtype, 'chunks', d.chunks)
ry, rx, qy, qx = d.shape
acc = np.zeros((qy, qx), np.float64); n = 0
for i in range(0, ry, 22):
    blk = d[i:i+22].astype(np.float64)
    acc += blk.sum(axis=(0, 1)); n += blk.shape[0] * blk.shape[1]
m = acc / n
m.astype('<f4').tofile('s1_mean.f32')
print('n', n, 'min', m.min(), 'max', m.max(), 'nonfinite', (~np.isfinite(m)).sum())
for k in f['dm_dataset_root/metadatabundle/calibration'].keys():
    try: print(k, f['dm_dataset_root/metadatabundle/calibration/'+k][()])
    except Exception as e: print(k, 'ERR', e)
