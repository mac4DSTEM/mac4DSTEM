import h5py, json, collections, sys
S = sys.argv[1]
rows = [json.loads(l) for l in open(S + '/ownerdata/emd_scan.jsonl') if l.strip().startswith('{')]
rows = [r for r in rows if r.get('SpectrumStream')]
c = collections.Counter(); bad = []
for r in rows:
    p = '<owner-ssd>/' + r['path']
    try:
        with h5py.File(p, 'r') as f:
            info = f['Info'][()] if 'Info' in f else None
            app = json.loads(bytes(info[0] if hasattr(info, '__len__') else info).decode()).get('applicationVersion', '?') if info is not None else 'none'
            ver = json.loads(bytes(f['Version'][()][0]).decode()).get('version')
            for u, g in f['Data/SpectrumStream'].items():
                d = g['Data']
                c[('velox', app.split('-')[0], 'emd', ver, 'comp', d.compression, 'flt', tuple(d._filters.keys()) if hasattr(d, '_filters') else None, 'FLT' , 'FrameLocationTable' in g, 'chunks', d.chunks)] += 1
    except Exception as e:
        bad.append((r['path'][-60:], repr(e)[:80]))
for k, v in c.most_common(): print(v, k)
print('errors', len(bad), bad[:5])
