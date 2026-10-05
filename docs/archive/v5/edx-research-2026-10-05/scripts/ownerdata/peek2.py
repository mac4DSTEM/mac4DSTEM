import h5py, sys, json
p=sys.argv[1]
def meta(ds):
    raw=bytes(ds[:,0]).split(b'\x00')[0]
    return json.loads(raw.decode('utf-8','replace'))
with h5py.File(p,'r') as f:
    d=f['Data']
    for t in d.keys():
        sub=d[t]
        print('Data/',t, [ (u, 'grp' if isinstance(sub[u],h5py.Group) else 'ds') for u in list(sub.keys())[:6]])
        for u in list(sub.keys())[:6]:
            gg=sub[u]
            if isinstance(gg,h5py.Group):
                print('  ',u,{kk:(vv.shape,str(vv.dtype)) for kk,vv in gg.items() if isinstance(vv,h5py.Dataset)}, {k:v for k,v in gg.attrs.items()})
    # metadata of SpectrumStream
    for t in ['SpectrumStream','Spectrum','SpectrumImage']:
        if t in d:
            for u in d[t].keys():
                g=d[t][u]
                if isinstance(g,h5py.Group) and 'Metadata' in g:
                    m=meta(g['Metadata'])
                    print('==',t,u, 'metadata keys', list(m.keys()))
                    print(json.dumps(m,indent=1)[:6000])
                    break
