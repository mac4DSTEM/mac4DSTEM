# Independent float64 numpy mirror of calibrated(...).map(...) (DiskDetection.swift:711,746), compared with the Swift harness output.
import numpy as np
n = 330 * 330
raw = open('s2_peaks.bin', 'rb').read()
counts = np.frombuffer(raw, '<i4', n); N = int(counts.sum())
x = np.frombuffer(raw, '<f4', N, 4 * n).astype(np.float64); y = np.frombuffer(raw, '<f4', N, 4 * n + 4 * N).astype(np.float64); w = np.frombuffer(raw, '<f4', N, 4 * n + 8 * N).astype(np.float64)
fx = np.fromfile('s2_fittedX.f32', '<f4').astype(np.float64); fy = np.fromfile('s2_fittedY.f32', '<f4').astype(np.float64)
scan = np.repeat(np.arange(n), counts)
refx, refy = 31.80266, 31.7953815     # the harness's meanOrigin
X = refx + (x - fx[scan]); Y = refy + (y - fy[scan])     # ellipse nil: offset is (dx, dy)
x0 = np.floor(X).astype(int); y0 = np.floor(Y).astype(int); ffx = X - x0; ffy = Y - y0
out = np.zeros((64, 64))
for xi, yi, ww in ((x0, y0, (1-ffx)*(1-ffy)), (x0+1, y0, ffx*(1-ffy)), (x0, y0+1, (1-ffx)*ffy), (x0+1, y0+1, ffx*ffy)):
    ok = (xi >= 0) & (xi < 64) & (yi >= 0) & (yi < 64)
    np.add.at(out, (yi[ok], xi[ok]), ww[ok] * w[ok])
sw = np.fromfile('s2_bvm.f32', '<f4').reshape(64, 64).astype(np.float64)
print('f64 sum', out.sum(), 'swift sum', sw.sum())
rel = np.abs(out - sw) / np.maximum(out, 1)
print('max |diff|/value over all px', rel.max(), 'at', np.unravel_index(rel.argmax(), rel.shape))
big = out > 1e6
print('pixels >1e6:', int(big.sum()), 'max rel diff there', rel[big].max())
print('argmax f64', np.unravel_index(out.argmax(), out.shape), 'swift', np.unravel_index(sw.argmax(), sw.shape))
