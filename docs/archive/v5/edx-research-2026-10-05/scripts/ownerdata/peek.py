import h5py, sys, json
p=sys.argv[1]
with h5py.File(p,'r') as f:
    print('top:',list(f.keys()))
    for k in f.keys():
        g=f[k]
        if isinstance(g,h5py.Group):
            print(k, list(g.keys())[:20], dict(g.attrs) if len(g.attrs)<10 else 'attrs>10')
    d=f.get('Data')
    if d is not None:
        for t in d.keys():
            sub=d[t]
            print(' Data/',t, len(sub.keys()), 'items')
            for u in list(sub.keys())[:5]:
                gg=sub[u]
                print('   ',u, {kk:(vv.shape,vv.dtype) if isinstance(vv,h5py.Dataset) else 'grp' for kk,vv in gg.items()})
