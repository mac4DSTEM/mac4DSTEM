import h5py, json, sys
import numpy as np
def col(md, j):
    return json.loads(md[:, j].tobytes().split(b'\x00')[0].decode())
def xcorr(a, b):
    a = a - a.mean(); b = b - b.mean()
    w = np.outer(np.hanning(a.shape[0]), np.hanning(a.shape[1]))
    F = np.fft.fft2(a*w) * np.conj(np.fft.fft2(b*w)); F /= np.abs(F) + 1e-9
    c = np.fft.ifft2(F).real
    i = np.unravel_index(np.argmax(c), c.shape)
    sh = [ (i[k] if i[k] <= c.shape[k]//2 else i[k]-c.shape[k]) for k in range(2)]
    return sh, c.max()
path = sys.argv[1]
with h5py.File(path, 'r') as f:
    imgs = f['Data/Image']
    for u in imgs:
        ds = imgs[u]['Data']
        md = imgs[u]['Metadata']
        d0 = col(md, 0)
        det = d0.get('BinaryResult', {}).get('Detector')
        if ds.ndim == 3 and ds.shape[2] > 1 and det in ('HAADF',):
            n = ds.shape[2]
            print('HAADF', ds.shape, ds.dtype, 'chunks', ds.chunks)
            f0 = ds[:, :, 0].astype(float)
            for j in [1, n//4, n//2, n-1]:
                fj = ds[:, :, j].astype(float)
                sh, pk = xcorr(f0, fj)
                dj = col(md, j); cp = dj.get('CustomProperties', {})
                a13 = cp.get('Scan.ScanTransformation.A13', {}).get('value'); a23 = cp.get('Scan.ScanTransformation.A23', {}).get('value')
                print(f' frame {j}: measured shift (axis0, axis1) px = {sh}, peak {pk:.3f}; image-md A13={a13} A23={a23}')
            break
# block sums for SNR
with h5py.File(path, 'r') as f:
    for u in f['Data/Image']:
        g = f['Data/Image'][u]; ds = g['Data']
        if ds.ndim == 3 and ds.shape[2] > 1 and col(g['Metadata'], 0).get('BinaryResult', {}).get('Detector') == 'HAADF':
            n = ds.shape[2]; B = 10
            ref = ds[:, :, 0:B].astype(float).sum(2)
            # self-noise check: odd vs even frames in first block
            ev = ds[:, :, 0:B:2].astype(float).sum(2); od = ds[:, :, 1:B:2].astype(float).sum(2)
            print(' even-vs-odd (first block):', xcorr(ev, od))
            for s in [n//4, n//2, n-B]:
                blk = ds[:, :, s:s+B].astype(float).sum(2)
                print(f' block {s}-{s+B-1} vs 0-{B-1}:', xcorr(ref, blk))
            # deliberately shifted control
            print(' control roll(+7,-5):', xcorr(ref, np.roll(np.roll(ref, 7, 0), -5, 1)))
            break
