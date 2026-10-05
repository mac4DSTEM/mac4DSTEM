import h5py, json, sys
import numpy as np
def col(md, j):
    b = md[:, j].tobytes().split(b'\x00')[0]
    return json.loads(b.decode('utf-8'))
for path in sys.argv[1:]:
    with h5py.File(path, 'r') as f:
        ss = f['Data/SpectrumStream']; u = list(ss)[0]; g = ss[u]
        md = g['Metadata'][()]  # (60000, nFrames) uint8, small
        n = md.shape[1]
        rows = []
        for j in range(n):
            d = col(md, j)
            cp = d.get('CustomProperties', {})
            a13 = float(cp.get('Scan.ScanTransformation.A13', {}).get('value', 'nan'))
            a23 = float(cp.get('Scan.ScanTransformation.A23', {}).get('value', 'nan'))
            sc = float(d['Optics'].get('ScreenCurrent', 'nan'))
            dets = d.get('Detectors', {})
            lt = [float(v.get('LiveTime', 'nan')) for k, v in dets.items() if 'LiveTime' in v]
            rows.append((a13, a23, sc, lt[0] if lt else float('nan')))
        r = np.array(rows)
        bd = d['BinaryResult'] if 'BinaryResult' in d else {}
        print('=====', path.split('/')[-1], 'frames', n)
        print(' pix', d.get('BinaryResult', {}).get('PixelSize'), 'scan', d.get('Scan', {}).get('ScanSize'), 'area', d.get('Scan', {}).get('ScanArea'))
        print(' A13 first/mid/last', r[0,0], r[n//2,0], r[-1,0], 'min/max', np.nanmin(r[:,0]), np.nanmax(r[:,0]))
        print(' A23 first/mid/last', r[0,1], r[n//2,1], r[-1,1], 'min/max', np.nanmin(r[:,1]), np.nanmax(r[:,1]))
        print(' monotone A13?', bool(np.all(np.diff(r[:,0])<=1e-12) or np.all(np.diff(r[:,0])>=-1e-12)))
        print(' ScreenCurrent first/last (A)', r[0,2], r[-1,2])
        print(' LiveTime col0/last', r[0,3], r[-1,3])
        print(' FullScanFOV', d['Optics'].get('FullScanFieldOfView'), 'ScanRotation', d['Scan'].get('ScanRotation'))
        pass
        for top in ('Application', 'Info'):
            if top in f:
                print(' /'+top, (list(f[top].keys())[:10] if hasattr(f[top],'keys') else bytes(np.asarray(f[top][()]).ravel()[0])[:300] if f[top].dtype.kind in 'SO' else f[top].shape))
