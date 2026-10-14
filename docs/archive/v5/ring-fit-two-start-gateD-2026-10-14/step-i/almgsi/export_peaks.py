# Export the sidecar's saved peaks and fitted origin maps as raw little-endian binaries for the Swift harness (bvm.swift).
# Conventions mirrored (BraggVectorEMDWriter.swift loadPeakGrid, lines ~699-870): x = Float(record.qy), y = Float(record.qx), intensity = Float(record.intensity);
# flat scan index = row-major over the (330,330) object array (scanHeight = shape[0], scanWidth = shape[1]).
# Origin maps (Calibration.swift appOriginMaps, ~1015-1030): fittedX = Float(qy0), fittedY = Float(qx0), flat row-major over (330,330).
import h5py, numpy as np
f = h5py.File("/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References/training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.mac4dstem.h5", "r")
r = f['braggvectors_root']
d = r['braggvectors/_v_uncal/data']
H, W = d.shape
counts = np.zeros(H * W, np.int32); xs = []; ys = []; ws = []
for i in range(H):
    for j in range(W):
        a = d[i, j]
        counts[i * W + j] = len(a)
        if len(a):
            xs.append(a['qy'].astype(np.float32)); ys.append(a['qx'].astype(np.float32)); ws.append(a['intensity'].astype(np.float32))
x = np.concatenate(xs); y = np.concatenate(ys); w = np.concatenate(ws)
print('scan', H, W, 'peaks', len(x), 'positions with 0 peaks', int((counts == 0).sum()), 'max per position', counts.max())
print('x range', x.min(), x.max(), 'y range', y.min(), y.max(), 'finite', bool(np.isfinite(x).all() and np.isfinite(y).all() and np.isfinite(w).all()), 'w min/max', w.min(), w.max())
with open('s2_peaks.bin', 'wb') as o:
    o.write(counts.astype('<i4').tobytes()); o.write(x.astype('<f4').tobytes()); o.write(y.astype('<f4').tobytes()); o.write(w.astype('<f4').tobytes())
c = r['metadatabundle/calibration']
qx0 = c['qx0'][()]; qy0 = c['qy0'][()]
assert qx0.shape == (H, W) and qy0.shape == (H, W)
qy0.astype('<f4').reshape(-1).tofile('s2_fittedX.f32')   # app x = column = py4DSTEM qy
qx0.astype('<f4').reshape(-1).tofile('s2_fittedY.f32')   # app y = row = py4DSTEM qx
print('qx0 mean(f64)', qx0.mean(), 'qy0 mean(f64)', qy0.mean(), 'scalars qx0_mean', c['qx0_mean'][()], 'qy0_mean', c['qy0_mean'][()])
# sequential float32 sum like Swift's reduce(0,+)
for nm, a in (('fittedX(qy0)', qy0), ('fittedY(qx0)', qx0)):
    s = np.float32(0)
    for v in a.astype(np.float32).reshape(-1): s = np.float32(s + v)
    print(nm, 'sequential-float32 mean', np.float32(s / np.float32(a.size)))
