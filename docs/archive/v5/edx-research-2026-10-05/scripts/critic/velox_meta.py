import h5py, json, sys, re
def col(ds, j):
    b = ds[:, j].tobytes().split(b'\x00')[0]
    return json.loads(b.decode('utf-8'))
def flat(d, p=''):
    out = {}
    if isinstance(d, dict):
        for k, v in d.items(): out.update(flat(v, p + k + '.'))
    elif isinstance(d, list):
        for i, v in enumerate(d): out.update(flat(v, p + str(i) + '.'))
    else: out[p[:-1]] = d
    return out
for path in sys.argv[1:]:
    print('=====', path.split('/')[-1])
    with h5py.File(path, 'r') as f:
        v = f['Version'][()]
        print('Version:', v[0] if hasattr(v, '__len__') else v)
        ss = f['Data/SpectrumStream']
        for u in ss:
            g = ss[u]
            print('stream keys', list(g.keys()), 'Data', g['Data'].shape, g['Data'].dtype, 'compression', g['Data'].compression, 'chunks', g['Data'].chunks)
            md = g['Metadata']; n = md.shape[1]
            print('metadata cols', n)
            a = flat(col(md, 0)); b = flat(col(md, n-1))
            diff = sorted(k for k in a if a.get(k) != b.get(k))
            print('keys differing first vs last frame:', diff[:60])
            pat = re.compile(r'drift|shift|current|dose|beam|emission|probe|ScanTransformation|Stage|Version|Software|LiveTime|RealTime|resolution|Fwhm|Elevation|Solid|Collection|Dead', re.I)
            for k in sorted(a):
                if pat.search(k): print('  ', k, '=', str(a[k])[:80], '| last:', str(b.get(k))[:40])
            if 'AcquisitionSettings' in g:
                s = g['AcquisitionSettings'][()]
                s = s[0] if hasattr(s, '__len__') and not isinstance(s, (bytes, str)) else s
                s = s.decode() if isinstance(s, bytes) else s
                print('AcqSettings:', s[:600])
            break
